# TextMate Phase 2 — Stream 1 (Xcode migration) progress & handoff

_Last updated: 2026-07-25. Branch: `claude/xcode-stream1-seed` (off `master`)._

This doc is the entry point for a **looping/autonomous session** continuing the
Xcode migration. Read it top to bottom, then work the "Next actions" list.

## Goal of Stream 1
Replace the `rave`→`ninja` build with a **hand-authored `TextMate.xcodeproj`**
(user's decision: Apple-native format, not XcodeGen/Tuist/SPM). Tactic: **seed the
project programmatically once, then maintain it natively.** No Swift; ObjC++/C++
kept. This pass targets a **fully linked, launchable `TextMate.app`**.

## How the seed works (the two scripts)
```bash
# 1. Extract the target graph from the .rave specs -> JSON
ruby ide/extract_specs.rb > ide/gen/specs.json
# 2. Generate TextMate.xcodeproj from that JSON (re-runnable; rebuilds from scratch)
ruby ide/seed_xcodeproj.rb
```
- `ide/extract_specs.rb` — mirrors rave's DSL grammar (see `bin/rave` `Parser`).
  Emits per-target: name, dir, sources (globbed), headers, require/require_headers,
  libraries, frameworks, executable, prefix, ln_flags, files/copy (with `@refs` +
  dest), entitlements, and per-target add-FLAGS. **66 targets parsed.**
- `ide/seed_xcodeproj.rb` — uses the `xcodeproj` gem to author the `.pbxproj`.
  Creates a target per spec, classified by `kind()`:
  app / qlgen / plugin / tool / lib. Currently emits **65 targets** (skips the
  `NewApplication` template) + an **`AllLibs`** aggregate.

Environment note: `gem install --user-install xcodeproj` (1.28.1, works on system
ruby 2.6). Network IS available; the offline caveat is only the `bl` bundle server.
`ide/gen/` (farm + specs.json + build logs) and `TextMate.xcodeproj/` are gitignored
during seeding — regenerate them with the two commands above.

## What is PROVEN to build (via `xcodebuild`, Xcode 26.6, arm64, Release)
Individually, these all compile clean to `build/Release/*.a`:
- `text` (leaf lib), `cf` (dep on text), `encoding` (Cap'n Proto codegen),
  `network` (9 C++ sources, curl/Security).
- Mechanisms proven: C++2a; the language-dispatching PCH `Shared/PCH/prelude.h`;
  the `<fw/header.h>` include farm (`ide/gen/include/`); custom `PBXBuildRule`s for
  Ragel (`*.rl`→`.cc`) and Cap'n Proto (`*.capnp`→`.capnp.cpp`+`.h`, auto-compiled);
  quote-surviving `-DNULL_STR`/`-DREST_API`; per-arch nix-sdk include/lib paths.

## KNOWN ISSUE (start here)
`xcodebuild -target AllLibs` fails, but **every lib builds fine in isolation.**
Failures manifest as `no type named 'string' in namespace 'std'` cascading from
`oak/algorithm.h` / `<fw>/*.h` during **PCH precompilation** under the parallel
build. Strong hypothesis: **parallel shared-PCH contention** — all targets share
one prefix-header path, so `build/SharedPrecompiledHeaders/` entries collide/race.
- **First thing to try:** confirm with a serial build:
  `xcodebuild -target AllLibs -jobs 1 -configuration Release build`
  If that passes, it's the race. Fixes to try (in order):
  1. Per-target precomp dir: set `SHARED_PRECOMPS_DIR = $(OBJROOT)/PCH/$(TARGET_NAME)`
     in `apply_common_settings` (in `ide/seed_xcodeproj.rb`).
  2. Or give each target a distinct `GCC_PREFIX_HEADER` copy (less clean).
  3. Or, worst case, `GCC_PRECOMPILE_PREFIX_HEADER = NO` (slower but correct).
- Logs from the last run: `ide/gen/alllibs_build.log`, `ide/gen/network_build.log`.

## Next actions (in order)
1. **Fix the AllLibs parallel-PCH issue** (above). Success = all 50 libs → `.a`.
   Expect a handful of genuine per-lib compile errors underneath the race; fix
   each (likely: vendored `Onigmo`/`kvdb` flag/PCH quirks; missing farm umbrellas
   for bare-name includes like `<oniguruma.h>`; a target needing its own `src` on
   the header path). Iterate `seed → build AllLibs → fix`.
2. **CLI tools + loadable bundles** (task 7). Product types already assigned
   (`:command_line_tool`, `:bundle` with `WRAPPER_EXTENSION` tmplugin/qlgenerator).
   Still TODO: **link wiring** — for each tool/bundle, compute `lib_closure()`
   (already implemented in the seed) and add each lib product to the target's
   Frameworks build phase + `add_dependency`, plus external libs via `LIB_LDFLAGS`
   (`-lcapnp -lkj -lcurl -liconv -lsqlite3 -lz`, `-L~/nix-sdk/arm64/lib`) and
   `-framework X` for each spec framework (union over closure). ld64 resolves
   static-archive cycles, so **do not** add lib↔lib target-dependency edges
   (Xcode forbids cycles; libs build independently — header visibility is the farm).
3. **TextMate.app** (task 8): link the full `require` closure + external libs +
   frameworks; reproduce the bundle layout from the spec's `files`/`copy`:
   - `files resources/* icons/*.icns @PrivilegedTool "Resources"`,
     `files @mate @tm_query "MacOS"`, `files about/* "Resources/About"`,
     `copy support/* "SharedSupport"`, `copy @Dialog @Dialog2 "PlugIns"`,
     `copy @TextMateQL "Library/QuickLook"` → Copy-Files build phases; the `@refs`
     are built-product copies (also add as target dependencies).
   - `Info.plist` is a **preprocessed template** (`${APP_VERSION}` etc. via
     `PLIST_FLAGS`). Either pre-generate it or use `INFOPLIST_PREPROCESS=YES` with
     the right defines. Check `Applications/TextMate/Info.plist`.
   - Entitlements: `Applications/TextMate/Entitlements.plist`; ad-hoc codesign
     (`CODE_SIGN_IDENTITY = -`) is fine for a local launchable build.
   - Also copy framework-declared resources (e.g. `OakTextView` `files resources/*`)
     into the app if UI assets are missing at runtime.
4. **Verify**: build `TextMate` target, then launch `build/Release/TextMate.app`.

## Guardrails for the loop
- Keep each iteration = re-run both scripts, build a single target or `AllLibs`,
  read errors, fix the **generator** (`ide/*.rb`), not the generated project.
- Commit meaningful green steps on `claude/xcode-stream1-seed` (co-author line per
  repo convention). Don't commit `TextMate.xcodeproj/`, `build/`, or `ide/gen/`.
- Do NOT touch `bin/rave` (pre-existing local edit, unrelated) or the `.claude/`
  worktrees. Deployment target is 15.0 (migration floor; SDK min is 10.13).
- Stream-4 (macOS-15 floor + dead-guard removal) lives on branch
  `claude/upbeat-galileo-eae114`, NOT merged to master; not required for the seed.
- The 3 dependency cycles (io↔ns↔plist etc.) do NOT block the static-lib seed.

## Task list (mirror of the session tracker)
- [x] Slice 1: `text` leaf lib   - [x] Slice 2: `cf` inter-target
- [x] Slice 3: Ragel + Cap'n Proto build rules
- [x] Extractor (`ide/extract_specs.rb`, 66 targets)
- [ ] Emit + compile all 50 libs (blocked on AllLibs parallel-PCH; see above)
- [ ] CLI tools + loadable bundles (link wiring)
- [ ] TextMate.app: link + bundle phases + Info.plist + entitlements + codesign
