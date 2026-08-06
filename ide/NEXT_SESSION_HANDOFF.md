# Next-session handoff — TextMate-NG

_Snapshot at end of session 2026-08-05. Point-in-time; when it disagrees with the
git log or the docs below, trust those._

## Where things stand (updated 2026-08-05)

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
  (first notarized build), alpha.5 (the rename). Latest tag: `v2026.7-alpha.6`
  (2026-08-03), and **HEAD is 21 commits past it** — nothing since alpha.6 has
  shipped to anyone. Two of those are user-visible: the Swift grammar now ships
  in the default bundle set (`cbaa5894`), so `.swift` files highlight in the
  editor and in Quick Look, and `passwd_entry()` no longer answers an unreadable
  home with an unclickable modal (`7fbd4a07`).
- **Phase 4 is in Find, and Find is nearly done (2026-08-04/05).** Three of its
  four substantial files are Swift — `FFResultNode`, `FFDocumentSearch`,
  `FFResultsViewController` — each with its tests written *before* the port.
  Only `Find.mm` (1402) is left. The framework went from **zero tests to 50** and
  from 3123 lines of ObjC++ to **2238**. Everything about finishing it is in
  `ide/FIND_PORT_HANDOFF.md`; read that before touching `Find.mm`.
- **509 tests across 34 bundles**, green (2026-08-05; 50 of them Find's, a
  bundle that did not exist three days ago). Re-measure by summing each bundle's own `Executed N tests`; do not
  increment the documented figure. **Match `Executed ([0-9]+) tests?,` — with the
  `s` optional.** xctest prints `Executed 1 test` for single-test suites, and a
  plural-only pattern skips those lines and then mis-attributes the next
  bundle's total, which reads as 500 instead of 484. Cross-check that
  `Test Case … started` and `… passed` counts are equal. Full note in
  `PROJECT_PHASES.md` under the test-count corrections.
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

Tests (34 bundles, 509 green):

```bash
xcodebuild test -project TextMate.xcodeproj -scheme AllTests -configuration Debug
```

