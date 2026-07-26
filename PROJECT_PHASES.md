# TextMate → Swift-native macOS: Project Phases & Progress

_High-level progress tracker. Last updated: 2026-07-25 (post-overnight-loop)._

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

## Roadmap (6 phases)

| # | Phase | Status | Effort / Risk |
|---|-------|--------|---------------|
| 1 | **Build bring-up** (rave → ninja compiling) | ✅ Done / pre-existing | — |
| 2 | **Xcode migration, keep ObjC++/C++** | 🔄 In progress | Large / Med |
| 3 | **Swift interop foundation** (Clang modules, bridging, first `.swift`) | ⬜ Not started | Small–Med / Med |
| 4 | **Swift-ify the AppKit/UI shell, leaf-first** | ⬜ Not started | Very large / Med |
| 5 | **App shell & lifecycle in Swift** (= recommended end state) | ⬜ Not started | Med / Low–Med |
| 6 | **(Optional) core engine → Swift** | ⬜ Likely skip | Huge / High ⚠️ |

**Phase 3** — enable Clang modules (Phase 2 currently `CLANG_ENABLE_MODULES=NO`;
Swift needs modules), module maps, C++ interop mode, bridging header, toolchain
baseline. Land the first `.swift` file (leaf util or new feature) calling both
layers. Prove toolchain; no behavior change.

**Phase 4** — migrate ObjC++ UI frameworks Swift-ward starting where engine contact
is smallest: Preferences, SoftwareUpdate, CommitWindow, Find, FileBrowser,
BundleEditor → then DocumentWindow/OakAppKit. Keep `OakTextView` (the NSView text
surface) as ObjC++ — tightest engine coupling. **Precondition: a working test
suite in the Xcode world (see "Tests" below) — refactoring the UI layer without a
regression net is the biggest avoidable risk in the whole plan.**

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
| 1 | **Xcode workspace scaffold** (48 frameworks + 11 apps) — critical path | 🔄 In progress (app links; launch pending) | — |
| 2 | Dependency integration (capnp/boost/Onigmo/kvdb) — make deps reproducible, not `~/nix-sdk` user-local paths | 🔄 In progress (prefix resolver landed; formalize/lockfile TBD) | 1 |
| 3 | Code signing & notarization (real identity; ad-hoc already proven) | ⬜ Not started | 1 |
| 4 | Raise deployment target (macOS 15) + remove dead guards | ✅ Done 2026-07-24 (unmerged) | — |
| 5 | API modernization (WebView→WKWebView, KVO) | ⬜ Not started | 1 |
| 6 | CI/CD (xcodebuild) | ⬜ Not started | 1, 2 |

### Phase 2 definition of done (cutover criteria)
Phase 2 is done when the Xcode build is at **feature parity** and rave/ninja can be
deleted:
- [ ] `TextMate.app` builds, launches, opens/edits/saves documents
- [ ] Bundles + plugins load (Dialog, Dialog2), QuickLook generator works
- [ ] All 11 CLI tools work (`mate`, `tm_query`, …)
- [ ] Default-bundles provisioning has an Xcode-world answer (see below)
- [ ] Test suites migrated and green (see below)
- [ ] CI builds + tests on a clean machine (no user-local paths)
- [ ] Signed + notarized artifact
- [ ] rave/ninja retired: tag the last green rave build, then delete `bin/rave`,
      the `.rave` specs, and ninja glue

**rave retirement policy (decided 2026-07-25):** keep the rave/ninja build limping
(green, low-effort) during Phase 2 — it is still the only home of the ~26 test
suites and the `DownloadBundles` provisioning step. Once **tests** and
**default-bundles provisioning** have Xcode-world answers, tag the final rave-green
commit (e.g. `rave-final`) and delete rave/ninja from the tree. No indefinite
dual-build maintenance beyond those two migrations.

### Stream 4 — Done (branch `claude/upbeat-galileo-eae114`, **not merged**)
- Deployment floor raised to **macOS 15.0 Sequoia** via `default.rave` `APP_MIN_OS`.
- All dead version guards removed (−213 lines), verified by full build.
- Follow-ups: **merge the branch**; 2 `@available` sites in the `PlugIns/dialog`
  submodule left untouched (submodule-pointer scope).

### Stream 1 — In progress (branch `claude/xcode-stream1-seed`)
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
- [ ] App bundle layout: resources / plugins / tools copy phases (in progress —
      uncommitted "Pass 3" in the seed)
- [ ] **Launch-verify** `build/Release/TextMate.app`
- [ ] Update `ide/PHASE2_PROGRESS.md` (its "BLOCKED" section is stale — the
      blocker was resolved in `4780a653`)

**Authoritative Stream-1 handoff:** [`ide/PHASE2_PROGRESS.md`](ide/PHASE2_PROGRESS.md).

---

## Tracked but not yet scheduled

- **Test-suite migration.** The rave graph declares ~26 `tests`/`cxx_tests` suites
  across `Frameworks/*/default.rave` (CxxTest-based, incl. GUI tests). The
  extractor currently ignores them. Needs a home: either CxxTest runner targets in
  the Xcode project or a wrap-in-XCTest strategy. Gates the Phase 2 cutover and is
  a hard precondition for Phase 4.
- **Default-bundles provisioning.** rave has a `DownloadBundles` build step
  (`bl install` → `DefaultBundles`); the Xcode build has no equivalent yet. Decide:
  run-script phase, or rely on the app's runtime bundle install
  (`AppController.mm` references DefaultBundles). Note the `bl` server has been
  unreachable from this machine — non-fatal, but affects the decision.
- **Dependency-cycle refactors.** 3 cyclic SCCs in the lib graph, all breakable
  with ~4 small refactors (cut `command→OakAppKit`, `io→ns`, `document→FileBrowser`,
  `OakCommand→BundleEditor`). The seed sidesteps them (no lib↔lib target edges;
  ld64 resolves archive cycles), so they don't block Stream 1 — but do them before
  Phase 3/4: cycles will fight modularization and Swift target boundaries.
- **Branch integration order.** Stream 4 (`claude/upbeat-galileo-eae114`) and
  Stream 1 (`claude/xcode-stream1-seed`) are both unmerged, off master. Stream 1's
  seed already assumes the 15.0 floor, so merge Stream 4 first (or fold it in).
- **Architecture decision: arm64-only vs universal.** Everything proven so far is
  arm64 Release. macOS 15 still runs on 2019–2020 Intel Macs, so universal2 is a
  real question — and the nix-sdk deps are per-arch. Decide before Stream 3
  (signing/notarization of the shipped artifact).
- **Debug configuration.** Seed work has been Release-only (incl. an NDEBUG
  define decision at link time). A working Debug config (asserts, `libOakDebug`)
  is needed before Phase 2 ends — day-to-day development depends on it.

## Open decisions (need user input eventually)

- Universal binary vs arm64-only (above).
- Signing identity / notarization account for Stream 3.

## Decided

- **rave build fate (2026-07-25):** keep it green in parallel until the test suites
  and default-bundles provisioning are migrated to the Xcode world, then tag and
  delete. See "rave retirement policy" under the Phase 2 cutover criteria.
