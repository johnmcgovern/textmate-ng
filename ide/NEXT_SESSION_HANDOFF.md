# Next-session handoff — TextMate-NG

_Snapshot at end of session 2026-08-02. Point-in-time; when it disagrees with the
git log or the docs below, trust those._

## Where things stand (updated 2026-08-02)

- **Phase 2 is DONE.** Stream 3 (signing & notarization) landed: Developer ID
  `John McGovern (R22V2H7QF4)`, `bin/notarize` drives `notarytool`, and shipped
  builds are notarized and stapled. Build a release with
  `TM_CODE_SIGN_IDENTITY`/`TM_DEVELOPMENT_TEAM` set, then run `bin/notarize`.
- **The app ships as `TextMate-NG.app`, id `com.j23software.TextMate-NG`**
  (id moved 2026-08-03, for alpha.6). The *target* is still named `TextMate` and
  must stay that way — renaming it drags `PRODUCT_MODULE_NAME` to `TextMate_NG`
  and breaks `#import "TextMate-Swift.h"` (`102162ec`) — so the id is now a
  **literal** in the seed rather than derived from `${TARGET_NAME}`.
  The old note here said the id "must not move again"; it moved once more, on
  purpose, to match the product name while the audience was still alpha-only.
  Now it does match, so there is no third move worth making.
- **Three releases shipped 2026-08-02:** alpha.3 (fixes + Swift ports), alpha.4
  (first notarized build), alpha.5 (the rename). Latest tag: `v2026.7-alpha.5`.
- **459 tests across 33 bundles**, green. Re-measure by summing each bundle's own
  `Executed N tests`; do not increment the documented figure.
- **QuickLook works again, as a Preview Extension (2026-08-03).** Legacy
  `.qlgenerator`s no longer load from *any* third-party app on this macOS, so it
  was rewritten as a sandboxed `TextMateQL.appex` in `Contents/PlugIns`. The
  scary part — moving the app's storage into an app-group container — turned out
  to be unnecessary: `temporary-exception` entitlements let the sandboxed
  extension read the real paths. A throwaway probe extension established that in
  one run; write one before scoping this kind of work. Full notes in
  `PROJECT_PHASES.md` under "Phase 2.6 — QuickLook".
- **The "About box shows 2.0.23" bug was never a bug.** That window belonged to
  the *installed upstream TextMate*, which answered the About click while both
  apps presented identically in the menu bar. The alpha.5 rename makes the
  mixup impossible. Beware generally: with upstream installed, confirm *which*
  app you are looking at before believing a UI screenshot.

## Where things stood at 2026-07-26

- **Branching: trunk-based, single branch.** Everything lives on `master`, which
  is in sync with `GH-johnmcgovern/master`. The old `claude/xcode-stream1-seed`
  and `claude/upbeat-galileo-eae114` branches were merged and deleted on
  2026-07-26 (tips were `0fba3af2` and `119d34a1` if anything ever needs
  recovering). Work on `master` and push; the solo-developer preference is to
  land changes on trunk regularly rather than accumulate long-lived branches.
- **Phase 2 streams 1, 2, 4, 5, 6: DONE.** Stream 3 (signing/notarization) is the
  only stream left and is blocked on the user's Apple Developer certificates.
- **The app really works.** `xcodebuild -target TextMate` produces an ad-hoc
  signed `TextMate.app` that launches, opens and edits documents, runs bundle
  commands, and renders HTML output with its stylesheets, scripts and images.
  Verified interactively, not inferred.
- **Branding:** TextMate-NG, calendar-versioned (`2026.7-alpha.1`), own icon.
  The version is the newest `## <date> (vX)` heading in
  `Applications/TextMate/about/Changes.md` — both build systems grep it, so
  adding a heading *is* the version bump.

## The one lesson this project keeps re-learning

**A green `xcodebuild` and a passing `codesign --verify --deep --strict` prove the
bundle is internally consistent. They do not prove it works.** Three separate
defects of exactly this shape were found in one session, each in an app that
built and signed perfectly:

1. Xibs were never compiled → the app could not launch at all.
2. Framework resources were never copied → Bundle Editor and Preferences had no
   nibs.
3. `-ObjC` was missing → *every* Objective-C category was stripped, so File ▸ New
   silently did nothing.

Run the binary. Open a document. Click the thing.

