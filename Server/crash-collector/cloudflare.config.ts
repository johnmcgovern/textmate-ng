import { bindings, defineConfig } from "cf/config";
import * as entrypoint from "./src/worker.js" with { type: "cf-worker" };

// Deploy with:  cf deploy        — **from this directory**, authenticated (cf auth
// whoami) to the account that owns the textmate-ng-diagnostics R2 bucket. This
// replaced the old wrangler.toml when the collector moved to the J23 Software main
// account; cf's login is per profile, and that profile sees only the one account,
// so a deploy cannot silently reach somewhere crash reports were never meant to go.
//
// Create the bucket once, first:  cf r2 buckets create --name textmate-ng-diagnostics
//
// ADMIN_TOKEN (read-side auth for bin/reports) is a real secret and is NOT in here —
// set it after the first deploy with `cf workers secrets` (or `cf deploy
// --secrets-file`). With it unset the admin route answers 404, which is the safe
// default: the Worker never lists the bucket over HTTP.

export default defineConfig({
	worker: {
		name: "textmate-ng-crash-collector",
		// Not today's date: the local `cf dev` runtime refuses a date newer than the
		// workerd it ships with, and bin/test-local is the only thing that runs this
		// Worker before it is deployed.
		compatibilityDate: "2026-07-01",
		entrypoint,
		observability: { enabled: true },
		// The collector's one canonical endpoint, on the J23 Software domain rather
		// than a per-account workers.dev subdomain — so moving Cloudflare accounts
		// again never changes the URL baked into shipped builds. cf creates the DNS
		// record on the (active) j23software.com zone. workers.dev is off: one address.
		workersDev: false,
		domains: ["textmate-ng-diagnostics.j23software.com"],
		env: {
			// The R2 binding the Worker writes reports through. Private bucket; the
			// Worker is the only thing that reads or writes it.
			REPORTS: bindings.r2({ name: "textmate-ng-diagnostics" }),

			// What a crash report must say about itself to be accepted — compared
			// against the report's own code-signature fields. EXPECTED_TEAM_ID will
			// change if J23 re-enrolls as an organization (a new Team ID); that is the
			// edit, plus a redeploy, when the first build under the new team ships.
			EXPECTED_SIGNING_ID: bindings.text("com.j23software.TextMate-NG"),
			EXPECTED_TEAM_ID: bindings.text("R22V2H7QF4"),

			// Read-side admin auth; value set out-of-band (see note above).
			ADMIN_TOKEN: bindings.secret(),
		},
	},
});
