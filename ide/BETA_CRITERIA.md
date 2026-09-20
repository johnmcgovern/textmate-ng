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

| # | Criterion | How it is checked | Status 2026-09-19 |
| --- | --- | --- | --- |
| 1 | A crash collector is deployed and the application posts to it | `TMCrashCollectorURL` in Info.plist is non-empty, and `Server/crash-collector/bin/reports` answers | **Met 2026-09-18** — deployed, posted to and read back end to end |
| 2 | Crash reports are arriving, and there are none | `bin/reports`, plus `~/Library/Logs/DiagnosticReports` on every machine running it | **Partly** — collector empty, but no shipped build carries the URL yet, so "none" is not yet evidence |
| 3 | Seven consecutive days of daily use on one build, no crash | The date on the newest crash report versus the release date of the build in use | **Not met** — the clock starts at the first release carrying the collector URL, which has not shipped |
| 4 | The full suite, the sanitizers and the fuzzer are green on the tagged commit | The Sanitizers workflow on that commit, not merely on `master` | **Met** and enforced weekly |
| 5 | The five-minute smoke pass is complete, including the surfaces accessibility cannot reach | `screencapture` of each window, read directly | **Mostly met 2026-09-19** — three of the four surfaces verified; the commit window is **broken**, see below |
| 6 | Nothing unreleased at the tag | `git log <tag>..HEAD` is empty | Met at each release |
| 7 | The updater has been seen installing a build unattended | Observed for alpha.27 on 2026-09-16; must hold for the beta too | **Met once** |

Criterion 5 was the one most likely to be quietly skipped, because it looked
like the only one a script could not answer. That turned out to be wrong, and
the correction is below. It is on the list because the two worst regressions
this project has shipped — the Settings crash of alpha.10, and the gutter bug
that survived to alpha.10 — were both invisible to the suite and obvious in the
first second of looking.

**Settled on alpha.30, 2026-09-19, and the earlier conclusion was wrong.**
The alpha.29 attempt reported three dead ends: a `WKWebView` exposes no
`AXWebArea`, the text view exposes no accessibility children, and accessibility
has no notion of colour. All three are still true, and all three stopped
mattering the moment `screencapture` worked — the screen recording permission
had been declined when that was written and has since been granted. A picture
answers every one of them directly, so this criterion is scriptable after all.

Two things had to be right first, and both had been wrong:

- **The application has to be genuinely frontmost, and idle time does not say
  so.** HIDIdleTime read 614 s while Chrome held focus. With no key window,
  accessibility reported zero windows, `keystroke` went to Chrome instead of the
  editor, and `Open Quickly…` read `enabled false` — which looked like a broken
  surface for three attempts and was only the responder chain doing its job.
  With the app actually frontmost it reads `enabled true`.
- **Windows have to be observed through `CGWindowListCopyWindowInfo`**, not
  `name of every window`. The window server saw every window opening normally
  the whole time accessibility saw none.

What alpha.30 actually showed:

| Surface | Verdict |
| --- | --- |
| Gutter line numbers | **Alive.** 1–47 drawn, with fold arrows at the right lines |
| Syntax colouring | **Alive.** Keywords, strings, comments, numbers and function names all distinct; C++ detected in the status bar |
| HTML output | **Alive.** The window opens at 564×684 *and renders text*, so the command-to-WebKit path works end to end |
| Settings | **Alive.** All six panes clicked through, each with controls, no crash |
| File browser | **Alive.** Tree populated, and it updated live when a file appeared |
| Find, Bundle Editor, Software Update | **Alive**, each opening a window |
| **Commit window** | **BROKEN — see below** |

## The one real defect this found

`Bundles ▸ Git ▸ Commit…` does not open. It fails with

    .../Bundle Support.tmbundle/Support/shared/bin/ruby18: line 43:
    .../TextMate/Ruby/1.8.7/bin/ruby: Bad CPU type in executable

The Ruby that ships with the bundles is `Mach-O 64-bit executable x86_64`, and
Rosetta is not installed on this machine: `arch -x86_64 /usr/bin/true` fails the
same way and `oahd` is not running. **216 of the 380 installed bundle commands
invoke `ruby18`**, across 29 bundles — the whole Git bundle (36), Markdown's
Show Preview, most of Objective-C, Mercurial, PHP and Ruby.

This is not a regression in alpha.30; nothing in this release goes near it. It
is also not only a build-machine problem. Apple Silicon Macs do not ship with
Rosetta, and the on-demand install prompt appears for *application bundles*, not
for a shell script that execs an x86 binary — so a user on a clean Apple Silicon
Mac gets this same failure with no offer to fix it, and more than half of the
bundle commands are dead for them.

`softwareupdate --install-rosetta` fixes it on a given machine. That is a
decision about what the application should require, not a build step, which is
why it is written here rather than done: either the beta declares Rosetta a
prerequisite and says so where a user will see it, or those 216 commands need a
Ruby that runs natively.

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
