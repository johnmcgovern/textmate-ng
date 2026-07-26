# TextMate Phase 2 — Stream 1 (Xcode migration) progress & handoff

_Last updated: 2026-07-25 (Stream 2 dep-prefix resolver). Branch: `claude/xcode-stream1-seed` (off `master`)._

## ✅ STREAMS 2 & 6 — reproducible deps + xcodebuild CI (validated on runner)
`xcodebuild -target TextMate` now builds `TextMate.app` on a clean `macos-latest`
runner via the new `xcode` CI job, linking capnp/kj from `/opt/homebrew/lib` (the
`brew --prefix` default; **no `TM_DEP_PREFIX`, no `~/nix-sdk`**) → `** BUILD
SUCCEEDED **` + codesign. Both CI jobs (`build`=ninja, `xcode`=xcodebuild) are green
(run 30181678660). Optional remaining hardening: pin dep versions (Brewfile) instead
of floating Homebrew formulae. Detail below.


The Xcode seed no longer hardcodes `~/nix-sdk/{arm64,x86_64}`. `ide/seed_xcodeproj.rb`
now resolves external deps (capnp/kj/boost/sparsehash) through a **`DEP_PREFIXES`**
list, mirroring `./configure`:
- **Default:** `brew --prefix` (→ `/opt/homebrew` on Apple Silicon, `/usr/local` on
  Intel; `/usr/local` if brew is absent). This makes the Xcode build reproducible on
  a clean CI runner after `brew install boost capnp google-sparsehash …` — the same
  formulae the ninja CI already installs — which is the precondition for Stream 6.
- **Override:** `TM_DEP_PREFIX` (colon-separated list) for non-Homebrew setups. The
  local dev box still builds with
  `TM_DEP_PREFIX="$HOME/nix-sdk/arm64:$HOME/nix-sdk/x86_64"` (boost header-only lives
  only under the x86_64 prefix). Each prefix contributes `<p>/include` + `<p>/lib`.

The capnp/ragel **codegen tools** (invoked by name inside Xcode script build rules,
which run with a sanitized PATH) now also resolve from `DEP_PREFIXES`: the rule PATH
is `<prefix>/bin … : $HOME/.nix-profile/bin : $PATH`, so Homebrew's `capnp`/`ragel`
are found on a runner while the nix dev box still uses `.nix-profile/bin`. (The
earlier nix-override build didn't catch this — it kept using `.nix-profile/bin`.)

Verified behavior-preserving: regenerate + `xcodebuild -target TextMate` with the
nix override → **BUILD SUCCEEDED**, `codesign --verify --deep --strict` passes.

Still TODO for Stream 2 to be "done": confirm the Homebrew default actually builds on
a runner — now wired as the **Stream 6 `xcode` CI job** (`.github/workflows/build.yml`),
which regenerates the seed and `xcodebuild`s with the Homebrew default (no
`TM_DEP_PREFIX`). Then decide whether to pin dep versions (lockfile / `brew bundle`
Brewfile) for true reproducibility vs. floating formulae.

**CI triage log** (run 30181050582): the `xcode` job's *first* run exposed a
generator fragility the local build masked — `seed_xcodeproj.rb` read specs.json via
`ide/gen/include/../specs.json`, whose `..` needs `ide/gen/include/` to pre-exist. On
a clean checkout that dir doesn't exist yet (the seed creates it), so the read hit
ENOENT. Fixed: read `ide/gen/specs.json` directly via a new `GEN_DIR` constant. The
ninja `build` job stayed green throughout.

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

## ✅ STREAM 1 COMPLETE (launch-verified 2026-07-26)

> **Correction.** The 2026-07-25 version of this section claimed the app
> "launches without crashing". It did not — the first real launch attempt exited
> immediately with `Unable to load nib file: MainMenu, exiting`. A passing
> `codesign --verify --deep --strict` had been read as evidence of launchability;
> it only ever proved the signature was internally consistent. **Do not treat
> codesign or a green build as a launch check — run the binary.**
>
> Root causes, both in Pass 3 of `ide/seed_xcodeproj.rb`, both now fixed:
> 1. **Xibs were never compiled.** rave's `CompileXib` (`.xib` → `.nib` via
>    `xcrun ibtool`, `bin/rave:667`) had no seed equivalent, so the bundle shipped
>    a raw `MainMenu.xib`.
> 2. **Framework resources were never copied.** rave bundles the assets of every
>    target in the require closure (`signature` → `required_targets(…,
>    include_self: true)` → `assets` → CopyFile); the seed only walked the app's
>    own `files`/`copy`. All 13 framework xibs plus their images/plists were
>    missing.
>
> Implementation notes for whoever touches this next:
> - `asset_closure(name)` mirrors rave's `required_targets(include_self: true)`.
> - `.lproj` **directory** inputs are expanded one level (`files resources/*`
>   globs the directory, not its contents).
> - Anything living in a `.lproj` is added to the **Resources build phase inside a
>   PBXVariantGroup**, not a Copy Files phase. This is load-bearing twice over: it
>   is what triggers Xcode's built-in ibtool rule, and Copy Files phases get the
>   `.lproj` re-appended by Xcode on top of `dst_path`, producing
>   `Resources/English.lproj/English.lproj/`.
> - Destinations are deduped on `(subfolder, path, basename)` — with ~40 targets
>   contributing files, two build commands writing one path is a hard Xcode error.
>
> Result: app wrapper went from ~66 to **204 files + 14 localized resources**.
> Verified from a clean `rm -rf build`: `** BUILD SUCCEEDED **`, 0 raw xibs, 0
> nested `.lproj`, codesign passes, app launches and stays alive as a foreground
> GUI process, and `mate --name smoke <file>` opens a document into the running
> app with nothing logged to the unified log.

