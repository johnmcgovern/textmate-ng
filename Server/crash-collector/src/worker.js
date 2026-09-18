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
// contact string, their machine model, and the stack of whatever was running.
//
// Which leaves the developer needing a way to see what arrived, and wrangler
// cannot give one: there is no `wrangler r2 object list` — the r2 object verbs
// are get, put and delete, all of which need a key you already have, and the
// keys here contain a UUID nobody has written down. `wrangler r2 bucket info`
// reports an object count, but it is a lagging metric: it still read 0 several
// minutes after two objects were confirmed stored. So the listing has to come
// from the Worker, which is the only thing holding a binding to the bucket.
//
// GET /list does that, behind a bearer token in ADMIN_TOKEN — a wrangler
// secret, never a value in wrangler.toml:
//
//     wrangler secret put ADMIN_TOKEN        (then: bin/reports)
//
// With no ADMIN_TOKEN set the route answers 404, exactly as an unknown path
// does, so an endpoint that was never configured is not advertised by its own
// refusal. The token is compared by SHA-256 digest rather than by string, so
// the comparison takes the same time whatever the guess and leaks nothing
// about length or prefix. /list is the only route that reads the bucket
// wholesale; an unauthenticated request can still only fetch one report whose
// UUID it already knows.
//
// If the POST endpoint is ever abused as free storage, the same token trick
// works there; the limits below are the first line, not the only one available.

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

// Same time whatever the guess, and nothing leaked about the token's length or
// how far a guess got: both sides are hashed to a fixed 32 bytes first, and the
// comparison accumulates differences instead of returning at the first one.
//
// No test covers the accumulate-instead-of-return part, and none can: replacing
// the loop body with an early `return false` survives the whole suite, because
// it is still correct — it answers the same thing, only sooner on a near miss.
// The property is about time, and bin/test-local measures status codes. Left as
// a loop anyway, but the reason it is safe is the hashing above rather than the
// loop: an early exit here would leak which byte of a SHA-256 *digest* differed
// first, which says nothing usable about the token that produced it. The loop
// is the cheaper belt beside that brace, not the thing holding it up.
async function tokenMatches(presented, expected) {
	const encoder = new TextEncoder();
	const [a, b] = await Promise.all([
		crypto.subtle.digest("SHA-256", encoder.encode(presented)),
		crypto.subtle.digest("SHA-256", encoder.encode(expected)),
	]);
	const x = new Uint8Array(a);
	const y = new Uint8Array(b);
	let difference = 0;
	for (let i = 0; i < x.length; i++) {
		difference |= x[i] ^ y[i];
	}
	return difference === 0;
}

async function handleList(request, env, url) {
	// Not configured is not an invitation: answer as though the route does not
	// exist, which is what an unknown path gets.
	if (!env.ADMIN_TOKEN) {
		return null;
	}
	const header = request.headers.get("Authorization") || "";
	const presented = header.startsWith("Bearer ") ? header.slice(7) : "";
	if (!presented || !(await tokenMatches(presented, env.ADMIN_TOKEN))) {
		return text(401, "Unauthorized.", { "WWW-Authenticate": "Bearer" });
	}

	// `reports/` alone lists every day; `?prefix=2026-09` narrows to one month
	// without the caller having to know the key layout.
	const narrow = sanitize(url.searchParams.get("prefix"));
	const prefix = `reports/${narrow}`;
	const limit = Math.min(Math.max(Number(url.searchParams.get("limit") || "50"), 1), 1000);

	// Only the .json sidecars: one small object per report, carrying everything
	// worth listing, so this never reads a crash report to describe it.
	const reports = [];
	let cursor;
	do {
		const page = await env.REPORTS.list({ prefix, cursor, limit: 1000 });
		for (const object of page.objects) {
			if (object.key.endsWith(".gz.json")) {
				reports.push(object.key);
			}
		}
		cursor = page.truncated ? page.cursor : undefined;
	} while (cursor);

	// The day is the second key segment, so a plain descending sort on the key
	// is newest-first; the UUID after it breaks ties arbitrarily but stably.
	reports.sort().reverse();
	const wanted = reports.slice(0, limit);
	const bodies = await Promise.all(wanted.map(async (key) => {
		const object = await env.REPORTS.get(key);
		if (!object) {
			return { key, error: "sidecar vanished between list and get" };
		}
		try {
			return { key, report: key.slice(0, -5), ...JSON.parse(await object.text()) };
		} catch (error) {
			return { key, error: "sidecar is not JSON" };
		}
	}));

	return cors(new Response(JSON.stringify({ total: reports.length, shown: bodies.length, reports: bodies }, null, 1) + "\n", {
		status: 200,
		headers: { "Content-Type": "application/json; charset=utf-8" },
	}));
}

export default {
	async fetch(request, env) {
		const url = new URL(request.url);

		if (request.method === "POST" && url.pathname === "/") {
			return handlePost(request, env);
		}

		if (request.method === "GET" && url.pathname === "/list") {
			const listing = await handleList(request, env, url);
			// null means "no ADMIN_TOKEN configured" — fall through to the 404.
			if (listing) {
				return listing;
			}
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
