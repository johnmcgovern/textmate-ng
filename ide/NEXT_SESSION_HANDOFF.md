# Next-session handoff — TextMate Xcode migration

_Snapshot at end of session 2026-07-25. Point-in-time; when it disagrees with the
git log or the docs below, trust those._

## Where things stand
- **Branch:** `claude/xcode-stream1-seed` (off `master`), **pushed** to
  `GH—johnmcgovern` (upstream set). HEAD moves as the loop commits; the branch is
  in sync with the remote.
- **Phase 2 / Stream 1 (Xcode migration seed): COMPLETE.** `xcodebuild -target
  TextMate` builds a launchable, ad-hoc-signed `TextMate.app` — 50 static libs, 11
  CLI tools, 3 loadable bundles (Dialog/Dialog2/TextMateQL), full bundle layout,
  Info.plist/entitlements. `codesign --verify --deep --strict` passes; it launches
  without crashing.
- **CI: GREEN.** The Apple-Silicon runner fix (`brew --prefix` auto-detect) plus a
  follow-up configure lib-check fix (`bd32681b`) are pushed; the `CI` workflow
  (`configure` + `ninja TextMate`) completes green — the full 853-step rave build
  links + signs `TextMate.app` on `macos-latest`. The feared `bl DefaultBundles.tbz`
  download does not run in this path.
- **Phase 2 / Stream 2 (reproducible deps): IN PROGRESS.** The Xcode seed's
  `~/nix-sdk` hardcode is replaced by a `brew --prefix`-default `DEP_PREFIXES`
  resolver (override via `TM_DEP_PREFIX`). See `ide/PHASE2_PROGRESS.md`.

## Documentation map (read in this order)
1. `PROJECT_PHASES.md` — top-level 6-phase roadmap (milestones). End state = Swift
   app shell + SwiftUI over the kept C++ core. Phase 2 is current.
2. `ide/PHASE2_PROGRESS.md` — the detailed Stream 1 handoff: how the two seed
   scripts work, every solved gotcha, and the resolved blockers. **Don't re-derive
   these — they're written down.**
3. Auto-memory `textmate-xcode-migration-phase2.md` + `textmate-build-setup.md`.

## Immediate next steps (pick up here)
1. ~~**Push the branch** + **watch CI.**~~ **DONE** — branch pushed, upstream set,
   CI green (full rave `ninja TextMate` build links + signs the app on the
   arm64 runner; no `bl` download in that path).
2. **Finish Stream 2** — the dep-prefix resolver is in the seed (Homebrew default,
   `TM_DEP_PREFIX` override). Remaining: prove the Homebrew default builds on a
   runner (do it as part of Stream 6's xcodebuild CI job), and decide dep-version
   pinning (Brewfile/lockfile) vs. floating formulae.
3. **Then the rest of Phase 2**, remaining streams (order is flexible; 5 is
   independent of 2/3):
   - **Stream 6** — CI via `xcodebuild` (add a job that regenerates the seed and
     `xcodebuild -target TextMate` on a Homebrew runner). This is what actually
     exercises Stream 2's Homebrew default end-to-end.
   - **Stream 5** — API modernization (WebView→WKWebView, KVO). Note: the global
     `<WebKit/WebKit.h>` in `Shared/PCH/prelude.m` is what forced the option-4 farm
     workaround; Stream 5 may let that be simplified.
   - **Stream 6** — CI via `xcodebuild` (replace/augment the ninja `build.yml`).
   - **Stream 3** — code signing & notarization (needs real certs → likely a STOP
     point that needs the user).
   - Then **Phase 3** (Swift interop foundation) per `PROJECT_PHASES.md`.

## How to rebuild / verify Stream 1
```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 RUBYOPT="-EUTF-8"
ruby ide/extract_specs.rb > ide/gen/specs.json && ruby ide/seed_xcodeproj.rb
xcodebuild -project TextMate.xcodeproj -target TextMate -configuration Release build
# -> build/Release/TextMate.app  (codesign --verify --deep --strict passes)
```

## Guardrails (unchanged)
- Edit the **generator** (`ide/*.rb`), not the generated `TextMate.xcodeproj`.
- Commit green steps with the `Co-Authored-By: Claude Opus 4.8` trailer; **never
  push without asking**; no PRs; commit named paths, never `git add -A`.
- **Do NOT touch `bin/rave`** — it has a pre-existing local edit (shows as modified;
  unrelated to this work).
- Gitignored / regenerated, never commit: `TextMate.xcodeproj/`, `build/`,
  `ide/gen/`, `local.rave`.
- Stop and leave a note when a chunk fails twice after real fix attempts, a decision
  only the user can make is required, or credentials are needed (e.g. Stream 3).

## Working-tree notes at snapshot
- `bin/rave` shows modified (pre-existing; leave it).
- `PROJECT_PHASES.md` is untracked (the roadmap doc).
- Everything from this session is committed on the branch through `7de0a620`.
