# TextMate → Swift-native macOS: Project Phases & Progress

_High-level progress tracker. Last updated: 2026-07-28 — **OakTabBarView is fully
ported** (OakTabView + OakTabFrame + OakTabBarView in one change; both hand-written
interop headers and the 1234-line `.mm` deleted; the dead OakTabBarViewController
removed first as its own commit). The framework is Swift except `OakAnimatorProxy`.
386 tests across 29 bundles green (the port landed its own test bundle), Debug
and Release both build, and the tab bar was exercised in the running app. Earlier: 2026-07-27 (**Phase 3 complete** — Swift
interop foundation. **Phase 4 in progress**: CommitWindow (pilot) and Preferences are
ported and verified in the running app; BundleEditor is partially ported — its
`PropertiesViewController` and value transformer are Swift, its 1072-line window
controller deliberately is not, because its state is C++ (`be::entry_t` browser tree,
`plist::dictionary_t` + boost visitors) and it needs `+load` and a `bundles::callback_t`
subclass, neither of which Swift can express. Nib-contract tests now cover the xib
string contracts that used to fail silently, and caught two real bugs on their first
run. 339 tests green. Phase 2's one remaining
item is still signing/notarization (Stream 3), in progress on the side — no phase
depended on it)._

**End-state (decided): a Swift app + SwiftUI shell with TextMate's C++ core kept
behind Swift/C++ interop — NOT a full Swift rewrite of the engine.** The core is a
large, perf-tuned C++ text engine (buffer, editor, selection, layout, parse,
Onigmo regexp); a Swift rewrite is multi-year/high-risk for little user gain.
Modern Swift/C++ interop (5.9+) makes keeping it legitimate.

**Key constraint threaded through every phase:** Swift imports C++ (5.9+) and ObjC
cleanly but **cannot import ObjC++ (`.mm`) headers**. TextMate's UI is ObjC++, so
each migration step = "expose a clean ObjC-or-C++ interface at the boundary, then
move the caller to Swift."

**Granularity rule for this doc:** track *milestones*, not tasks. Task-level detail
lives in the per-stream handoff docs (currently [`ide/PHASE2_PROGRESS.md`](ide/PHASE2_PROGRESS.md));
duplicating it here goes stale within hours while the loop runs.

---

## Roadmap (6 phases + Phase 2.5 cleanup)

| # | Phase | Status | Effort / Risk |
|---|-------|--------|---------------|
| 1 | **Build bring-up** (rave → ninja compiling) | ✅ Done / pre-existing | — |
| 2 | **Xcode migration, keep ObjC++/C++** | 🔄 In progress (signing left) | Large / Med |
| 2.5 | **Cleanup & de-MacroMates** (dead code, cyclic deps, MacroMates-coupled services) | ✅ Done 2026-07-26 | Med / Low |
| 3 | **Swift interop foundation** (Clang modules, bridging, first `.swift`) | ✅ Done 2026-07-27 | Small–Med / Med |
| 4 | **Swift-ify the AppKit/UI shell, leaf-first** | 🔄 In progress — CommitWindow, Preferences, OakTabBarView done; BundleEditor partial (2026-07-28) | Very large / Med |
| 5 | **App shell & lifecycle in Swift** (= recommended end state) | ⬜ Not started | Med / Low–Med |
| 6 | **(Optional) core engine → Swift** | ⬜ Likely skip | Huge / High ⚠️ |

Numbered as **2.5**, not renumbered into the sequence, so it doesn't invalidate the
"Phase 2"/"Phase 3" language already used in commit messages and other docs
(`ide/PHASE2_PROGRESS.md`, `ide/NEXT_SESSION_HANDOFF.md`). It sits here because
several of its items — the license/CrashReporter/SoftwareUpdate MacroMates coupling
— are naturally decided alongside Stream 3's `CFBundleIdentifier` move (both are
"stop being MacroMates"), and because the dependency-cycle refactors should land
before Phase 3/4 touch the same lib graph for Swift modularization.

**Phase 3** — ✅ **Done 2026-07-27.** The Swift toolchain is proven end to end: the
first `.swift` file ([`Applications/TextMate/src/SwiftInterop.swift`](Applications/TextMate/src/SwiftInterop.swift))
calls a C++ core API (`text::pad`, via a Clang module) and an ObjC API
(`OakNotEmptyString`, via the bridging header), and is itself called from ObjC++
(`AppController.mm` through the generated `TextMate-Swift.h`) — the full
Swift↔ObjC↔C++ round trip, logged once at launch (`os_log` subsystem
`com.j23software.TextMate`, category `swift-interop`) with zero behavior change.
Verified in the running Release app; Debug and Release both build; 311 tests green.

Decisions that shaped it, recorded because Phase 4 will lean on all of them:

- **Toolchain baseline: Xcode 26.6 / Swift 6.3.3, `SWIFT_VERSION=6.0`**
  (strict-concurrency language mode from day one, rather than migrating later),
  `SWIFT_OBJC_INTEROP_MODE=objcxx`.
- **Global `CLANG_ENABLE_MODULES=NO` is untouched.** The "Swift needs modules"
  premise in the old plan was too coarse: Swift's importer runs its own Clang and
  only needs module maps for what Swift imports, so none of the 61 ObjC++/C++
  targets changed how they compile. Modules exist only in a generated Swift-facing
  farm (`ide/gen/swift/`, see `SWIFT_MODULES` in `ide/seed_xcodeproj.rb`): per-module
  shim headers that include the prelude first — the same "headers assume the PCH"
  contract every TU already relies on — then the farm headers they expose.