A fourth instance of the same shape turned up on 2026-07-26: the `bl` tool had
**never once compiled** in the Xcode project. Nothing depended on it, so nothing
ever asked it to build, and its absence was invisible until Stream 8 made the app
depend on it. A target existing in the project is not evidence it builds — only
`AllLibs`, the app, and now the test bundles are actually exercised.

Two diagnostic traps that cost real time, both worth remembering:

- `nm`/`otool` finding a **selector name** proves nothing — callers put selector
  names in the method-name table. Only `__objc_catlist` shows whether a category
  implementation linked.
- `mate` addresses TextMate by bundle id, so with an upstream TextMate.app
  installed it may drive *that* one. Use `open -a <path>` to be certain which
  binary you are testing.
- **`open -a <path>` is only as certain as the path.** The product is
  `build/<config>/TextMate-NG.app` since alpha.5; a pre-rename
  `build/Debug/TextMate.app` sat there for a day afterwards and launched happily,
  running yesterday's code while `xcodebuild` reported the *current* target
  built. It cost half an hour on 2026-08-02 and read exactly like a broken port.
  `build/` is gitignored and disposable — when a run disagrees with a build,
  check the product's mtime first, and delete stale bundles rather than reasoning
  about them.

## Documentation map (read in this order)

1. `PROJECT_PHASES.md` — the 6-phase roadmap. End state = Swift app shell over
   the kept C++ core. Phase 2 is current.
2. `ide/PHASE2_PROGRESS.md` — Stream 1 detail: how the two seed scripts work,
   every solved gotcha, and two corrections to earlier claims that were wrong.
   **Don't re-derive these.**
3. `ide/STREAM5_HOJSBRIDGE_PLAN.md` — the WKWebView migration, complete, with the
   two design questions it answered.
4. `ide/gen_xctest.rb` + `ide/xctest_preamble.h` — how the OAK-style tests become
   XCTest bundles, and why everything compiles as ObjC++ with ARC off.

## How to build and run

```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 RUBYOPT="-EUTF-8"
export PATH="$HOME/.gem/ruby/2.6.0/bin:$PATH"     # xcodeproj gem
ruby ide/extract_specs.rb > ide/gen/specs.json && ruby ide/seed_xcodeproj.rb
xcodebuild -project TextMate.xcodeproj -target TextMate -configuration Release build
open -a "$PWD/build/Release/TextMate-NG.app"     # target TextMate, product TextMate-NG
```

Tests (25 bundles, 275 green):

```bash
xcodebuild test -project TextMate.xcodeproj -scheme AllTests -configuration Debug
```

