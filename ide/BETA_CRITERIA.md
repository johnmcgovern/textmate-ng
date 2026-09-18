# What "beta" will mean

Decided 2026-09-17; criteria 1-3 revised 2026-09-18, when deploying showed that two of their checks named a command that does not exist. Beta is a **stability promise**, not a feature milestone —
the port and the hardening are finished either way, and saying "beta" because
the work is done would be describing this project's state rather than the
software's.

The promise is: *a stranger can use this as their editor for a week and nothing
will lose their work or disappear on them.* That is a claim about evidence, so
each criterion below is something that can be checked rather than judged, and
the version stays `2026.N-alpha.M` until all of them hold.

## The criteria

| # | Criterion | How it is checked | Status 2026-09-18 |
| --- | --- | --- | --- |
| 1 | A crash collector is deployed and the application posts to it | `TMCrashCollectorURL` in Info.plist is non-empty, and `Server/crash-collector/bin/reports` answers | **Met 2026-09-18** — deployed, posted to and read back end to end |
| 2 | Crash reports are arriving, and there are none | `bin/reports`, plus `~/Library/Logs/DiagnosticReports` on every machine running it | **Partly** — collector empty, but no shipped build carries the URL yet, so "none" is not yet evidence |
| 3 | Seven consecutive days of daily use on one build, no crash | The date on the newest crash report versus the release date of the build in use | **Not met** — the clock starts at the first release carrying the collector URL, which has not shipped |
| 4 | The full suite, the sanitizers and the fuzzer are green on the tagged commit | The Sanitizers workflow on that commit, not merely on `master` | **Met** and enforced weekly |
| 5 | The five-minute smoke pass is complete, including the surfaces accessibility cannot reach | By hand: HTML output, the commit window, gutter line numbers, syntax colouring | **Not met, and cannot be met by script** — see below |
| 6 | Nothing unreleased at the tag | `git log <tag>..HEAD` is empty | Met at each release |
| 7 | The updater has been seen installing a build unattended | Observed for alpha.27 on 2026-09-16; must hold for the beta too | **Met once** |

Criterion 5 is the one most likely to be quietly skipped, because it is the only
one a script cannot answer. It is on the list because the two worst regressions
this project has shipped — the Settings crash of alpha.10, and the gutter bug
that survived to alpha.10 — were both invisible to the suite and obvious in the
first second of looking.

**Tried on alpha.29, and here is exactly how far a script gets.** HTML output:
two output windows *do* open (564×684, with the expected chrome), but a
`WKWebView` exposes no `AXWebArea` to this process, so whether anything is
rendered inside them is unknown. Gutter line numbers: the text view exposes no
accessibility children at all, so there is nothing to read. Syntax colouring:
accessibility has no notion of colour. `screencapture` is refused — the screen
recording permission was declined earlier — so there is no picture to fall back
on. Three surfaces, three dead ends; this criterion needs a person to look at a
window, and that is the whole reason it is written down separately.

## What beta will not promise

- **No bugs.** It promises no *known* crashes and a way for unknown ones to
  reach the developer.
- **A frozen interface.** Bundles, settings and key bindings can still change.
- **Support.** One person maintains this.
- **That the C++ engine has been audited.** It has been fuzzed at four entry
  points and run under sanitizers; that is not the same thing, and the
  difference is written down in the handoff rather than smoothed over.

## The version, when it happens

`2026.10-beta.1`. The step from `2026.9-alpha.28` is pinned in
`t_OakCompareVersionStrings.mm` — `test_a_beta_is_newer_than_an_alpha` — because
the unattended update path installs nothing that is not strictly newer, and a
beta that did not compare as newer than the last alpha would be refused by every
machine already running one, silently, since anti-rollback is deliberately
quiet. That would be a release that reached nobody and said nothing.

## What is left, in order

1. ~~Deploy the Worker (`Server/crash-collector`), put its URL in Info.plist.~~
   Done 2026-09-18: `https://textmate-ng-crash-collector.developer-c31.workers.dev`,
   verified by posting a report the way the client posts one, reading it back
   byte-identical, and listing it with `bin/reports`. The test report was then
   deleted, so the bucket is empty on purpose rather than by accident.
2. Ship an alpha carrying it, and let it run. **Criterion 2 cannot be read as
   met before this happens**: an empty collector that no build has ever posted
   to looks exactly like an empty collector that nothing has crashed into, and
   only one of those is evidence. Criterion 3's week starts here too.
3. Do the smoke pass properly, the three unreached surfaces included.
4. A week.
5. Tag `2026.10-beta.1`.

A note on criterion 2, learned while deploying. The check was written as
`wrangler r2 object list`, a command that does not exist in any version of
wrangler — so a criterion meant to be mechanically checkable would have failed
at the moment someone first tried to check it, which is the moment it matters.
It is now `bin/reports`, which is in the repository and is run by whoever reads
this. A criterion that names a command nobody has run is a criterion nobody has
checked.
