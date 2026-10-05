# Crash collector

The endpoint TextMate-NG posts crash reports to. A Cloudflare Worker in front of
an R2 bucket; about 150 lines, no database, no application dependencies.

It exists because the client half has been written and unreachable since
2026-07-26: the URL it was given resolved to MacroMates' `api.textmate.org`, and
this fork is not affiliated with them, so `AppController` stopped calling it
rather than send a stranger's crash reports to a company that did not ask for
them. This is the J23-owned collector that comment said was needed.

## Deploying

    cf r2 buckets create --name textmate-ng-diagnostics
    cf deploy --secrets-file <file>          # first deploy only — see ADMIN_TOKEN below

**Run `cf deploy` from this directory** — it reads `cloudflare.config.ts` here.
Check `cf auth whoami` first: the collector lives in the J23 Software main
account, the one that owns the `textmate-ng-diagnostics` bucket and the
`j23software.com` zone, and that profile sees only this account — so a deploy
cannot silently reach somewhere crash reports were never meant to go.

The bucket is named `textmate-ng-diagnostics` to sit alongside the other
`*-diagnostics` buckets in this account. `bin/test-local` runs a local dev server
(`cf dev --local`), where miniflare simulates the bucket.

The Worker answers on one canonical custom domain,
`https://textmate-ng-diagnostics.j23software.com`, rather than a per-account
`workers.dev` subdomain — so moving Cloudflare accounts again never changes the
URL. That URL goes in `TMCrashCollectorURL` in
`Applications/TextMate/Info.plist` — the plist rather than a preference, so that
where crash reports go is covered by the code signature. Until it is filled in,
the application uploads nothing and never asks.

`ADMIN_TOKEN` (the read-side token for `GET /list`, below) is a real secret and
is not in `cloudflare.config.ts`. Supply it on the first deploy with `cf deploy
--secrets-file <path>`, where the file holds a line `ADMIN_TOKEN=<value>`. With
it unset the listing route answers `404`.

## What it accepts

One route, `POST /`, whose shape is the client's and not this Worker's:
`multipart/form-data` with a gzipped crash report in `report`, plus short
`hardware` and `contact` strings. It answers `201` with a `Location` of
`/r/<uuid>`, which the client shows to the user in a notification.

`GET /r/<uuid>` returns that report. **Anyone with the URL can read it** — the
id is a random UUID so the URL is unguessable, but there is no login. A crash
report carries the contact string the user typed, their machine model, and the
stack of what was running.

## Reading what has arrived

    bin/reports              # everything, newest first
    bin/reports 2026-09      # one month

Each report is stored twice: the gzipped report itself, and a small `.json`
beside it with the hardware string, the contact string and the arrival time.
`bin/reports` shows the sidecars and never downloads a report, so listing what
arrived does not mean reading anyone's stack.

It goes through the Worker's `GET /list`, not through the R2 object verbs,
because those cannot do this: each `cf r2 objects get/put/delete` needs a key you
already hold, whereas these keys contain a UUID that exists nowhere but in the
notification shown to whoever crashed, and a bucket's `object_count` lags badly
enough that it cannot answer "did anything arrive" either. The Worker holds the
only binding to the bucket, so the listing comes from there.

`/list` wants the bearer token in `ADMIN_TOKEN`, set as a Worker secret (above).
`bin/reports` reads the same value from the login keychain, so it is never an
argument and never in a file:

    security add-generic-password -a "$USER" -s textmate-ng-collector -w

With `ADMIN_TOKEN` unset the route answers `404`, identically to any unknown
path, so a collector not configured for listing is not advertised by the shape
of its own refusal. Given a key — from `bin/reports` — a single report comes
down with:

    cf r2 objects get textmate-ng-diagnostics reports/2026-09-18/<uuid>.gz > report.gz

## Who can upload

Nothing can prove a shipped binary is genuine, and it is worth saying that
plainly rather than implying otherwise. A shared token in the app bundle is
recoverable with `strings`. App Attest is the one real primitive, and it is not
available here: `DCAppAttestService.shared.isSupported` was measured as `false`
for a Developer ID signed binary with no provisioning profile, on macOS 27.

So the aim is not proof of origin. It is that the endpoint be worth nothing to
anyone else. `POST /` requires the `report` part to be a crash report macOS
wrote about *this* application:

| Check | Refusal |
| --- | --- |
| under 2 MB on the wire | `413` |
| real gzip, and under 16 MB decompressed | `415` |
| two JSON documents separated by a newline | `422` |
| header has `incident_id`, `timestamp`, `bug_type` | `422` |
| body's `codeSigningID` is `com.j23software.TextMate-NG` | `422` |
| body's `codeSigningTeamID` is the project's Team ID | `422` |

The last two are the useful ones. A `.ips` carries `codeSigningID` and
`codeSigningTeamID` in its second document, written by the kernel from the
crashed process's actual code signature rather than by whatever posted it. That
is a stronger thing to demand than a token, which can simply be read out of the
bundle — a forgery here has to be a deliberately constructed crash report
claiming this project's signing identity. It is still not a guarantee, and a
determined person can produce one. What it does stop completely is the endpoint
being useful as free file storage or as a way to fill the bucket with noise,
which is the abuse that actually costs something.

Reports from local Debug builds are refused too, and that is correct: a Debug
build is ad-hoc signed with no Team ID, so only released builds can post.

Both expected values live in `env` in `cloudflare.config.ts`, not in the source,
because the Team ID will change — J23 is enrolled as an individual, and an
organization enrollment reissues it. Change it when the first build signed with
the new one ships, not before, or reports from every build in the field stop
being accepted.

The decompressed cap is enforced while decompressing, not after: a couple of
hundred KB of zeros expands past a gigabyte, so a check that ran afterwards
would already have lost.

**A deploy is not instantly global.** Testing a refusal immediately after
`cf deploy` can reach the previous version and get the old answer; that
happened once while writing these checks, and looked briefly like a hole in
them. Repeat the request before believing it.

## Limits, and what is deliberately missing

Two megabytes per report, 512 characters per text field, control characters
stripped. A report over the limit is refused with `413`, which is a 4xx, which
the client records as sent — a report that size will not shrink on a retry.

There is no authentication on upload. If the endpoint is ever abused as free
storage, add a shared token: a header the client sets and the Worker checks.
That is a ten-line change on each side, and the reason it is not there today is
that a token compiled into a downloadable application is not a secret, so it
would buy only the cost of reading the binary.

There is no retention policy. Reports stay until deleted by hand. R2's lifecycle
rules can do it on a schedule if that changes.

## Testing it without deploying

`bin/test-local` starts `cf dev --local` and runs the same requests the
application makes, plus the refusals: a body over the limit, a missing `report`
part, a `GET` of something that is not there, and a `PUT`.
