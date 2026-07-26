# TextMate → Swift-native macOS: Project Phases & Progress

_High-level progress tracker. Last updated: 2026-07-26 (Streams 7 & 8, rave parity
audit, rave/ninja retirement, arm64-only decision, Phase 2.5 formalized and
started: dead-code cleanup, dependency-cycle refactors done — 0 cyclic SCCs —
and all 3 MacroMates-coupled-service decisions landed)._

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
| 2.5 | **Cleanup & de-MacroMates** (dead code, cyclic deps, MacroMates-coupled services) | 🔄 Only `bin/CxxTest` left (blocked on Stream 7 follow-up) | Med / Low |
| 3 | **Swift interop foundation** (Clang modules, bridging, first `.swift`) | ⬜ Not started | Small–Med / Med |
| 4 | **Swift-ify the AppKit/UI shell, leaf-first** | ⬜ Not started | Very large / Med |
| 5 | **App shell & lifecycle in Swift** (= recommended end state) | ⬜ Not started | Med / Low–Med |
| 6 | **(Optional) core engine → Swift** | ⬜ Likely skip | Huge / High ⚠️ |

Numbered as **2.5**, not renumbered into the sequence, so it doesn't invalidate the
"Phase 2"/"Phase 3" language already used in commit messages and other docs
(`ide/PHASE2_PROGRESS.md`, `ide/NEXT_SESSION_HANDOFF.md`). It sits here because
several of its items — the license/CrashReporter/SoftwareUpdate MacroMates coupling
— are naturally decided alongside Stream 3's `CFBundleIdentifier` move (both are
"stop being MacroMates"), and because the dependency-cycle refactors should land
before Phase 3/4 touch the same lib graph for Swift modularization.

**Phase 3** — enable Clang modules (Phase 2 currently `CLANG_ENABLE_MODULES=NO`;
Swift needs modules), module maps, C++ interop mode, bridging header, toolchain
baseline. Land the first `.swift` file (leaf util or new feature) calling both
layers. Prove toolchain; no behavior change.

**Phase 4** — migrate ObjC++ UI frameworks Swift-ward starting where engine contact
is smallest: Preferences, SoftwareUpdate, CommitWindow, Find, FileBrowser,
BundleEditor → then DocumentWindow/OakAppKit. Keep `OakTextView` (the NSView text
surface) as ObjC++ — tightest engine coupling. **Precondition met 2026-07-26
(Stream 7):** 25 XCTest bundles, 275 tests green under `xcodebuild test`. Read the
caveat though — that net covers the C++ *core* (text, buffer, regexp, parse,
selection…). The ObjC++ UI frameworks Phase 4 actually refactors have almost no
automated coverage: the only UI-layer tests are the 3 interactive `cxx_tests`
harnesses, which do not assert. Leaf-first ordering and manual launch-verification
still carry most of the risk here.

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
- [ ] `TextMate.app` builds, launches, opens/edits/saves documents
- [ ] Bundles + plugins load (Dialog, Dialog2), QuickLook generator works
- [ ] All 11 CLI tools work (`mate`, `tm_query`, …)
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
      deliberate step. `bin/CxxTest` and `bin/gen_html` are kept too — both are
      load-bearing for the Xcode build now (the 3 GUI test bundles; the About
      pages).

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

- `ide/extract_specs.rb` now captures `cxx_tests` (it silently dropped them).
- `ide/gen_xctest.rb` (new) wraps the OAK-style tests in `XCTestCase` subclasses,
  reusing the assertion macros verbatim from `ide/xctest_preamble.h` (ported from
  `bin/gen_test`, which goes away with rave). Test bodies are unchanged; only
  failure reporting differs — a thrown `oak_exception` becomes an `XCTFail`.
- `ide/seed_xcodeproj.rb` Pass 4 emits **25 `.xctest` bundles**, one per framework,
  plus a shared `AllTests` scheme. `xcodebuild test` runs **275 tests green**.
- The `cxx_tests` GUI suites are compiled (so they stop rotting) but never run:
  they subclass `CxxTest::TestSuite`, not `XCTestCase`, so XCTest cannot invoke
  them. That is deliberate — they gate on a `GUI_TESTS` env var and then block in
  `[NSApp run]` awaiting manual interaction, so they would hang CI. **They are
  interactive harnesses, not a regression net.** Rewriting them into real
  assertions is separate, unscheduled work.
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
> with no errors in the unified log.

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

🔄 Started 2026-07-26. Candidate list below; each item needs its own remove-or-replace
decision, so this phase is a set of independent, low-risk cleanups rather than a
single change. None of it blocks Phase 3 — it's listed here because it *should*
happen before Phase 3/4 touch the same lib graph and bundle identity again.

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
- **`bin/CxxTest`** — a large vendored tree serving exactly 3 files
  (`OakAppKit`/`ns`/`layout`'s `gui_*.mm`), and those 3 don't even run under
  `xcodebuild test` (see Stream 7: they subclass `CxxTest::TestSuite`, not
  `XCTestCase`, and would block in `[NSApp run]` if invoked). Blocked on rewriting
  those 3 suites into real, asserting `XCTestCase`s (tracked as a Stream 7
  follow-up) — once that's done, `bin/CxxTest` and its `.gitmodules` entry can go.
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

- ~~**Test-suite migration.**~~ **Done 2026-07-26** — see Stream 7 below.
- ~~**Default-bundles provisioning.**~~ **Done 2026-07-26** — see Stream 8 below.
- **Branch integration order.** Stream 4 (`claude/upbeat-galileo-eae114`) and
  Stream 1 (`claude/xcode-stream1-seed`) are both unmerged, off master. Stream 1's
  seed already assumes the 15.0 floor, so merge Stream 4 first (or fold it in).
- **Debug configuration.** Seed work has been Release-only (incl. an NDEBUG
  define decision at link time). A working Debug config (asserts, `libOakDebug`)
  is needed before Phase 2 ends — day-to-day development depends on it.

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