Requires Xcode selected (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`)
and `brew install capnp ragel ninja multimarkdown boost google-sparsehash`.

## What's next

**`KEventManager` is ported (2026-08-02), so TMFileReference is finished** —
nothing in the framework is ObjC++ any more, only `FileItemImage.mm`'s 27-line C
function, which stays by design. Details in `PROJECT_PHASES.md` under "Phase 4 —
TMFileReference"; the short version is that behaviour is unchanged, the 4 tests
from `d7ad0835` pass against the Swift through the untouched ObjC header, and the
watcher was watched working in the running app.

**One planned-for obstacle turned out not to exist, and the handoff was the thing
that was wrong:** `fcntl(fd, F_GETPATH, &buf)` needs no shim. C-variadics really
are unimportable, but the POSIX ones (`open`, `fcntl`, `ioctl`, `sem_open`) have
hand-written non-variadic overloads in the Darwin overlay. A 10-line probe
settled it in a minute. **Probe before believing a wall recorded in prose.**

**The QuickLook `.appex`-or-delete decision is settled: rewritten, 2026-08-03.**

**Next: MenuBuilder** (399 lines, survey score 1).

Verified in Finder itself on 2026-08-03 (not just `qlmanage`): the space-bar
panel and the column-view preview both highlight C, JSON, Ruby, Markdown and
shell files, plain text falls back correctly, and a type we do not claim is left
to the system. Swift previews *unhighlighted* — there is no Swift bundle in the
installed set, so no grammar matches; the editor would be equally unhighlighted,
and the fix is a bundle, not code.

Three loose ends the QuickLook work leaves, none blocking:

- **The first preview in a protected folder raises a privacy prompt** ("access
  files on your Desktop", attributed to TextMate-NG), once per location. The
  experiment for removing it was run on 2026-08-03 and **failed**: narrowing the
  entitlement from `/` to the two real subpaths (plus the `passwd_entry()` fix
  that allowed it) leaves the prompt exactly where it was. Both changes were
  kept anyway — smaller grant, real bug fix — but do not expect a quiet first
  run from that direction. What the run did establish is that the preview
  renders whether or not the prompt is answered; a denial costs only per-folder
  `.tm_properties` settings. Details in `PROJECT_PHASES.md`.

- **The extension has no automated coverage.** Nothing did before either — the
  old generator had none — but `TMQLCreateAttributedString` is now an ordinary
  function taking a URL and returning an attributed string, so it is testable in
  a way the CFPlugIn entry points never were. It needs a bundle index in the test
  environment, which is the part to think about.
- **A thumbnail extension is a separate extension point.** The legacy generator
  also drew Finder icon thumbnails (`GenerateThumbnailForURL`); that half was
  dropped rather than ported, because `com.apple.quicklook.thumbnail` is its own
  `.appex` target. Nothing depends on it, and the system draws generic icons as
  it already has been since the generator stopped loading.

**Stream 3 — DONE 2026-08-02.** Developer ID + notarization work end to end;
see `PROJECT_PHASES.md` "Open decisions". Nothing here needs the user any more.

**Decided 2026-07-26: arm64-only**, not universal2 — rationale in
`PROJECT_PHASES.md` under "Decided". Release now pins `ONLY_ACTIVE_ARCH=NO` so a
shipped build is arm64 regardless of the build host.

**rave/ninja is retired (2026-07-26, tag `rave-final`)** — both blockers cleared
(Streams 7 & 8), the parity audit found no functional gap, and the build tooling
(`bin/rave`, `bin/gen_build`, `bin/gen_test`, `bin/notarize_await`,
`bin/expand_variables`, `bin/extract_changes`, `bin/update_changes`, `configure`,
`.travis.yml`, `local-orig.rave`, the ninja CI job) is deleted. **Not** deleted:
the `.rave` spec files (`ide/extract_specs.rb`'s live input — see "Stage B" in
`PROJECT_PHASES.md`) and `bin/gen_html` (the About-pages build phase needs it now).
`bin/CxxTest` was kept at the time but has since been deleted in Phase 2.5, once the
4 GUI suites that needed it became real tests.

- **Editor support for this repo's own code:** `.tm_properties`' `TM_FRAMEWORK_INCLUDE`
  now points at `ide/gen/include/<fw>/<fw>` (the Xcode seed's farm) instead of
  rave's `_Include/<fw>/include`. Run the two `ruby` seed commands once to
  populate it before relying on in-editor diagnostics for this project's own
  C++/ObjC++ code.
- **Not attempted:** rebuilding TextMate's own ⌘B-to-build integration against
  Xcode. `.tm_properties`' dead `TM_NINJA_TARGET` bindings were removed rather than
  replaced — that's new feature work, not cleanup, and nobody asked for it yet.

Two follow-ups fell out of that work, neither blocking:
- **13 skipped tests.** Listed with reasons in `SKIPPED_TESTS`
  (`ide/seed_xcodeproj.rb`). Mostly environmental or stale fixtures, but one is a
  real memory-safety bug: `cf/tests/t_rect.cc`'s `from_str(".........")` underflows
  `size_t` into a huge `CGRect` and writes off the end of its canvas.
- **The 3 GUI suites don't assert.** They compile but XCTest can't run them, and
  they'd hang if it could. Rewriting them into real tests would be the only
  automated coverage the ObjC++ UI layer has before Phase 4.

**Then Phase 3** (Swift interop foundation): enable Clang modules — Phase 2 sets
`CLANG_ENABLE_MODULES=NO` and Swift needs them — module maps, C++ interop mode,
bridging header, and the first `.swift` file.

## Guardrails

- Edit the **generator** (`ide/*.rb`), not the generated `TextMate.xcodeproj`.
- Gitignored, regenerated, never committed: `TextMate.xcodeproj/`, `build/`,
  `ide/gen/`.
- `PlugIns/dialog` and the other submodules are out of scope for edits.
- Commit messages carry a `Co-Authored-By:` trailer. Ask before pushing.
