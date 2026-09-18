# Crash collector

The endpoint TextMate-NG posts crash reports to. A Cloudflare Worker in front of
an R2 bucket; about 150 lines, no database, no dependencies.

It exists because the client half has been written and unreachable since
2026-07-26: the URL it was given resolved to MacroMates' `api.textmate.org`, and
this fork is not affiliated with them, so `AppController` stopped calling it
rather than send a stranger's crash reports to a company that did not ask for
them. This is the J23-owned collector that comment said was needed.

## Deploying

    wrangler r2 bucket create textmate-ng-crash-reports
    wrangler r2 bucket create textmate-ng-crash-reports-preview   # for `wrangler dev`
    wrangler deploy

`wrangler deploy` prints the Worker's URL. That URL is what
`TM_CRASH_COLLECTOR_URL` in `ide/seed_xcodeproj.rb` must be set to; until it is,
the application does not upload anything and the consent prompt never appears.

## What it accepts

One route, `POST /`, whose shape is the client's and not this Worker's:
`multipart/form-data` with a gzipped crash report in `report`, plus short
`hardware` and `contact` strings. It answers `201` with a `Location` of
`/r/<uuid>`, which the client shows to the user in a notification.

`GET /r/<uuid>` returns that report. **Anyone with the URL can read it** — the
id is a random UUID so the URL is unguessable, but there is no login. A crash
report carries the contact string the user typed, their machine model, and the
stack of what was running. The bucket is never listed over HTTP; to read what
has arrived, list it from your own machine:

    wrangler r2 object list textmate-ng-crash-reports
    wrangler r2 object get textmate-ng-crash-reports reports/2026-09-17/<uuid>.gz.json

Each report is stored twice: the gzipped report itself, and a small `.json`
beside it with the hardware string, the contact string and the arrival time, so
that last command answers "what is this" without downloading and unzipping.

## Limits, and what is deliberately missing

Two megabytes per report, 512 characters per text field, control characters
stripped. A report over the limit is refused with `413`, which is a 4xx, which
the client records as sent — a report that size will not shrink on a retry.

There is no authentication. If the endpoint is ever abused as free storage, add
a shared token: a header the client sets and the Worker checks. That is a
ten-line change on each side, and the reason it is not there today is that a
token compiled into a downloadable application is not a secret, so it would buy
only the cost of reading the binary.

There is no retention policy. Reports stay until deleted by hand. R2's lifecycle
rules can do it on a schedule if that changes.

## Testing it without deploying

`bin/test-local` starts `wrangler dev` against the preview bucket and runs the
same requests the application makes, plus the refusals: a body over the limit, a
missing `report` part, a `GET` of something that is not there, and a `PUT`.