`xcodebuild -target TextMate` produces a complete, ad-hoc-signed, **launchable**
`TextMate.app` (50 libs + 11 tools + 3 bundles + app). The blocker below was resolved with
**option 4**: a no-umbrella variant farm (`ide/gen/include-nou`) lets WebKit-pulling
targets resolve `<Network/Network.h>` to Apple while keeping TM's `<network/…>`.
Also: per-target `ln_flags` propagation (license weak-import), app Info.plist/
entitlements/version, and Pass 3 bundle layout (Copy Files phases for files/copy +
@ref products). Seed regenerates the whole project: `ruby ide/extract_specs.rb >
ide/gen/specs.json && ruby ide/seed_xcodeproj.rb`. Streams 2/3/5/6 + Phase 3 remain.

<details><summary>Resolved blocker (was: WebKit↔network SDK collision)</summary>

## ⛔ BLOCKED — needs a user decision (2026-07-25, task 3 / the app)
`xcodebuild -target TextMate` fails to compile the app. Everything else is green:
50 libs (AllLibs), all 11 CLI tools, all 3 bundles, and the app's Info.plist /
entitlements / version / linking are all wired and working. The blocker is a
**genuine new-SDK header collision**, not a generator bug:

- `Applications/TextMate/src/AppController.mm` is ObjC++, so its PCH pulls
  `<WebKit/WebKit.h>` → `WKWebsiteDataStore.h` → `#import <Network/Network.h>`
  (an addition in the current SDK; the old rave SDK didn't do this).
- The **same TU** also does `#import <network/tbz.h>` (TM's own `network` fw).
- On case-insensitive APFS, TM's `network` farm dir and Apple's `Network.framework`
  are the same name, so `<Network/Network.h>` resolves to TM's `network/network.h`
  (→ `std::string` errors). No include-path ordering satisfies both a TM
  `<network/…>` and an Apple `<Network/…>` include in one compilation.
- Scoping the farm (done — `header_farm_dirs`) fixes every target that only *links*
  network, but not AppController.mm, which genuinely *includes* it.

**Confirmed:** `AppController.mm` uses **both** WebKit *and* `<network/tbz.h>` in the
one TU (verified), so the WebKit include can't simply be moved off it.

**Decision needed — pick one (all are out of scope for a pure generator edit):**
1. ~~Drop `<WebKit/WebKit.h>` from the shared PCH~~ — **insufficient**: AppController.mm
   references WebKit itself, so it would re-include it and hit the same collision.
2. **Rename TM's `network` framework** include prefix (e.g. `tm_network`) so it can't
   collide with Apple's `Network.framework`. Touches the `<network/…>` include sites
   (network, updater, AppController.mm) + the farm dir name. Most robust.
3. **Generate a case-sensitive header map** for the farm so `<network/tbz.h>` resolves
   to TM while `<Network/Network.h>` falls through to Apple. Generator-only if hmaps
   are case-sensitive (needs verifying).
4. **Per-target farm variant**: give WebKit-overlapping targets a `network` farm dir
   *without* the `network.h` umbrella (only AppController.mm needs it, and it includes
   `tbz.h`, not the umbrella), so `<Network/Network.h>` falls through to Apple. Pure C++
   network consumers (updater) keep the full farm. Generator-only but fiddly.
Recommendation: **option 2** (most robust) or **option 4** (keeps it in the generator).
Progress committed through a73a68c4. Loop stopped pending this call.
</details>

## KNOWN ISSUE — RESOLVED 2026-07-25 (commit 9dd5daed)
`xcodebuild -target AllLibs` now builds all **50** static libs clean. The
parallel-PCH-race hypothesis was **wrong** — it failed serially too. Three real
generator bugs (each masked earlier by stale/partial build state):
1. **Build rules dropped from the object graph.** `PBXBuildRule`s were shared
   across targets and attached via `ObjectList#replace`, which doesn't parent
   them — they never serialized, so every target referenced dangling UUIDs and
   Xcode said "no rule to process file" for `*.capnp`/`*.rl`. Fix: fresh rule
   objects per target, appended with `<<` (not `replace`).
2. **Flat farm shadowed a system framework.** One flat `-I ide/gen/include` on
   every target let TM's `network` fw shadow Apple's `<Network/Network.h>` (pulled
   in by the WebKit PCH). Fix: double-nested farm (`ide/gen/include/<fw>/<fw>/*.h`)
   + per-target header paths scoped to the transitive `require`/`require_headers`
   closure (`header_closure`), mirroring rave's per-target `-I _Include/<fw>`.
3. **Own src dir on the angle path shadowed system headers.** `regexp/src/glob.h`
   shadowed POSIX `<glob.h>`. Fix: own dirs go on the quote-only path
   (`USER_HEADER_SEARCH_PATHS` + `ALWAYS_SEARCH_USER_PATHS=NO`).
Rebuild check: `xcodebuild -project TextMate.xcodeproj -target AllLibs -configuration Release clean build` → 50 `.a` in `build/Release/`.

## Next actions (in order)
1. ~~Fix the AllLibs parallel-PCH issue.~~ **DONE** (commit 9dd5daed) — all 50 libs → `.a`.
2. ~~**CLI tools + loadable bundles.**~~ **DONE** (commit 88126b8d). Pass 2 in the seed
   links executables/bundles against their transitive lib closure (.a in Frameworks
   phase + target dep; no lib↔lib edges) + external `-l…`/`-framework …` unioned over
   the closure. Release now defines **NDEBUG** (else oak/debug asserts reference the
   unlinked libOakDebug.a). Bundles get `INFOPLIST_FILE` → their real template plist +
   ad-hoc `CODE_SIGN_IDENTITY="-"`. All 11 tools + Dialog/Dialog2/TextMateQL build clean.
   **START HERE →** task 3 below (the app). Product types already assigned
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
- [x] Emit + compile all 50 libs (commit 9dd5daed)
- [x] CLI tools + loadable bundles (link wiring) (commit 88126b8d)
- [x] TextMate.app: link + bundle phases + Info.plist + entitlements + codesign (c8c34262)
