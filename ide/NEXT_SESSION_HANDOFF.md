# Next-session handoff — TextMate-NG

_Snapshot at end of session 2026-07-26. Point-in-time; when it disagrees with the
git log or the docs below, trust those._

## Where things stand

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
open -a "$PWD/build/Release/TextMate.app"
```

Tests (25 bundles, 275 green):

```bash
xcodebuild test -project TextMate.xcodeproj -scheme AllTests -configuration Debug
```

Requires Xcode selected (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`)
and `brew install capnp ragel ninja multimarkdown boost google-sparsehash`.

## What's next

**Needs the user:**
- **Stream 3 — signing & notarization.** Real certificates. Also requires moving
  `CFBundleIdentifier` off `com.macromates.*`, which will orphan existing
  preferences and window state, so pick the moment deliberately. Held
  deliberately: the identity is being designed for J23 Technologies as a whole,
  not just this repo. Note rave's notarize flow used the retired `altool` —
  build Stream 3 on `notarytool` from scratch.

**Decided 2026-07-26: arm64-only**, not universal2 — rationale in
`PROJECT_PHASES.md` under "Decided". Release now pins `ONLY_ACTIVE_ARCH=NO` so a
shipped build is arm64 regardless of the build host.

**rave/ninja is retired (2026-07-26, tag `rave-final`)** — both blockers cleared
(Streams 7 & 8), the parity audit found no functional gap, and the build tooling
(`bin/rave`, `bin/gen_build`, `bin/gen_test`, `bin/notarize_await`,
`bin/expand_variables`, `bin/extract_changes`, `bin/update_changes`, `configure`,
`.travis.yml`, `local-orig.rave`, the ninja CI job) is deleted. **Not** deleted:
the `.rave` spec files (`ide/extract_specs.rb`'s live input — see "Stage B" in
`PROJECT_PHASES.md`), `bin/CxxTest` (the 3 GUI suites still compile against it),
and `bin/gen_html` (the About-pages build phase needs it now).

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
