// The crash collector TextMate-NG posts to.
//
// The client is Frameworks/CrashReporter/src/CrashReporter.swift, and the shape
// of a request is its shape, not one chosen here: a multipart/form-data POST
// with three parts — `report` (a gzipped .ips crash report, sent as a file),
// `hardware` ("MacBookPro18,2/arm64/10"), and `contact` (whatever the user typed
// in Settings, or "Anonymous"). The client treats 2xx as sent and 4xx as "sent
// as far as I am concerned, do not retry", so a refusal this Worker means
// permanently must be a 4xx and a refusal it wants retried must be a 5xx.
//
// It reads the `Location` header of the response and shows it to the user in a
// notification they can click. That URL is /r/<id> below.
//
// **Reports are readable by anyone holding the URL.** The id is a v4 UUID, so
// the URL is unguessable, but there is no account and no login: this is a
// personal collector for one developer's own application, and a crash report is
// not a secret so much as a private thing. What it does contain is the user's
// contact string, their machine model, and the stack of whatever was running —
// which is why nothing here ever lists the bucket over HTTP. To read the
// reports, list the bucket from your own machine:
//
//     wrangler r2 object list textmate-ng-crash-reports
//
// If the endpoint is ever abused as free storage, the fix is a shared token in
// a header the client sends; the limits below are the first line, not the only
// one available.

const MAX_BODY_BYTES = 2 * 1024 * 1024;   // a gzipped .ips is tens of KB; 2 MB is generous
const MAX_FIELD_CHARS = 512;              // hardware and contact are short strings
const RETENTION_NOTE = "reports are kept until deleted by hand";

function cors(response) {
	// The client is a native application and sends no Origin, so this is only
	// for a browser opening a /r/ link.
	response.headers.set("X-Content-Type-Options", "nosniff");
	return response;
}

function text(status, body, extraHeaders = {}) {
	return cors(new Response(body + "\n", {
		status,
		headers: { "Content-Type": "text/plain; charset=utf-8", ...extraHeaders },
	}));
}

// A short, readable string with nothing in it that could confuse a log reader or
// an object key. Control characters out, length capped.
function sanitize(value) {
	if (typeof value !== "string") {
		return "";
	}
	return value.replace(/[\u0000-\u001F\u007F]/g, " ").trim().slice(0, MAX_FIELD_CHARS);
}

async function handlePost(request, env) {
	const declaredLength = Number(request.headers.get("Content-Length") || "0");
	if (declaredLength > MAX_BODY_BYTES) {
		// 413 is a 4xx, so the client records the report as sent and stops
		// offering it. That is the intent: a report this size will not get
		// smaller on a retry.
		return text(413, `Report too large (${declaredLength} bytes, limit ${MAX_BODY_BYTES}).`);
	}

	let form;
	try {
		form = await request.formData();
	} catch (error) {
		return text(400, "Expected multipart/form-data.");
	}

	const report = form.get("report");
	if (!report || typeof report === "string") {
		return text(400, "Expected a `report` file part.");
	}

	const body = await report.arrayBuffer();
	if (body.byteLength === 0) {
		return text(400, "The `report` part was empty.");
	}
	if (body.byteLength > MAX_BODY_BYTES) {
		return text(413, `Report too large (${body.byteLength} bytes, limit ${MAX_BODY_BYTES}).`);
	}

	const id = crypto.randomUUID();
	const received = new Date();
	const day = received.toISOString().slice(0, 10);
	const key = `reports/${day}/${id}.gz`;

	const metadata = {
		id,
		receivedAt: received.toISOString(),
		filename: sanitize(report.name) || "report.gz",
		hardware: sanitize(form.get("hardware")),
		contact: sanitize(form.get("contact")),
		userAgent: sanitize(request.headers.get("User-Agent")),
		bytes: body.byteLength,
	};

	await env.REPORTS.put(key, body, {
		httpMetadata: {
			contentType: "application/gzip",
			contentDisposition: `attachment; filename="${metadata.filename}"`,
		},
		// R2 custom metadata values must be strings.
		customMetadata: {
			hardware: metadata.hardware,
			contact: metadata.contact,
			receivedAt: metadata.receivedAt,
		},
	});

	// The metadata alongside the report, so `wrangler r2 object get` on one
	// small JSON file answers "what was this" without unzipping anything.
	await env.REPORTS.put(`${key}.json`, JSON.stringify(metadata, null, 1), {
		httpMetadata: { contentType: "application/json" },
	});

	const location = new URL(request.url);
	location.pathname = `/r/${id}`;
	location.search = "";

	return cors(new Response(JSON.stringify({ id, bytes: body.byteLength, note: RETENTION_NOTE }, null, 1) + "\n", {
		status: 201,
		headers: {
			"Content-Type": "application/json; charset=utf-8",
			"Location": location.toString(),
		},
	}));
}

async function handleGet(request, env, id) {
	// The day is part of the key but not of the URL, so find it. A list prefixed
	// by `reports/` is bounded by how many reports exist, which for a personal
	// collector is small; if it ever is not, store an id → key pointer on write.
	const listed = await env.REPORTS.list({ prefix: "reports/" });
	const match = listed.objects.find((object) => object.key.endsWith(`/${id}.gz`));
	if (!match) {
		return text(404, "No such report.");
	}

	const object = await env.REPORTS.get(match.key);
	if (!object) {
		return text(404, "No such report.");
	}

	const headers = new Headers();
	object.writeHttpMetadata(headers);
	headers.set("etag", object.httpEtag);
	return cors(new Response(object.body, { headers }));
}

export default {
	async fetch(request, env) {
		const url = new URL(request.url);

		if (request.method === "POST" && url.pathname === "/") {
			return handlePost(request, env);
		}

		const report = url.pathname.match(/^\/r\/([0-9a-fA-F-]{36})$/);
		if (request.method === "GET" && report) {
			return handleGet(request, env, report[1]);
		}

		if (request.method === "GET" && url.pathname === "/") {
			// Deliberately says nothing about what is stored.
			return text(200, "TextMate-NG crash collector.");
		}

		if (request.method === "GET" || request.method === "HEAD") {
			return text(404, "Not found.");
		}
		return text(405, "Method not allowed.", { "Allow": "GET, POST" });
	},
};