Requires Xcode selected (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`)
and `brew install capnp ragel ninja multimarkdown boost google-sparsehash`.

## What's next

**Finish Find: port `Find.mm` (1402 lines), the last substantial file in the
framework.** Read `ide/FIND_PORT_HANDOFF.md` first — it is written for exactly
this task and carries the two decisions to settle before writing any Swift:

1. **`Find.h` contains C++ — and Swift can express it.** `text::range_t` appears
   in two `FindMatch` properties, in its initialiser, and in `FindDelegate`'s
   `-selectRange:inDocument:`; `OakFindServerProtocol` adds `find::options_t` and
   `text::pos_t const&`. Two claims were made about this and **both were wrong**:
   first "no C++ in its headers" (false), then "so it cannot be Swift" (also
   false). Probes on 2026-08-05 showed Swift conforms to the protocol and holds
   `text.range_t` properties under this project's interop mode. **No support file
   is forced.** Two things still need probing first: whether the `FindMatch` ABI
   actually round-trips (compiling is not agreement — see `scm::status::type`),
   and whether Swift can build the `std::multimap` the replace path hands to
   `-performReplacements:`.
2. **`MBCreateMenu` is called twice** (`Find.mm:356`, `:578`) and Swift cannot
   construct its C++ DSL. Hand-roll the two menus, as CommitWindow and
   Preferences already do; do not port MenuBuilder first.

Coverage is partly written: `-acceptMatches:` has 4 tests (`b1595405`). The
find-options assembly (`:881`) and the status-string pluralisation (`:1188`) are
still worth pinning before the port, and both are pure.

**After Find:** `DocumentWindow` (3564, of which 2885 is one window controller
with no tests), then the heavy set — `OakAppKit`, `FileBrowser`, `OakFilterList`.
`MenuBuilder` goes **last**, once its ObjC++ callers are gone. `HTMLOutput` needs
a `std::map` API redesign before it is portable at all.

**alpha.7 shipped 2026-08-06** (`f23dff04`, tag `v2026.7-alpha.7`, 23 commits past
alpha.6), carrying the Swift grammar (`cbaa5894`), the `passwd_entry()` fix
(`7fbd4a07`) and the `FFResultsViewController` port. HEAD is **0 commits past the
tag**. A release is a heading in `Applications/TextMate/about/Changes.md` plus
`bin/notarize`.

Two earlier notes here were wrong about this same count — "five commits, nothing
user-visible", then "21 commits waiting" — both asserted rather than counted.
`git rev-list --count <tag>..HEAD` is the whole of the work.

~~**Then Phase 3** (Swift interop foundation)~~ — **done long ago**; this line
survived from the session that wrote it. Modules, C++ interop mode, bridging
headers and the first `.swift` file all landed, and there are nine Swift
frameworks now.

## Distribution — TODO: publish builds from GitHub

**Nobody can get a build without being handed one.** Seven alphas have been
tagged and notarized, and the only way to install any of them has been a zip
passed directly from this machine. For an open-source project that is the wrong
default, and it came up 2026-08-06 the first time someone outside asked to try
it. `README.md` now points here for the answer, so this section is the answer.

Where it stands today: `bin/notarize` ends by *printing* the packaging command
rather than running it —

```sh
ditto -c -k --keepParent build/Release/TextMate-NG.app TextMate-NG-<version>.zip
```

— and stops there. Everything upstream of that is already automated and already
correct: Developer ID signing, hardened runtime, notarization, stapling, and a
`spctl` check. **The gap is only the last mile**, which is what makes this a
small task rather than a project.

What needs deciding and doing, roughly in order:

1. **`gh release create` against the tag that already exists.** The tags are
   there (`v2026.7-alpha.1` … `.7`); a release attaching the stapled zip is one
   command. Decide whether to backfill the older tags or start at the next one —
   backfilling means re-notarizing builds nobody has, so probably start fresh.
2. **Release notes come from `Applications/TextMate/about/Changes.md`.** The
   newest `## <date> (vX)` section *is* the release note, already written for a
   reader rather than a committer, and the version already derives from that
   heading. Extract the section between the first two `##` headings and pass it
   as the body rather than writing anything a second time.
3. **Extend `bin/notarize`, or add `bin/release` next to it?** Prefer a separate
   `bin/release`: notarizing and publishing are different blast radii, and
   `bin/notarize` is safe to re-run in a way that "create a public release" is
   not. It should refuse to publish an app whose stapled ticket does not validate
   and whose version does not match the tag it is publishing to.
4. **Mark them pre-releases.** These are alphas; GitHub's `--prerelease` flag
   keeps "Latest release" honest and keeps them out of the default download.
5. **Check what the zip actually contains before the first public one.** It is
   built from `build/Release/`, and that directory has held stale artifacts
   before — there is a pre-rename `TextMate.app.dSYM` sitting in it right now.
   The zip is `--keepParent` on the `.app` alone so it should be unaffected, but
   *should* is exactly the word that has cost this project time before. Unzip the
   artifact somewhere clean, run it, and check its version and signature.
6. **Say what the requirements are where the download is.** Apple Silicon and
   macOS 15 are in `README.md`; a release body that omits them will produce a bug
   report from an Intel Mac.

Not in scope, and worth writing down so it does not creep in: **this is not
software update.** Sparkle-style updating stays off until the fork has a server,
and a GitHub Release is not a substitute for one.

## Guardrails

- Edit the **generator** (`ide/*.rb`), not the generated `TextMate.xcodeproj`.
- Gitignored, regenerated, never committed: `TextMate.xcodeproj/`, `build/`,
  `ide/gen/`.
- **Re-seed after editing any test source.** `ide/gen_xctest.rb` generates the
  XCTest bundles at seed time, so `xcodebuild test` alone compiles the *previous*
  version of a test you just changed. Cost a wasted cycle on 2026-08-05 chasing
  errors that had already been fixed.
- `PlugIns/dialog` and the other submodules are out of scope for edits.
- Commit messages carry a `Co-Authored-By:` trailer. Ask before pushing.

## How this session worked, if that is useful

Four ports in two days, and the pattern that produced them: **write the tests
first, port, build, run the whole suite, then run the app** — the last step
because three of the four turned up something no test could reach. The two
defects that got furthest were both cases where every cheap check passed and only
the app or the *next* file's survey exposed them.

The rules earned along the way are collected at the end of
`ide/FIND_PORT_HANDOFF.md`. Two are about this codebase (`@objc dynamic`;
an ObjC ivar is not an implicitly-unwrapped Swift property) and two are about
method (measure, never subtract; a negative grep result is not a finding).