- **The bridging header is deliberately minimal** (Foundation + `<string>` +
  `<OakFoundation/OakFoundation.h>`), NOT the full prelude: `prelude.mm` drags
  WebKit/Quartz/AddressBook through the C++-interop importer on every Swift
  compile, and skipping it also sidesteps the `network`-farm/WebKit
  `<Network/Network.h>` collision entirely (no `network` farm dir is on the
  importer's `-Xcc` path).
- **C-variadic functions are invisible to Swift** — `text::format(char const*, …)`
  was the natural first call and cannot be imported; `text::pad` (non-variadic,
  `std::string` return crossing into Swift `String`) proves the same layer.
- Swift build settings are scoped to targets that have `.swift` sources (today:
  the app only) and the importer's `-Xcc` include paths are explicit
  (`swift_xcc_flags`) rather than trusting Xcode to forward `HEADER_SEARCH_PATHS`.

**Phase 4** — 🔄 **In progress.** Migrate ObjC++ UI frameworks Swift-ward starting
where engine contact is smallest, keeping `OakTextView` (the NSView text surface)
as ObjC++ — tightest engine coupling. **Precondition met 2026-07-26 (Stream 7):**
25 XCTest bundles, **311 tests** green under `xcodebuild test`. Phase 2.5 turned
the old interactive harnesses into 36 real tests, the first automated coverage
`layout` and `OakAppKit` ever had; the remaining Phase 4 frameworks are still
uncovered, so each port should land its own tests (the pilot added 14). Nib-backed
frameworks additionally get contract tests — see "nib-contract tests" below;
**386 tests across 29 bundles** as of 2026-07-29.

Measured migration surface: **~30k lines of ObjC++ across ~15 frameworks**
(37k total minus OakTextView's 6.9k, which stays). Done so far: CommitWindow
(1.1k ✅), Preferences (1.9k ✅), **OakTabBarView (1.6k ✅, 2026-07-28)**,
BundleEditor (1.3k ⚠️ partial). **`SoftwareUpdate`
(1.2k) is deliberately deferred** — the open Sparkle question may replace that
framework wholesale. (It is §7 of `NOTARIZATION_HANDOFF.md`, which is kept as a
local working note and deliberately not published — so that reference resolves
only in a working copy, not on the remote.)

**Ordering is now evidence-based, not line-count-based** — see the coupling
survey below. Re-run it with `python3 ide/coupling_survey.py` before picking the
next framework.

### Phase 4 pilot — CommitWindow (Done 2026-07-27)

CommitWindow is the SCM commit sheet: `CommitWindowTool` (a CLI shipped in the app
bundle, which bundle commit scripts invoke) hands the changed files and their
statuses to the running app over Distributed Objects; `OakCommitWindowServer`
presents the sheet; on commit the window serializes ` -m '<message>' <paths…>` back
over the port for the script to splice onto `git commit`.

~85% of it is now Swift (`CommitWindow.swift`, `CWItem.swift`,
`CWTableCellView.swift`, `CWStatusStringTransformer.swift`, plus a headless-testable
`CommitWindowLogic.swift`). **What stayed ObjC++ is the interesting part** — it is
the boundary shape every later port will hit, and it lives behind
[`CWSupport.h`](Frameworks/CommitWindow/src/CWSupport.h):

- **Distributed Objects is unavailable in Swift** — not merely deprecated, never
  exposed. The server and the client reply channel (`CWClientChannel`) stay ObjC++.
- **Two C++-typed `@objc` selectors cannot be implemented by a Swift class**:
  `variables` (returns `std::map`, called by OakTextView on its delegate) and
  `performBundleItem:` (takes `bundles::item_ptr`, dispatched to the key window's
  delegate by `AppController Commands.mm`). `CWInteropAdapter` conforms on the Swift
  controller's behalf and forwards. **This is the reusable pattern**: a small ObjC++
  adapter as delegate stand-in, not a rewrite of the caller.
- **Engine calls got ObjC-clean wrappers** (`path::escape`, `path::display_name`,
  `format_string::expand`, `io::exec`, `bundles::query`) — the roadmap's "expose a
  clean interface at the boundary" recipe, and the place to convert the `NULL_STR`
  sentinel to `nil` exactly once so it never reaches Swift.

Verified end to end, not just built: `CommitWindowTool` driven against the running
app produced the sheet; the table rendered all 3 files with correct status badges
and the `?`-status file correctly unchecked; **Commit** returned
` -m 'pilot commit message'  src/file1.txt src/file2.txt` to the tool (exit 0) and
**Cancel** returned empty output (exit 1). 325 tests green (311 + 14 new).

**Two pre-existing bugs this pilot uncovered**, both unrelated to Swift:

1. **`CommitWindowTool` was never copied into the app bundle** — so SCM commit was
   broken in *every* Xcode-built app from Stream 1 until now. `Frameworks/CommitWindow`
   (a lib) declares `files @CommitWindowTool "MacOS"`, but Pass 3 processed `@refs`
   only for the bundle target itself, on the stated assumption that "only the bundle
   declares them." It was the exact same class of gap as the Stream 1 resource
   correction, and is fixed the same way — closure-wide. It is also why the pilot
   could not be verified until it was fixed.
2. ~~**No main window ⇒ the commit command hangs forever.**~~ **Fixed 2026-07-29,
   and it was worse than this described.** The original note assumed the trigger
   was "no open window". It is not: `-[NSApplication mainWindow]` is nil whenever
   the app is merely **inactive**, which is the normal state when a commit is
   started from a terminal. So the hang did not need an edge case — with two
   documents open and TextMate simply not frontmost, the tool blocked forever.

   Reproduced before fixing, which is what corrected the diagnosis: with TextMate
   inactive the parent window reported **0 sheets** and `CommitWindowTool` never
   returned; the identical call with TextMate active reported **1 sheet** and
   worked. Confirmed afterwards straight from the app, once `/usr/bin/log` was
   being invoked correctly (see the logging note above) — inactive with one
   document open it reports `mainWindow=nil keyWindow=nil orderedWindows=1
   chosen=sheet`, and with every window closed `orderedWindows=0
   chosen=standalone`. Three layers of fix:

   - **Window selection** (`CommitWindowServer.mm`): after the `TM_PROJECT_UUID`
     match and `mainWindow`, fall back to `keyWindow`, then to the first visible
     window that `canBecomeMainWindow`.
   - **Presentation** (`CommitWindow.swift`): `beginSheetModalForWindow:` took a
     *non-optional* window and was handed nil from ObjC, so `beginSheet` was a
     silent no-op. Replaced by `-presentAttachedToWindow:`, which takes an
     optional and presents standalone when there is nothing to attach to. It also
     calls `NSApp.activate` — the user is being asked for a commit message while a
     CLI tool blocks on the answer, so a window that opens behind another app is
     the same user-visible symptom as the hang.
   - **A guarantee**: an `NSWindow.willCloseNotification` observer sends a failure
     reply if none was sent, so no future window-selection mistake can wedge a
     terminal again. `sendCommitMessageToClient` is idempotent, so the normal
     Commit/Cancel paths are unaffected.

   Dismissal had to change with it: every exit path called
   `sheetParent?.endSheet(…)`, which is a no-op for a standalone window and would
   have left it on screen after a commit. `dismiss()` now ends the sheet or closes
   the window as appropriate.

   Verified end to end in both presentations: inactive-with-windows produced a
   sheet on the frontmost window and returned
   ` -m 'fix verified from an inactive app'  a.txt`; with **every** window closed
   the standalone window appeared, returned ` -m 'standalone window commit'  a.txt`,
   and closed itself. Both exited cleanly instead of hanging.

Recipe notes for the next port:
- Framework Swift needs a per-framework **bridging header** (`<dir>/src/<Target>-Bridging-Header.h`);
  the seed picks it up by convention. Cross-framework Swift *imports* will need
  module maps (`SWIFT_MODULES`), which the pilot did not require.
- The importer's `-Xcc` path is now **all** farm dirs, not a curated list. That is
  safe only because nothing Swift parses may include `prelude.m`/`.mm` — bridging
  headers use `prelude.cc` + Cocoa — so the WebKit/`<Network/Network.h>` collision
  that forces per-target scoping for ObjC++ cannot arise here.
- A non-Swift target linking a Swift-containing static lib (`CommitWindowTool` →
  `libCommitWindow.a`) needs `-L$(SDKROOT)/usr/lib/swift`; clang, not swiftc, drives
  that link and won't find the runtime's `.tbd`s otherwise.
- **Swift 6 concurrency vs AppKit**, as predicted: `deinit` on a `@MainActor` class
  cannot touch its own state (teardown moved to an explicit call), and
  non-`Sendable` `NSEvent` in a local event monitor needs the isolated region to
  compute before the event passes through.
- `.swift` files listed in a framework's `tests` glob compile straight into the test
  bundle (no OAK-assert shim). Shared logic files listed there must stay free of
  ObjC metadata, or `-ObjC` force-loads the archive's copy and it collides.

### Phase 4 — Preferences (Done 2026-07-27)

The 6-pane preferences window (Files, Projects, Bundles, Variables, Software
Update, Terminal) plus its `PreferencesPane` base and window/toolbar controller.
**~1.9k lines, all of it now Swift** except `Keys.h/.mm` (a constants header 8
other frameworks import — porting it would force every consumer to take a
generated Swift header for no gain) and the boundary in
[`PWSupport.h`](Frameworks/Preferences/src/PWSupport.h): `settings_t` wrappers,
`bundles::query`, `format_string::expand`, the `NSGridView` helper (it took
`std::vector<NSUInteger>`), and the whole `mate` install path
(`AuthorizationRef` + C varargs + recursive POSIX file ops — not expressible in
Swift at all).

**Three new reusable techniques, none of which the pilot needed:**

1. **A framework's public ObjC header can stay hand-written while its
   implementation moves to Swift.** `Preferences.h` still declares
   `@interface Preferences : NSWindowController`; the Swift class is
   `@objc(Preferences)`. `AppController.mm` was not touched at all. This is how
   a framework gets ported without editing its consumers, and it avoids exporting
   build-directory `*-Swift.h` through the include farm. The rule that makes it
   work: ObjC++ *inside* the framework must not import that header, or it
   collides with the generated one.
2. **KVC routing survives the port unchanged.** Panes bind to key paths that are
   not properties, and `value(forUndefinedKey:)` / `setValue(_:forUndefinedKey:)`
   redirect them to `NSUserDefaults` or the C++ `settings` layer. This works in
   Swift for the same reason it worked in ObjC — `NSViewController` is an ObjC
   class and the ObjC KVC machinery does the dispatch. Verified by toggling a
   checkbox and watching the default flip `0`↔`1`.
3. **A nib-backed controller ports fine, but its xib is a set of string
   contracts.** `TerminalPreferences.xib` names File's Owner `TerminalPreferences`
   (hence `@objc(TerminalPreferences)`), five outlets by name, and — the trap —
   binds `installIndicaitorImage`, whose original misspelling **must be
   preserved** or the binding silently breaks.

Two upstream annotations were added rather than worked around locally, because
every later port hits the same thing:

- **`NS_SWIFT_NAME(TMBundle)` on BundlesManager's `Bundle`.** Swift maps NSBundle
  to `Bundle`, so a tmbundle-index `Bundle` is ambiguous the moment a file
  imports Foundation. ObjC name and all existing ObjC call sites unchanged.
- The `Oak*` UI constructors are unannotated C++, so Swift imports them as
  implicitly-unwrapped optionals — **and an IUO decays to a plain `Optional`
  wherever the type is inferred.** Every call site needs an explicit type
  (`let b: NSButton = OakCreateCheckBox(…)`). A blanket `NS_ASSUME_NONNULL` on
  that header would be wrong (`OakCreateLabel`'s `font` is legitimately nil).

**One real bug was introduced by the port and caught by launching it** — worth
recording as the shape of mistake to watch for. `BundlesPreferences.selectedIndex`
did `Int(selectedIndex) < labels.count`; with `allowsEmptySelection` the scope bar
reports "no selection" as `NSUInteger`'s max, which is not representable as `Int`,
so Swift's *checked* conversion trapped and the app died on opening the Bundles
pane. The ObjC++ original compared unsigned-to-unsigned and was fine. **Swift
turns silently-wrapping ObjC integer conversions into hard crashes**: keep bounds
checks in the unsigned domain and convert only after they pass.

Verified in the running app, not just built: all 6 toolbar panes switch without
crashing; the Terminal nib loads with outlets connected (its `${…}` status
templates expand — "Shell support not installed", `/usr/local/bin/mate`
interpolated into the summary — and the status image resolves through the
misspelled binding); Bundles lists 255 bundles across 6 category buttons;
Variables renders its 3-column table; and a checkbox toggle writes through to
`NSUserDefaults`. 325 tests green.

**Phase 5** — AppDelegate, NSDocument architecture, MenuBuilder, entry point;
optionally SwiftUI for auxiliary surfaces (prefs/dialogs/about). Main editing
surface stays AppKit.

**Phase 6** — huge/high-risk/low-benefit; realistically leave as C++ permanently.
Only if "zero C++" becomes a hard requirement.

---

## Phase 2 detail — Xcode migration (6 work streams, ~7–11 wk)

"Migrate build system to Xcode, modernize APIs, keep ObjC++/C++." Build graph = 61
targets with declarative `.rave` specs.

| Stream | Scope | Status | Depends on |
|--------|-------|--------|------------|
| 1 | **Xcode workspace scaffold** (48 frameworks + 11 apps) — critical path | ✅ Done 2026-07-26 (launch-verified; see bundle-resource correction below) | — |
| 2 | Dependency integration (capnp/boost/Onigmo/kvdb) — make deps reproducible, not `~/nix-sdk` user-local paths | ✅ Done 2026-07-26 (Homebrew default validated on CI; optional dep-version pinning TBD) | 1 |
| 3 | Code signing & notarization (real identity; ad-hoc already proven) | ⬜ Not started (needs certs → user) | 1 |
| 4 | Raise deployment target (macOS 15) + remove dead guards | ✅ Done 2026-07-24 (unmerged) | — |
| 5 | API modernization (WebView→WKWebView, KVO) | ✅ Done 2026-07-26 — all 5 slices; no legacy WebKit API left in the tree. See [`ide/STREAM5_HOJSBRIDGE_PLAN.md`](ide/STREAM5_HOJSBRIDGE_PLAN.md) | 1 |
| 6 | CI/CD (xcodebuild) | ✅ Done 2026-07-26 (`xcode` job green on macos-latest) | 1, 2 |
| 7 | Test suites → XCTest bundles | ✅ Done 2026-07-26 (25 bundles, 275 tests green) | 1 |
| 8 | Default-bundles provisioning | ✅ Done 2026-07-26 (run-script phase) | 1 |

### Phase 2 definition of done (cutover criteria)
Phase 2 is done when the Xcode build is at **feature parity** and rave/ninja can be
deleted:
- [x] `TextMate.app` builds, launches, opens/edits/saves documents — verified
      2026-07-26 on disk, not by eye: an edit + ⌘S changed the file's SHA, and a
      new document saved through the custom `OakSavePanel` (encoding/line-ending
      accessory rendering) landed with the exact typed content.
- [x] Bundles + plugins load (Dialog, Dialog2), QuickLook generator works —
      verified 2026-07-26: 35 bundles installed, the Bundles menu fully populated,
      and a real command ran end-to-end (Text → Statistics for Selection returned
      the correct counts); both `.tmplugin`s confirmed loaded into the live process
      via `vmmap`, not just present on disk. **QuickLook caveat:** the generator is
      correctly built and functional — factory exported, `dlopen` clean, and
      `CFPlugInInstanceCreate` succeeds from a plain host — but Apple's QL host
      processes are library-validated and refuse ad-hoc-signed plugins (reproduced
      exactly: the same probe fails when signed with library validation). Loading
      inside Finder/qlmanage is therefore **gated on Stream 3's real signing
      identity**, not on any build gap.
- [x] All 11 CLI tools work (`mate`, `tm_query`, …) — verified 2026-07-26: all 11
      build in Release, all gave correct functional output, and every executable
      the app actually ships (`mate`, `tm_query`, `PrivilegedTool`, `tm_dialog`,
      `tm_dialog2`) runs **in place** in the bundle — the embed-dylibs phase's
      vendored capnp/kj + nested `disable-library-validation` entitlement work as
      designed. Known local-dev quirk, not a shipping defect: the *standalone*
      copies in `build/Release/` reference Homebrew's ad-hoc-signed dylibs directly
      and carry no entitlement, so under Release's hardened runtime they fail at
      `dyld` load (Debug copies work; bundled copies work). Static-linking capnp or
      signing tools with the nested entitlement would fix it if it ever matters.
- [x] Default-bundles provisioning has an Xcode-world answer (Stream 8)
- [x] Test suites migrated and green (Stream 7 — 25 bundles, 275 tests)
- [x] CI builds + tests on a clean machine (run 30199308492: `xcode` job seeds,
      builds, and runs the AllTests suite green on macos-latest; the bundle
      script phase reached `api.textmate.org` from the runner too)
- [ ] Signed + notarized artifact
- [x] rave/ninja retired (2026-07-26, tag `rave-final`): `bin/rave`, `bin/gen_build`,
      `bin/gen_test`, `bin/notarize_await`, `bin/expand_variables`,
      `bin/extract_changes`, `bin/update_changes`, `configure`, `.travis.yml`, and
      `local-orig.rave` deleted; the ninja CI job removed; `.gitignore`,
      `.tm_properties` and `README.md` updated. **The `.rave` spec files
      (`{Applications,Frameworks,PlugIns}/*/default.rave`, `default.rave`) are
      kept** — they remain `ide/extract_specs.rb`'s live input for regenerating
      `TextMate.xcodeproj`; deleting them is Stage B (below), a separate,
      deliberate step. `bin/gen_html` is kept too — still load-bearing for the
      Xcode build (the About pages). `bin/CxxTest` was also kept at the time; it
      has since been deleted in Phase 2.5.

**rave retirement policy (decided 2026-07-25; executed 2026-07-26):** the two
things that kept rave alive were the test suites and the `DownloadBundles`
provisioning step. Both got Xcode-world answers (Streams 7 and 8), and rave turned
out never to have built the tests at all — so it was no longer the only home of
anything. Tag `rave-final` marks the last commit where `./configure && ninja
TextMate` was verified green and launchable; the build tooling was deleted
immediately after. Remaining cutover criteria above (signing, notarization,
clean-machine CI) never depended on rave.

**Stage B, not yet done:** the `.rave` spec files are still the Xcode project's
source of truth (`ide/extract_specs.rb` parses them on every regeneration;
`TextMate.xcodeproj` itself stays gitignored/regenerated). Deleting the specs
means graduating to a committed, hand-maintained `.xcodeproj` first — a real
one-way door, and a separate decision from anything above.

### Stream 7 — Test suites → XCTest (Done 2026-07-26)

**The premise in the old plan was wrong — these suites had no build rule at all.**
`bin/rave` parses the `tests`/`cxx_tests` keywords and globs the files, but nothing
downstream turns them into a ninja rule: a generated `build.ninja` has no `/test`
target and never invokes `bin/gen_test` or CxxTest.

They were not always dead. The *original* generator, `bin/gen_build`, built and ran
them: `af91d39b` (2019-07-16, "Generate build rules for tests but do not depend on
the tests passing") added `gen_test`/`cxxtestgen` rules plus `run_test` rules that
executed the binaries. `bin/rave` arrived as a from-scratch replacement in
`e921af4e` (2021-01-25) carrying the two DSL keywords into its parser but never
implementing the rules, and `70d26715` (2021-02-15) gutted `bin/gen_build` from 967
lines to a `./configure` shim — deleting the only code that built the tests.
**So the suites have been unbuildable since February 2021**, and the last build
system to run them tolerated failures by design, which is how 13 of them rotted.

A leftover that corroborates this: the repo-root `.tm_properties` still maps ⌘B in
a test file to the ninja targets `<fw>/test` and `<fw>/cxx_test`, which have not
existed for over five years.

Also a naming correction: only **3** frameworks (`OakAppKit`, `ns`, `layout`) use
CxxTest, via `cxx_tests`. The other 22 are plain `void test_x ()` functions using
`OAK_ASSERT*`, written for the unused runner in `bin/gen_test`.

- `ide/extract_specs.rb` captured `cxx_tests` (it had silently dropped them). That
  handling has since been removed again — see Phase 2.5, where the suites became
  ordinary `tests` and CxxTest went away.
- `ide/gen_xctest.rb` (new) wraps the OAK-style tests in `XCTestCase` subclasses,
  reusing the assertion macros verbatim from `ide/xctest_preamble.h` (ported from
  `bin/gen_test`, which goes away with rave). Test bodies are unchanged; only
  failure reporting differs — a thrown `oak_exception` becomes an `XCTFail`.
- `ide/seed_xcodeproj.rb` Pass 4 emits **25 `.xctest` bundles**, one per framework,
  plus a shared `AllTests` scheme. `xcodebuild test` ran **275 tests green** (311
  after Phase 2.5).
- The `cxx_tests` GUI suites were compiled (so they stopped rotting) but never ran:
  they subclass `CxxTest::TestSuite`, not `XCTestCase`, so XCTest could not invoke
  them — and they gate on a `GUI_TESTS` env var and then block in `[NSApp run]`
  awaiting manual interaction, so running them would have hung CI. **They were
  interactive harnesses, not a regression net.** Rewritten in Phase 2.5.
- **13 tests are skipped by name** in the generated scheme, each with its reason
  recorded in `SKIPPED_TESTS` (`ide/seed_xcodeproj.rb`). All are long-dormant
  failures, not regressions — but leaving them red would make the CI signal
  worthless. Categories: missing tools (`hg`, `svn`), git no longer defaulting to
  `master`, host spellchecker dependence, two needing installed grammars, four
  genuine behaviour mismatches, and one real **memory-safety bug** —
  `cf/tests/t_rect.cc`'s `from_str(".........")` underflows `size_t` into a huge
  `CGRect` and writes out of bounds (it crashes the process, taking the whole
  bundle with it). Fixing these is tracked separately.

### Stream 8 — Default-bundles provisioning (Done 2026-07-26)

The Xcode build shipped the raw `DefaultBundles.tbz.bl` (a 20-byte list reading
`mandatories defaults`) as a resource. `AppController.mm` looks for
`DefaultBundles.tbz`, so `pathForResource:` found nothing and first-run bundle
provisioning silently did nothing — with no fallback path.

The seed now adds the project's first `PBXShellScriptBuildPhase` to the app target,
mirroring rave's `CreateBundlesArchive`: run `bl -C <stage> install $(cat …)`, then
`tar` the staged tree into `$(DERIVED_FILE_DIR)/DefaultBundles.tbz` and copy that
into `Contents/Resources`; the `.tbz.bl` is filtered out of the resource copy.
Failure is tolerated (rave does the same), so an unreachable `bl` server yields an
app with no default bundles rather than a failed build.
`ENABLE_USER_SCRIPT_SANDBOXING=NO` is pinned explicitly — a sandboxed script phase
cannot reach the network.

**The `bl` server is reachable again** (the previous "unreachable" note is stale):
verified end to end, producing a 4.9 MB archive of 32 bundles that extracts cleanly
through the same `tar` flags `network::tbz_t` uses.

Making the app depend on `bl` also exposed that **`bl` had never compiled** in the
Xcode project — nothing depended on it before. Its `network` farm include dir was
withheld by a collision guard meant only for WebKit-pulling targets; `bl` is pure
C++ and reaches `<network/key_chain.h>` transitively through `updater.h`. The guard
in `farm_dir` is now scoped to targets that actually pull WebKit.

### rave parity audit (2026-07-26)

Before deleting rave, every build rule it owns was walked and matched against the
Xcode seed. `bin/rave` has 9 `Compiler` transforms plus the target-level steps;
status of each:

| rave rule | Xcode equivalent | Status |
|---|---|---|
| `CompileClang` (.c/.m/.cc/.mm → .o) | native | ✅ |
| `CompileRagel` (.rl → .cc) | `PBXBuildRule` in the seed | ✅ |
| `CompileCapnp` (.capnp → .c++) | `PBXBuildRule` in the seed | ✅ |
| `CompileXib` (.xib → .nib) | variant groups → ibtool | ✅ (Stream 1) |
| `ExpandVariables` (Info.plist) | `INFOPLIST_FILE` + build settings | ✅ (Stream 1) |
| `CreateBundlesArchive` (.tbz.bl → .tbz) | script phase | ✅ (Stream 8) |
| `ConvertToUTF16` (.strings) | Xcode converts natively… | ⚠️ **gap, fixed** |
| `CompileMarkdown` (.md → .html) | none | ⚠️ **gap, fixed** |
| `CompileAssetCatalog` (.xcassets → .car) | — | n/a, no `.xcassets` in tree |

Two real gaps, both invisible to a green build and both now closed:

1. **About pages were never generated.** rave compiled `about/*.md` → HTML via
   `bin/gen_html` (multimarkdown + the app's header/footer ERB templates); the seed
   copied the raw `.md`. `AboutWindowController.mm` loads `About/<Page>.html`, so
   5 of the 6 About tabs rendered blank — only `Bundles.html`, already HTML in the
   tree, worked. Now a script phase (`add_about_pages_phase`), with the `.md`
   inputs filtered out of the resource copy. **Verified by clicking all six tabs.**
2. **`${YEAR}` was never expanded.** rave ran `ExpandVariables` over
   `InfoPlist.strings` with `-dYEAR=`; Xcode converts `.strings` to UTF-16 but
   expands nothing, so the shipped copyright read `2004-${YEAR}` literally. Now
   pre-substituted at seed time (`expand_year_strings`), mirroring how the
   entitlements template is handled.

Target-level steps (`objects`/`executable`/`lipo`/`assets`/`signature`/`runner`/
`notarize`/`defines`/`expand`) map to native Xcode behaviour, except:
- `lipo` — only matters for universal builds; see the arch decision above.
- `notarize` — rave drives the **retired** `altool`. Stream 3 must be built on
  `notarytool` regardless, so there is nothing here to port.
- `runner`/`defines` — `ninja TextMate/run` and the `install`/`bump`/`deploy`
  actions in `local.rave` are developer conveniences, replaced by Xcode's Run
  action. Worth re-creating only if missed.

**Conclusion: no functional gap remains between the two build systems.** rave is
ready to delete once Stream 3 no longer wants it as a reference.

### Stream 4 — Done (branch `claude/upbeat-galileo-eae114`, **not merged**)
- Deployment floor raised to **macOS 15.0 Sequoia** via `default.rave` `APP_MIN_OS`.
- All dead version guards removed (−213 lines), verified by full build.
- Follow-ups: **merge the branch**; 2 `@available` sites in the `PlugIns/dialog`
  submodule left untouched (submodule-pointer scope).

### Stream 1 — Done (branch `claude/xcode-stream1-seed`)

> **Correction (2026-07-26).** This section previously recorded a "launchable"
> app. It was not: the first actual launch attempt died with `Unable to load nib
> file: MainMenu, exiting`. `codesign --verify --deep --strict` passing had been
> mistaken for launchability — the signature was valid, the bundle was just
> missing its contents. Two seed gaps, both now fixed:
>
> 1. **No xib compilation.** `bin/rave` has a `CompileXib` rule (`.xib` → `.nib`
>    via `xcrun ibtool`); the seed had no equivalent and copied raw `.xib` files
>    into the bundle, so `NSApplicationMain` could not find `MainMenu.nib`.
> 2. **No require-closure resources.** rave copies the assets of *every* target
>    in a bundle's require closure into the wrapper (`bin/rave`, `signature` →
>    `required_targets(…, include_self: true)`). The seed only handled the app's
>    own `files`/`copy` entries, so every framework-owned resource was absent —
>    BundleEditor's 7 property xibs, OakTextView's `TabSizeSetting.xib`,
>    Preferences' nibs. Bundle Editor and Preferences would have failed to open
>    even once the main nib loaded.
>
> Both live in Pass 3 of `ide/seed_xcodeproj.rb`. Localized resources go through
> **PBXVariantGroups** in the Resources phase rather than Copy Files phases:
> that is what invokes Xcode's built-in ibtool rule, and it avoids Xcode
> re-appending the `.lproj` on top of an explicit `dst_path` (which nests them as
> `Resources/English.lproj/English.lproj/`). App bundle went from ~66 to 204
> files + 14 localized resources.
>
> **Verified 2026-07-26:** clean `rm -rf build` → seed → `xcodebuild` →
> `** BUILD SUCCEEDED **`; 0 raw xibs and 0 nested `.lproj` in the wrapper;
> `codesign --verify --deep --strict` passes; the app launches, stays alive as a
> foreground GUI process, and `mate --name smoke <file>` opens a document into it
> with no errors in the unified log. (That last clause is unsupported for the same
> reason as the Phase 4 correction below — `log show` captures nothing for this
> app. The launch and the `mate` round trip are the real evidence here.)

Generator decision (**confirmed by user**): **hand-authored `.xcodeproj`**, seeded
programmatically via the `xcodeproj` Ruby gem (`ide/extract_specs.rb` +
`ide/seed_xcodeproj.rb`), then maintained natively. No Swift; ObjC++/C++ kept.

Milestones:
- [x] Mechanisms proven: include farm, mixed-language PCH, Ragel/Cap'n Proto build rules
- [x] All 50 static libs build (`AllLibs`, commit `9dd5daed`)
- [x] All 11 CLI tools + 3 loadable bundles link (commit `88126b8d`)
- [x] WebKit↔`network` SDK header collision resolved — option 4, no-umbrella farm
      variant (commit `4780a653`)
- [x] **`TextMate.app` compiles + links** (ad-hoc signed, Info.plist generated;
      commit `4780a653`)
- [x] App bundle layout: resources / plugins / tools copy phases, xib compilation,
      and require-closure resource propagation (Pass 3 in the seed)
- [x] **Launch-verify** `build/Release/TextMate.app` — done 2026-07-26. Needed two
      seed fixes first (xib compilation + require-closure resources); the earlier
      "launchable" claim was never true. See the correction note below.
- [ ] Update `ide/PHASE2_PROGRESS.md` (its "BLOCKED" section is stale — the
      blocker was resolved in `4780a653`)

**Authoritative Stream-1 handoff:** [`ide/PHASE2_PROGRESS.md`](ide/PHASE2_PROGRESS.md).

---

## Phase 2.5 detail — Cleanup & de-MacroMates

✅ **Done 2026-07-26.** Each item needed its own remove-or-replace decision, so this
phase was a set of independent, low-risk cleanups rather than a single change. None
of it blocked Phase 3 — it's here because it *should* happen before Phase 3/4 touch
the same lib graph and bundle identity again.

**Dead code:**
- ~~`Applications/NewApplication`~~ **Deleted 2026-07-26** — the unused
  Xcode-template scaffold app; `SKIP_TARGETS` in the seed (its only reason to
  exist) went with it.
- ~~`bin/show_log`~~ **Deleted 2026-07-26** — confirmed zero references anywhere.
- ~~`bin/gen_credits.rb`~~ **correction (2026-07-26): not dead, kept.** The
  original rave parity audit only grepped source/build files and missed that
  `bin/gen_html` pipes a Markdown page's *rendered HTML* back through
  `ERB.new(...).result(binding)` (`bin/gen_html`'s last line) — so the
  `<% require 'bin/gen_credits'; ... %>` block embedded in
  `Applications/TextMate/about/Contributions.md` genuinely executes at every
  build, shelling out to `git log` to render the live commit list the About
  window's Contributions tab shows. (Minor, unrelated aside for whenever the
  MacroMates-coupled-services item below is tackled: `generate_credits` caches
  GitHub username lookups to `~/Library/Caches/com.macromates.TextMate/githubcredits`
  and queries `api.github.com/legacy/...`, a long-deprecated endpoint — likely
  degrading silently to no GitHub links today, not a build break.)
- ~~**`bin/CxxTest`**~~ **Deleted 2026-07-26**, along with its `.gitmodules` entry —
  a 3.8 MB vendored submodule that existed for 4 files. See "GUI harnesses → real
  tests" below for the rewrite that unblocked it. Also removed with it:
  `Shared/include/test/cocoa.h` (the `GUI_TESTS`/`[NSApp run]` helper, now referenced
  by nothing), the `cxx_tests` keyword from `ide/extract_specs.rb` and all three
  `default.rave` files, and Pass 4's CxxTest scaffolding in `ide/seed_xcodeproj.rb`
  (the per-file `<cxxtest/TestSuite.h>` wrappers, the `Root.cpp` shim needed to make
  them link, and the `bin/CxxTest` header-farm entry). The extractor now deliberately
  ignores `cxx_tests` rather than handling it, so a reappearance is noticed.
- ~~**Dependency-cycle refactors.**~~ **Done 2026-07-26.** Recomputed the actual
  graph (Tarjan's SCC over `ide/gen/specs.json`'s real `require`/`require_headers`
  edges) rather than trust the old note — found 3 cyclic SCCs of sizes 3, 3, and
  9 (the 9-node one, 17 internal edges, initially looked far worse than "~4
  refactors" suggested; it wasn't — decomposed into exactly 2 necessary cuts).
  Every one of the 4 cuts was a single file coupled to another framework for one
  narrow, mechanical reason:
  - `io → ns`: `intermediate.mm`'s two `NSString`/`std::string` conversions,
    inlined using deps `io` already had (`OakFoundation`, `cf`).
  - `command → OakAppKit`: `runner.mm`'s one `addButtons:` convenience call,
    replaced with two direct `addButtonWithTitle:` calls.
  - `document → FileBrowser`: `KEventManager`/`FileItemImage` relocated to
    `TMFileReference` (a framework both sides already required) — a pure file
    move, no new framework.
  - `OakCommand → BundleEditor`: inverted via `NSNotificationCenter`
    (`OakRevealBundleItemNotification`), matching a convention already in the
    same file. Caught one real timing bug before it shipped: `BundleEditor` is
    only ever instantiated lazily, so registering the observer in `-init` would
    have silently dropped the very first crash-recovery reveal in any session
    that hadn't yet opened the Bundle Editor. Fixed by registering in `+load`
    instead, which runs unconditionally at process start — matching what the
    original direct call actually guaranteed.

  Verified: the resulting graph has **0 cyclic SCCs** (confirmed both by
  simulation before editing and by recomputing from the real spec file after).
  Landed as 4 independent, individually-verified steps — full build green and
  all 275 tests green after each one, not just at the end.

**GUI harnesses → real tests (2026-07-26).** The 4 `gui_*.mm` files were rewritten as
ordinary OAK-style test files, taking the tree from **275 to 311 tests**. They are
*not* hand-written `XCTestCase` subclasses: making them plain `void test_x ()`
functions means the existing `ide/gen_xctest.rb` wraps them like the other 22
frameworks' tests, so no new seed machinery was needed and all the CxxTest handling
could simply be deleted. Only `layout`'s and `OakAppKit`'s `tests` globs had to widen
(`t_*.cc` → `t_*.{cc,mm}`; `OakAppKit` had no `tests` line at all).

| was | now | tests |
|---|---|---|
| `layout/tests/gui_layout.mm` | `t_layout.mm` | 15 |
| `ns/tests/gui_key_events.mm` | `t_key_events.mm` | 7 |
| `OakAppKit/tests/gui_pop_out.mm` | `t_pop_out.mm` | 5 |
| `OakAppKit/tests/gui_dictionary.mm` | `t_key_equivalent_view.mm` | 9 |

- **`t_layout.mm`** — the big one, and all of it headless: `ng::layout_t` owns its
  metrics and only wants a `CGContext` when actually asked to draw. Covers
  hit-testing ↔ `rect_at_index` round-trips, soft wrap and explicit wrap columns,
  folding (including the persisted `folded_as_string()` round trip), layout-aware
  caret movement, gutter line records, selection rects, `draw` into a
  `CGBitmapContext` asserting pixels actually landed, and multi-byte text never being
  split mid-character. The old harness' *one* real assertion —
  `structural_integrity()` in a refresh cycle's destructor, under randomized inserts
  — is kept as `test_randomized_inserts`, but with a **fixed seed**: the original used
  `arc4random` and so could not replay a failure.
- **`t_key_events.mm`** — covers `to_s(NSEvent*)`, which every key binding in the app
  goes through and which nothing tested. Events are synthesized with
  `CGEventCreateKeyboardEvent` (what `to_s` reads back internally anyway), so no
  window or run loop is needed. Because `to_s` resolves key codes through the *active
  keyboard layout*, the layout-dependent expectations are gated on a US-ANSI probe
  rather than assumed — this repo has already been bitten once by a locale bug.
- **`t_pop_out.mm`** — the pop-out's child-window bookkeeping *and* its timing: the
  animation genuinely runs headlessly, so the tests drive the run loop and assert the
  window closes itself (with a timeout, so a regression fails instead of hanging).
- **`gui_dictionary.mm` was dropped, not ported.** It tested no TextMate code — an
  `NSTextInput`-conforming view built inside the test file, existing so a human could
  press ⌃⌘D and watch the *system* dictionary service. `OakKeyEquivalentView` is
  covered instead: real OakAppKit logic (event string ↔ glyph display, recording
  state, clear keys), read back through the accessibility value, which is both the
  same string the view draws and a shipped interface.

Two things this turned up worth recording:
- `folded_as_string()` returns `NULL_STR`, not `""`, when nothing is folded, and
  `is_line_fold_start_marker()` reports the *grammar's* `foldingStartMarker` pattern —
  it is not a consequence of a manual `fold()` and needs installed bundles. Both were
  wrong guesses in the first draft of the tests, caught by running them.
- `layout->width()`/`height()` return `max(content, viewport)`, so a test with a
  viewport larger than its content measures the viewport and cannot see content
  changes at all. The tests pin a deliberately tiny viewport for this reason.

**Launch-verified**, not just green: `⌘G` in a real document flashes the yellow
pop-out over the match, replaces the previous flash rather than stacking, and the
window closes itself ~0.7s later — the three behaviours `t_pop_out.mm` asserts,
confirmed in the running app. The Bundle Editor's Key Equivalent field was exercised
too; that surfaced one *pre-existing* bug unrelated to this work (a clear button
offered on a field with no key equivalent — `OakKeyEquivalentView`'s `showClearButton`
requires a non-empty `eventString`, so the bound value is arriving non-nil, likely an
`NSObjectController` marker or the `NULL_STR` sentinel crossing into ObjC). Left as a
follow-up rather than fixed here.

**Debug config fixed 2026-07-26 — and a trap worth not re-entering.** The Debug app
and CLI tools failed at link on the `oak/debug` assert symbols; Pass 2 now links
`libOakDebug.a`, but **in Debug only**, and that scoping is the whole point rather
than tidiness:

`OakAssert.mm` has a `+load` that installs an `NSExceptionHandler` whose delegate
calls **`abort()` on every exception** (bar `FSExecutionErrorException`). `+load`
does not consult `NDEBUG`. The seed's existing Pass 4 comment reasons that linking
OakDebug in both configs is "harmless — in Release nothing references it", and the
first attempt at this fix copied that reasoning into Pass 2. **It is wrong for an
ObjC archive under `-ObjC`**, which the seed passes precisely so ld pulls in members
nothing references. Linking it unconditionally would have shipped a Release app that
aborts on any ObjC exception. Because a frameworks-phase entry and a target
dependency are per-target and cannot be scoped to a configuration, OakDebug goes in
as a raw linker input in the Debug `OTHER_LDFLAGS` instead. Verified at the binary
level, not from build settings: `nm` finds `OakExceptionHandlerDelegate` in the Debug
executable and **not** in the Release one.

Turning Debug on then exposed a real, pre-existing crash — precisely what an
abort-on-exception handler is for. `OakAccessibleLink` (`OakTextView.mm`) threw
`NSAccessibilityException` for any attribute outside its advertised list, but AppKit's
legacy accessibility path probes beyond that list, so **the Debug app aborted on
opening any document containing a `markup.underline.link` scope** — any Markdown file
with a URL in it. Two rounds were needed: replacing the throw with
`[super accessibilityAttributeValue:]` only traded the exception for
`doesNotRecognizeSelector`, because on a current SDK **`NSObject` implements none of
the legacy accessibility methods** (measured: only `accessibilityAttributeValue:
forParameter:` survives; `NSView` still has them, which is why the same
defer-to-super idiom is safe in `OakKeyEquivalentView` and not here). The class is now
self-contained: `nil` for unsupported attributes, `NO` for settable, no-op for set.
The two `[super …]` calls it already had were the same latent crash and went too.
Verified by opening the file that reproduced it and walking the AX tree with System
Events — which now returns real roles (`AXGroup, AXTabGroup, AXButton…`) instead of
aborting, in both Debug and Release.

**MacroMates-coupled services — decided and landed 2026-07-26:**
- ~~**`license`**~~ **Removed.** `Frameworks/license` deleted whole (serial-number
  purchase/registration flow, `visitOnlineStore:` hardcoded to
  `shop.macromates.com`, `revoked_serials()` validation). Confirmed before
  deleting that nothing else in the app gates on license validity — it only ever
  drove the About window's Registration tab (now removed, 5 tabs instead of 6)
  and the "Add license" link. Also removed the now-orphaned
  `kUserDefaultsLicenseOwnerKey` default and the dead `addLicense`/
  `addLicenseCallback` bridge code in `WKWebView.js` that only that tab used.
  Verified: About window opens with no crash, exactly 5 tabs.
- ~~**`CrashReporter`**~~ **Upload disabled.** `AppController.mm` no longer calls
  `postNewCrashReportsToURLString:` (that URL resolved to MacroMates'
  `api.textmate.org/crashes`). The framework and its Preferences → Software
  Update checkbox stay, ready to re-enable once a J23-owned collector exists —
  relabeled from the now-inaccurate "Submit to MacroMates" to "Submit crash
  reports" so it doesn't claim to do something it can't. macOS's own system
  crash reporting is unaffected.
- ~~**`SoftwareUpdate`**~~ **Channels unconfigured.** `AppController.mm` no
  longer sets `SoftwareUpdate.sharedInstance.channels` to the
  `api.textmate.org/releases/...` URLs. Verified: Preferences → Software Update →
  "Check Now" now surfaces a clear *"No channel named 'release'."* error instead
  of silently checking MacroMates' TextMate 2 release feed — confirmed this is
  `SoftwareUpdate.mm`'s existing graceful-failure path (`checkForTestBuild:`),
  not a crash or a new code path. Re-wire once a J23-owned update feed exists.

All three were naturally decided alongside Stream 3's eventual move off
`com.macromates.*` (same underlying question — "what is this fork's own identity,
distinct from MacroMates' infrastructure") but didn't need to wait for it: none of
the three required a J23 identity to already exist, only to stop pointing at
MacroMates' in the meantime.

---

## Tracked but not yet scheduled

- **`SyntaxMate` is mispackaged and orphaned** (found 2026-07-26 during cutover
  verification). Its spec says `prefix "${target}.xpc/Contents"` — it is an **XPC
  service**, not a CLI tool — but the seed's `kind()` doesn't recognize `.xpc`, so
  it falls through to `:tool` and builds as a bare executable that nothing wraps.
  Nothing in the tree references it (no `NSXPCConnection`, no spec `require`, not
  copied into the app), so nothing is broken today; it was upstream's syntax-
  highlighting extension host. Decide: package it properly as `.xpc` in the seed,
  or delete it like the other orphans.
- **Standalone Release tools vs hardened runtime** — see the CLI-tools cutover
  criterion above. The copies in `build/Release/` can't load Homebrew's dylibs
  under library validation; the shipped, bundled copies are fine. Fix only if
  standalone use of the build products ever matters (static-link capnp/kj, or
  sign tools with the nested entitlement).
- ~~**Test-suite migration.**~~ **Done 2026-07-26** — see Stream 7 below.
- ~~**Default-bundles provisioning.**~~ **Done 2026-07-26** — see Stream 8 below.
- ~~**Branch integration order.**~~ **Stale, struck 2026-07-26.** This said Stream 4
  (`claude/upbeat-galileo-eae114`) and Stream 1 (`claude/xcode-stream1-seed`) were
  unmerged and needed ordering. Neither branch exists locally or on
  `GH-johnmcgovern` any more, `default.rave` already carries `APP_MIN_OS "15.0"`,
  and there are no `@available` guards left outside the `PlugIns/dialog` submodule.
  Both streams' content is on master; there is nothing to merge.
- ~~**Debug configuration.**~~ **Done 2026-07-26** — and the original note
  mischaracterized it. Debug was never wholly missing: the *test bundles* built and
  ran in Debug all along (that is how the 311 tests run). Only the **app and tools**
  failed, at link, on the `oak/debug` assert symbols (`OakBadAssertion`,
  `OakPrintBadAssertion`, `oak::to_s`) that Release compiles out via `NDEBUG`.
  `default.rave`'s root-level `config debug { require OakDebug }` is what supplies
  them, and that block sits outside any target so `extract_specs.rb` drops it. Pass 2
  now links `libOakDebug.a` **in Debug only**. See "Debug config" under Phase 2.5's
  follow-ups for why Debug-only is load-bearing rather than incidental.

## Open decisions (need user input eventually)

- Signing identity / notarization account for Stream 3.

## Decided

- **arm64-only, not universal2 (2026-07-26).** TextMate-NG ships Apple Silicon
  only. The macOS 15 floor already excludes every pre-2018 Intel Mac; Rosetta is
  winding down, so investing in x86_64 now means building for a platform Apple is
  retiring. Decisively, universal2 would require fat-building capnp/boost/
  sparsehash per architecture — reintroducing the two-prefix `~/nix-sdk` setup
  Stream 2 just eliminated — in exchange for a shrinking slice of users who are
  not a developer text editor's audience. The arm64 build is also ~42% smaller
  than upstream's universal one. `ARCHS` is one line in
  `ide/seed_xcodeproj.rb` if this is ever revisited; the expensive half is the
  universal dependency chain, which is what's being deferred.
- **rave build fate (2026-07-25):** keep it green in parallel until the test suites
  and default-bundles provisioning are migrated to the Xcode world, then tag and
  delete. See "rave retirement policy" under the Phase 2 cutover criteria.

### Phase 4 — BundleEditor (⚠️ partially done 2026-07-27)

**Done:** `PropertiesViewController` and `OakRot13Transformer` are Swift, plus a
`BESupport.h` shim for `decode::rot13`. `PropertiesViewController` is the File's
Owner of **all 8 property xibs** (Bundle, Command, FileDrop, Grammar, Macro,
Shared, Snippet, Theme), so one small class carries eight nib contracts: the
class name, the outlets `objectController` / `alignmentView` /
`keyEquivalentView`, and the `properties` key path their object controllers bind
to.

**Not done: the `BundleEditor` window controller itself (1072 lines).** This is a
deliberate stop, not an oversight — the survey found it is *not* the leaf its line
count suggested:

- Its **core state is C++**: `be::entry_ptr` (the NSBrowser model tree),
  `std::map<bundles::item_ptr, plist::dictionary_t>` (pending edits), and
  `bundles::item_ptr` (the selected item). The browser delegate methods index
  into the C++ tree directly (`parent_for_column`).
- Property bags round-trip through **`plist::dictionary_t` with a
  `boost::static_visitor`** for `${var}` expansion — a C++ variant visitor with
  no ObjC-shaped equivalent.
- Two things **Swift structurally cannot do**: `+load` (used deliberately —
  Phase 2.5 registered the `OakRevealBundleItemNotification` observer there
  precisely because the class is otherwise instantiated lazily and would miss the
  first reveal), and subclassing `bundles::callback_t`, a C++ struct with virtual
  methods, to receive bundle-change callbacks.
- Its **public API is C++-typed**: `-revealBundleItem:(bundles::item_ptr const&)`,
  called from two other targets (`AppController.mm`, `DocumentWindowController.mm`).

Porting it therefore means first writing a real ObjC model layer (`BEModel`)
wrapping the entry tree, item operations and plist conversion — a few hundred
lines of *new* ObjC++ whose only purpose is to let Swift drive C++ it could
otherwise drive directly. That is a legitimate application of the roadmap's
"expose a clean interface at the boundary" recipe, but it is a materially bigger
and riskier job than CommitWindow or Preferences, and it should be scheduled as
its own piece of work rather than folded into a "1.3k-line leaf".

**Recipe note that generalizes** (hit here first, will recur): a framework whose
Swift **module** name matches one of its own **ObjC class** names cannot import
its generated `*-Swift.h` from ObjC++ under `SWIFT_OBJC_INTEROP_MODE=objcxx` —
the header emits `namespace <Module> { … }` and clang rejects it as "redefinition
of 'X' as a different kind of symbol". The fix is the same hand-written-header
pattern used for cross-target consumers, applied *internally*: see
[`BESwiftClasses.h`](Frameworks/BundleEditor/src/BESwiftClasses.h). Nothing checks
those declarations against the Swift definitions at build time — a mismatch is an
unrecognized selector at runtime.

**Verification gap — closed 2026-07-28**, see "Nib-contract tests" below. The 8
property xibs now have direct coverage.

### Phase 4 infrastructure — nib-contract tests (Done 2026-07-28)

Nib wiring is the one thing in these ports that fails **silently**: renaming a
Swift class, an `@IBOutlet`, or a bound key path produces no build error and no
test failure — just a dead pane, found whenever a user next opens it. Through the
first three ports the only check was launching the app and looking, and for
BundleEditor even that was impossible (NSBrowser would not take a synthetic
selection). Test bundles could not cover it because `ide/seed_xcodeproj.rb`
Pass 4 built them with **no resources at all**, so any nib load failed.

- **Seed:** `add_test_resources` copies the framework's own `Resources` assets
  into its `.xctest` bundle, routing `.lproj` content through `add_localized`
  (a `PBXVariantGroup`) so xibs go through Xcode's ibtool rule — the same
  mechanism Pass 3 uses, and for the same reason. Deliberately *not*
  `asset_closure`: a test needs the nibs of the framework under test, and pulling
  every transitive dependency's resources into 28 bundles would cost build time
  and reintroduce the duplicate-basename collisions Pass 3 dedups around.
- **Tests:** 10 in `BundleEditorTests` (one per property xib, plus the
  `properties` key path and the key-equivalent view) and 4 in `PreferencesTests`
  (TerminalPreferences' nib, its 5 outlets, the misspelled
  `installIndicaitorImage` binding, and the defaults-backed key paths that go
  through `PreferencesPane`'s undefined-key routing). **339 tests, 28 bundles.**

Two real bugs surfaced on the suite's first run — the gap was hiding things:

1. **`CommandProperties.xib` could only be loaded after `+[BundleEditor
   sharedInstance]` had run.** It binds through six named value transformers that
   the singleton registered in its `dispatch_once`. Nothing enforced that order;
   it merely happened to hold because the Bundle Editor window is the only way to
   reach those nibs. Registration moved to `+load`, which that file already uses
   for exactly this "must exist before anyone asks" reason.
2. **`TerminalPreferences.init()` was never exposed to ObjC.** Swift stopped
   inferring `@objc` for members of ObjC subclasses in Swift 4, so `-init` fell
   through to `NSViewController`'s, which chains to `-initWithNibName:bundle:` —
   an initializer `PreferencesPane` does not implement (it declares its own
   designated init, so `NSViewController`'s are not inherited) — and the Swift
   runtime trapped. Invisible until something creates the class from ObjC, which
   is precisely what a test does.

**Interop hazard worth carrying forward:** an `NSException` raised inside nib
loading now unwinds through a Swift frame (`-[NSViewController view]` calls into
Swift's `loadView`), and the Swift runtime aborts with *"C++ exception handling
detected but the Swift runtime was compiled with exceptions disabled"*. What used
to be a catchable, loggable ObjC exception is now immediate process death — so
latent ordering bugs like #1 stop being survivable as this layer moves to Swift.

Recipe notes:
- A test bundle reaches Swift classes that are `internal` to their framework via
  the **hand-written ObjC declaration** (`BESwiftClasses.h`,
  `TerminalPreferences.h`) plus `-ObjC` force-loading the linked archive — *not*
  by recompiling the Swift sources into the test bundle, which would put two
  `@objc` classes with the same runtime name in one process.
- Any initializer a test (or any ObjC caller) uses must be explicitly `@objc`.
- Bridging headers are now looked up in `<dir>/tests/` before `<dir>/src/`.
- `TerminalPreferencesNibTests` deliberately avoids `-[NSViewController view]`:
  `loadView` calls `LSSetDefaultHandlerForURLScheme("txmt", …)`, which would
  register the *test runner* as the machine's txmt:// handler. It instantiates
  the nib directly with the controller as File's Owner instead, which exercises
  the contracts under test without the side effect.

### Phase 4 coupling survey (2026-07-28)

Re-run with `python3 ide/coupling_survey.py`. The roadmap originally ordered
frameworks by `wc -l`; BundleEditor proved that misleading, so this measures what
actually cost time on the three completed ports.

| framework | loc | pubAPI | state | sigs | +load | cbk | xib | score |
|---|---:|---|---:|---:|---:|---:|---:|---:|
| HTMLOutputWindow | 77 | shim | 0 | 0 | 0 | 0 | 0 | **0** |
| CrashReporter | 262 | direct | 0 | 0 | 0 | 0 | 0 | **1** |
| MenuBuilder | 399 | shim | 0 | 0 | 0 | 0 | 0 | **1** ⚠️ |
| BundleMenu | 240 | shim | 0 | 1 | 0 | 0 | 0 | **1** |
| SoftwareUpdate | 1243 | direct | 0 | 0 | 0 | 0 | 0 | **2** (deferred) |
| **OakTabBarView** | **1601** | **direct** | **0** | **0** | **0** | **0** | **0** | **3** |
| TMFileReference | 761 | shim | 1 | 1 | 0 | 0 | 0 | 11 |
| HTMLOutput | 715 | shim | 1 | 3 | 0 | 0 | 0 | 12 |
| OakCommand | 672 | shim | 1 | 5 | 0 | 0 | 0 | 14 |
| BundlesManager | 995 | shim | 4 | 3 | 0 | 0 | 0 | 37 |
| Find | 3123 | shim | 4 | 5 | 0 | 0 | 0 | 43 |
| OakAppKit | 4815 | shim | 3 | 12 | 0 | 0 | 2 | 46 |
| DocumentWindow | 3564 | shim | 4 | 11 | 0 | 0 | 0 | 50 |
| OakFilterList | 2528 | shim | 7 | 4 | 0 | 0 | 0 | 65 |
| FileBrowser | 4585 | shim | 4 | 9 | 3 | 0 | 0 | 65 |
| BundleEditor | 1254 | shim | 3 | 9 | 1 | 1 | 8 | 141 |
| OakTextView | 6917 | shim | 16 | 53 | 0 | 4 | 1 | 595 |

`state` = C++ ivars/properties, `sigs` = ObjC methods with C++ in their
signature, `cbk` = C++ virtual-callback subclasses, `pubAPI` = whether the public
headers parse as plain ObjC. **`pubAPI: shim` is not by itself a blocker** —
bridging headers are compiled with `SWIFT_OBJC_INTEROP_MODE=objcxx` and can read
C++; it means consumers face interop questions, not that the port is hard.

The ranking validates against experience: **OakTextView is worst by 4×**, which
is exactly the framework the roadmap says stays ObjC++ permanently, and
**BundleEditor is second-worst despite being only 1254 lines** — matching what
the partial port actually ran into.

**Recommended next: `OakTabBarView` (1601 lines).** Substantial, user-visible UI
with *zero* C++ state, zero C++ method signatures, no `+load`, no callback
subclasses, no nibs, and a public API that imports as plain ObjC. It is the only
sizeable framework in the tree with a clean bill on every axis. Note its one C++
line — `std::vector<tab_t>` in a local layout routine (`OakTabBarView.mm:1093`)
— is a function-local, not state.

Corrections this survey makes to the old ordering:

- **`Find` (3.1k) was slated next; it should not be.** At score 43 it is an order
  of magnitude harder than OakTabBarView for twice the code. Still a reasonable
  mid-wave pick, just not the next one.
- **`OakFilterList` is worse than its size suggests** (7 C++ state members —
  the highest outside OakTextView). Demote it below DocumentWindow.
- **`FileBrowser`'s three `+load` are harmless** — each is a one-line
  `[self registerClass:… forURLScheme:…]`, nothing like the ordering guarantee
  BundleEditor's encodes. Its score is volume, not structural blockage.
- ⚠️ **`MenuBuilder` scores 1 but is a trap.** Its *public API is a C++ DSL* —
  `typedef std::vector<MBMenuItem> MBMenu` plus a designated-initializer
  aggregate, which Swift cannot construct (both the CommitWindow and Preferences
  ports had to hand-roll menus instead of calling `MBCreateMenu`). Porting it
  means redesigning that API for Swift callers, which is a design decision, not
  a mechanical port. The score is low because the C++ is a typedef rather than
  state — a known blind spot of the metric.
- **`HTMLOutputWindow` (77 lines) is trivial but coupled**: it scores 0 only
  because it is nearly empty, and it imports `<HTMLOutput/HTMLOutput.h>`, so it
  is best done together with HTMLOutput (715).

### Phase 4 — OakTabBarView (started 2026-07-28)

Picked off the coupling survey as the best remaining candidate. **Started, not
finished:** `OakTabItem` (the tab model and drag payload) and `OakBox` are Swift;
`OakTabView` and `OakTabBarView` itself (1234 lines) are still ObjC++.

Two findings, both of which the survey had missed:

1. **`OakAnimatorProxy` must stay Objective-C permanently.** It is an `NSProxy`
   that forwards every message to its target inside an implicit-animation group
   — the trick behind `tabView.animator.frame = …`. Swift cannot express either
   half: `NSProxy` is not an `NSObject` subclass, and `-forwardInvocation:`
   needs `NSInvocation`, which **Swift cannot import at all**. Split out into
   [`OakAnimatorProxy.h/.mm`](Frameworks/OakTabBarView/src/OakAnimatorProxy.mm).
   `ide/coupling_survey.py` grew an `objc` column for exactly this class of
   blocker — it had been measuring C++ coupling only, and scored this framework
   a clean 3 while it contained something as impossible for Swift as a C++
   virtual subclass. OakTabBarView now scores 23; still the best sizeable
   candidate, and the ranking is otherwise unchanged.
2. **`OakTabBarViewController` (235 lines) was dead code — deleted 2026-07-28.**
   Nothing in the tree referenced it — not source, xib, plist, or spec (beyond
   its own `headers` export). `DocumentWindowController` builds an `OakTabBarView`
   directly and implements `OakTabBarViewDataSource` itself. Removed the `.h`/`.mm`
   and its `default.rave` `headers` entry (the `sources src/*.{mm,swift}` glob
   dropped the `.mm` automatically), in the spirit of the Phase 2.5 dead-code
   removals. Build and the full suite stayed green across the deletion.

**A porting hazard worth memorising, caught only by running the app:**

```objc
@property (nonatomic, getter = isSelected) BOOL selected;   // -selected / -setSelected:
```
```swift
@objc(isSelected) var selected: Bool                        // -isSelected / -setIsSelected:  ⚠️
```

`@objc(name)` on a Swift *property* renames the property, so the setter becomes
`setIsSelected:` — it is **not** the equivalent of ObjC's `getter=` attribute.
The build was clean, the tests were green, and the app died with
`-[OakTabItem setSelected:]: unrecognized selector` the moment a second tab
opened. The only spelling that reproduces the ObjC accessor pair is to annotate
each accessor:

```swift
@objc var selected: Bool {
    @objc(isSelected) get { _selected }
    @objc(setSelected:) set { _selected = newValue }
}
```

Both `selected` and `modified` had it. **Grep any framework for `getter =`
before porting its properties** — this pattern is common in this codebase.

Verified in the running app: three files opened into one project window render
three correctly-titled tabs with the right one selected and its content shown;
no unrecognized-selector faults in the log.

**The remaining ~1150 lines were one indivisible unit — ✅ ported together
2026-07-28.** `OakTabView` (~400 lines) and `OakTabBarView` (~700) are mutually
coupled: OakTabBarView's class extension declared `OakTabView*`/`OakTabFrame*`
properties and its layout code makes ~40 references across 12+ distinct
OakTabView members (`tabItem`, `frame`, `hidden`, `overflowButtonVisible`,
`dragImage`, `target`, `action`, `doubleAction`, `dragAction`, `fittingSize`,
`backgroundView`…). Porting either alone would have meant hand-declaring the
other's interface in `OTBSwiftClasses.h` **with nothing checking it against the
Swift** — exactly how the `setSelected:` crash above happened, multiplied by
twenty. Both went in one change, so **`OTBSwiftClasses.h` and `OTBObjCClasses.h`
are deleted rather than grown**, along with `OakTabBarView.mm` (1234 lines).
`OakTabFrame` (a 20-line layout value object) went with them, as a Swift
`NSObject` subclass.

### Phase 4 — OakTabBarView complete (2026-07-28)

**The framework is now Swift except `OakAnimatorProxy`** (which stays ObjC
permanently, see above): `OakTabBarView.swift`, `OakTabView.swift`,
`OakTabItem.swift`, `OakBox.swift`. Net −1317/+26 lines against the ObjC++.
Also deleted first, as a separate verified commit: the dead
`OakTabBarViewController.{h,mm}` (235 lines).

Five things this port established that the earlier ones did not:

1. **Splitting the protocols out of the public header is what makes the
   module-name collision survivable.** The bridging header still cannot import
   `OakTabBarView.h` (module name == class name, the `namespace OakTabBarView`
   rejection from BundleEditor), but the Swift code *needs* the delegate and
   data-source protocol types. They moved to a new
   [`OakTabBarViewProtocols.h`](Frameworks/OakTabBarView/src/OakTabBarViewProtocols.h),
   which only forward-declares the class and so carries no collision;
   `OakTabBarView.h` imports it, leaving every external consumer unchanged.
   **It must be added to the spec's `headers` line**, or consumers that import
   `<OakTabBarView/OakTabBarView.h>` fail with "file not found" — the include
   farm only exports declared headers. This is the general recipe for porting a
   framework whose module name matches its principal class.
2. **KVO-observed properties must be `@objc dynamic`, not merely `@objc`.**
   `OakTabItem`'s `title`/`path`/`modified`/`selected` are observed by
   `OakTabView`. A plain `@objc var` lets Swift store straight to the backing
   field, so the observation never fires; it only worked while every mutation
   came from ObjC, which always dispatched through the setter. Porting the
   *mutating* side (OakTabBarView) is what would have broken it — silently, as a
   tab bar that stops updating its titles.
3. **`NSKeyValueObservation` tokens sidestep the `@MainActor` deinit problem.**
   CommitWindow needed an explicit `teardown()` because a `@MainActor` class
   cannot touch its state from `deinit` under Swift 6. Observation tokens
   invalidate themselves when replaced or deallocated, so no teardown call and
   no lifetime bookkeeping. The handlers are `@Sendable`: they must **not**
   forward the observed object into the isolated region ("sending 'item' risks
   causing data races") — read from `self` inside `MainActor.assumeIsolated`
   instead, which is what the ObjC `observeValue:` did anyway.
4. **The AppKit accessibility marker protocols cannot be adopted under Swift 6**
   — `NSAccessibilityRadioButton`/`NSAccessibilityGroup` conformance "crosses
   into main actor-isolated code". Dropping the conformance costs nothing: the
   role is established at runtime by `setAccessibilityRole(.radioButton)` /
   `.tabGroup` plus the `accessibility*()` overrides, which is what VoiceOver
   actually reads. Verified in the running app — System Events resolves a tab as
   `radio button 2 of tab group 1`.
5. **`NSProxy` is reachable from Swift via `unsafeBitCast`.** The animator
   trick (`tabView.animator.mouseInside = …`) survives the port: wrap
   `super.animator()` in `OakAnimatorProxy` and bit-cast it back to the class
   type. It works only because the forwarded properties are `dynamic`, which
   forces `objc_msgSend` and so reaches `-forwardInvocation:`.

**A latent bug found and deliberately preserved:** `countOfVisibleTabs` is a
public readonly `NSInteger` property that **has no getter implementation** in the
ObjC++ original — an auto-synthesized ivar nothing ever assigned, so it always
returned 0. Its one consumer (`DocumentWindowController`'s tab auto-close) masks
it with `max(…, 8)`, so it only matters above 8 visible tabs. Ported as-is with a
comment; fixing it is a behaviour change and belongs in its own commit.

**The signedness trap bit again, and the port fixes it.** `selectedTabIndex` is
`NSUInteger` in the public header; typing it `Int` in Swift is not harmless.
`DocumentWindowController` passes `MIN(_selectedTabIndex, _documents.count-1)`,
which is `NSUIntegerMax` when the document list is empty: as `NSUInteger` that
fails the `< count` guard harmlessly (what the ObjC did), but as `Int` it arrives
as −1, **passes** the guard, and indexes the array out of bounds. Declared `UInt`.
Same lesson as the `BundlesPreferences.selectedIndex` crash — **keep bounds
checks in the unsigned domain**, and match the header's signedness exactly.

**Verified in the running app, not just built** (Debug, where `OakAssert.mm`'s
handler `abort()`s on any ObjC exception — so surviving these interactions is
itself the assertion): three files open as three correctly-titled tabs with the
right one selected and its content shown; **clicking** a tab switches selection,
content and window title (the exact path the `setSelected:` crash died on);
**⌘W** closes a tab and the bar re-lays out 3 → 2; **16 documents** render 5 tabs
with the overflow chevron on the last one — and the *selected* document is forced
into the last visible slot, which exercises the `didIncludeSelected` branch of
the layout algorithm; **clicking the overflow button** builds and pops its menu
(`TMFileReference` icons + the `setModifiedState:` category) without incident;
and **typing** in a document flips the tab's accessibility label to
`file14.txt (modified)`, proving the `modified` KVO chain and the close-button
image swap. No crash reports were generated, and the app survived all of it in a
**Debug** build — where `OakAssert.mm`'s handler `abort()`s on any ObjC
exception, so staying alive is itself the assertion. Debug and Release both
build; **358 tests across 28 bundles green**, unchanged from before the port.

> **Correction (2026-07-29).** This paragraph also claimed "the unified log shows
> zero errors, exceptions or unrecognized selectors." That was not evidence.
> `log show --predicate 'process == "TextMate"'` returns **nothing at all** for
> this app — not even the launch-time `swift-interop` message Phase 3 emits on
> every run — so the absence of errors was an absence of capture, not a clean
> run. Found while diagnosing the CommitWindow hang, where the same query hid the
> `os_log_error` that had been added specifically to make that failure visible.
> The behavioural checks and the abort-on-exception Debug build are what carry
> the verification above. **Do not cite `log show` as evidence for this app until
> the logging is shown to be captured** — and note that the diagnostic os_log in
> `CommitWindowServer.mm` was never observable either.

#### OakTabBarView tests (2026-07-28)

The port landed with no coverage — the framework was the only ported one without
a test bundle, and the roadmap's own policy is that each port lands its own.
**25 tests, `OakTabBarViewTests` (bundle 29, 383 tests total).** They drive the
bar through its *public ObjC surface* rather than its internals, because that
surface is the hand-written header nothing checks against the Swift.

The test bundle can `#import "../src/OakTabBarView.h"` — safe **here** precisely
because it is unsafe inside the framework: there is no generated
`OakTabBarView-Swift.h` in this target for the `namespace` emission to collide
with. So the tests are also the missing build-time check on that header.

Covered: the header's selector contract; data-source dispatch and reload
(add/rename/remove); selection, including that it survives a reload; the
delegate's `performCloseTab:` and the `tag` it reads; the layout — tabs stop at
`tabItemMaxWidth`, tile edge-to-edge with no gaps when squeezed, cap by
available width, and **always keep the selected document visible**
(`didIncludeSelected`); and `OakTabItem`'s pasteboard wire format.

**Two tests were checked by mutation, and the first draft of one was worthless.**
`testEditedStateReachesTheTabThroughKVO` asserted on the tab's accessibility
label — which reads *through* to the tab item, so it passed with `dynamic`
removed. The label proves nothing about the observation. The `modified`
observation's only visible effect is the close-button image swap, so the test now
asserts on that; dropping `dynamic` makes it, and only it, fail. The lesson
generalises: **when testing a KVO chain, assert on state that exists only
because the observation fired**, never on something that reads through to the
source. The signedness regression is guarded twice on purpose — the typed
assignment pins `UInt` at compile time (reverting stops the build), and a KVC
assignment reproduces the ObjC caller's path, which with a signed property dies
with `Fatal error: Index out of range`. Both verified by mutating the source and
watching them fail.

`countOfVisibleTabs`'s always-zero behaviour was pinned by a test too — now
superseded, see below.

#### Logging is observable — and the trap that hid it (2026-07-29)

**`zsh` has a `log` builtin that shadows `/usr/bin/log`.** It fails with
`too many arguments`, which looks nothing like a PATH problem, and with stderr
redirected it looks exactly like an app that logs nothing. A whole diagnostic
detour was spent this session concluding TextMate's `os_log` output "was not
observable" and that a `no main window` diagnostic "never fired". Both were
wrong. **Always spell it `/usr/bin/log`**, and never redirect its stderr while
you are still establishing whether a query works:

```
/usr/bin/log stream --predicate 'subsystem == "com.j23software.TextMate"'
/usr/bin/log show --last 30m --predicate 'process == "TextMate" AND messageType == error' --style compact
```

Proven with a deterministic probe rather than assumed: `main.mm` logs
`Received SIGTERM: Quick shutdown.`, and after `kill -TERM` that line appears
attributed to `TextMate[…]`. Levels matter for after-the-fact diagnosis —
`os_log` (default) and `os_log_error` persist to the log store; `os_log_info`
and `os_log_debug` are memory-only and need `--info`/`--debug`.

**A correction this forces.** The OakTabBarView port write-up claimed "the
unified log shows zero errors" as evidence. That query never ran. Re-run
properly, the app does emit error-level lines, but every one comes from an Apple
subsystem (`com.apple.appintents`, `AppKit:StateRestoration`, `CFNetwork`,
`BaseBoard`, `TextInputUI`) — ordinary noise for any AppKit app. Nothing from
this codebase, no unrecognized selectors, no exceptions. The conclusion stands;
the evidence for it is now real.

**New convention: [`Shared/include/oak/log.h`](Shared/include/oak/log.h)** defines
`OAK_LOG_SUBSYSTEM` (`com.j23software.TextMate`) so one predicate finds
everything the app emits, with a category per area:

```objc
static os_log_t const kLogCommitWindow = os_log_create(OAK_LOG_SUBSYSTEM, "commit-window");
```

Adoption is incremental. 168 sites still use `os_log_error(OS_LOG_DEFAULT, …)`,
which works but carries no subsystem and can only be filtered by process; a few
older sites invented non-reverse-DNS subsystems of their own (`Pasteboard`,
`KEventManager`) that group with nothing. Move them as they are touched.

#### Post-port hardening (2026-07-29)

- **`countOfVisibleTabs` fixed.** It now reports what the layout pass actually
  admits instead of the auto-synthesized 0 it had returned since the ObjC++ days.
  The consumer, `DocumentWindowController`'s tab auto-close, computes
  `documents.count - max(countOfVisibleTabs, 8)`: with the constant 0 it always
  closed down to 8 tabs, and it now keeps whatever is on screen when that is
  more than 8 — which is plainly what the `max()` was for.
- **A crash regression the port introduced, found while fixing the above.**
  `Int(floor(visibleWidth / CGFloat(minimumTabSize)))` converts *before*
  clamping. `minimumTabSize` is the user default `tabItemMinWidth`, so 0 is
  reachable (`defaults write … tabItemMinWidth 0`), the division is then ±∞ or
  NaN, and Swift's checked `Int()` traps — killing the app as the tab bar lays
  out. The ObjC++ original ran `MIN`/`MAX` first and narrowed to `NSUInteger`
  afterwards, so it survived. Now clamped in the floating-point domain, matching
  the original for every input including NaN. **This is the third instance of
  the same rule** (after `BundlesPreferences.selectedIndex` and
  `selectedTabIndex`): *clamp in the wide domain, convert last.*
- **`CFBundleVersion` is derived**, from the HEAD commit's date via `${APP_BUILD}`
  (`ide/seed_xcodeproj.rb`), so rebuilding a commit reproduces its build number
  rather than stamping today. The `YYYYMMDD` shape is deliberate: shipped builds
  already carry `20260726`/`20260729`, and CFBundleVersion must increase
  monotonically for update ordering — a commit count would be a *decrease*.
- **README gained an "Installing a test build" section** — Apple Silicon/macOS 15
  requirements, `ditto` unpacking, and the quarantine flag, since alpha builds
  are handed over directly rather than downloaded.

**Two testing lessons, both found by tests failing rather than by review:**

1. **A test that writes to `UserDefaults.standard` poisons every later run if it
   crashes.** The degenerate-width test set `tabItemMinWidth` and restored it in
   a `defer`; a mutation run trapped before the `defer`, leaving `0` in
   `com.apple.dt.xctest.tool`, and two unrelated layout tests then failed
   claiming 20 tabs fit a 700pt bar. Overrides now go through the **argument
   domain**, which is volatile and never written to disk — verified to survive a
   deliberately crashing run.
2. **`dataSource` is `weak`, so `bar.dataSource = Stub()` deallocates
   immediately.** `reloadData()` then returns at its `guard let dataSource` and
   the code under test never runs. The test passed against the *buggy* build and
   was only exposed by mutation testing. Hold test doubles in a local — and treat
   a regression test that passes under mutation as broken, not as good news.
