# Notarization + public distribution — handoff notes

Carried over from a session accidentally run in `notion-automation`. Untracked and disposable —
delete once the content lands somewhere permanent.

Goal: **someone visits a GitHub page, downloads the latest build, drags it into /Applications.**

---

## 1. Licensing is already settled — and it forces the distribution path

This project is **GPLv3** (`LICENSE`, `COPYING`). Consequences:

- **Developer ID + notarization + DMG: fine.** No conflict. Apple does not require you to own the
  code, only to sign it with a valid Developer ID.
- **Mac App Store: effectively closed.** GPLv3's anti-tivoization and "no additional restrictions"
  terms conflict with the App Store's DRM and licence agreement (the VLC precedent). Not a blocker
  here — direct download *is* the goal — but it means notarization is **mandatory, not optional**.
  There is no second channel to fall back on.
- Distributing a branded GPLv3 build under **J23 Software** is allowed. Obligations: keep it GPLv3,
  offer corresponding source, preserve notices. The *TextMate name/icon* is a separate trademark
  question from the licence — worth a decision before a public launch.

## 2. Start Apple Developer enrollment NOW — it is the only item with calendar cost

Everything else here is work you control. This one is a queue you wait in.

| | Individual | Organization (J23 Software) |
|---|---|---|
| Lead time | Often same day | **1–4 weeks** |
| Needs | Apple ID + payment | Legal entity, **D-U-N-S number**, live company website, authority to bind |
| Cert reads | `John McGovern` | `J23 Software` |

**The trap:** the Team ID is baked into every signed binary. Ship v1 personally and move to
J23 Software later and macOS treats it as a *different developer* — new Team ID, and users who
already allowed the old one get re-prompted.

D-U-N-S is free from Dun & Bradstreet but commonly takes ~5 business days. `j23software.com` being
live and matching the entity name helps Apple's verification — they check the site.

**Do this in parallel with the build, not after it.**

## 2a. Verified findings (2026-07-26, empirical — not estimates)

Run against `build/Release/TextMate.app`, re-signed by hand in a scratch copy. All four
results were *tested*, not reasoned about.

**① Hardened Runtime already works. ✅ — and is now enabled in the build.** Originally
proven by re-signing a scratch copy inside-out with `--options runtime` and the existing
`ide/gen/entitlements/TextMate.plist`: signature valid (`flags=0x10002(adhoc,runtime)`),
app launches, both `.tmplugin`s load. The usual notarization landmine is a non-issue here.

> **Correction (2026-07-29).** This item used to end "*but it is not enabled in the
> build*: `ENABLE_HARDENED_RUNTIME` appears nowhere in `ide/seed_xcodeproj.rb`. One
> setting to add." That is stale — the setting landed in `f9fddd71` ("Stream 3: make the
> app self-contained and Hardened-Runtime ready") and is now scoped to Release
> (`ide/seed_xcodeproj.rb`, `bs["ENABLE_HARDENED_RUNTIME"] = config.name == "Release" ?
> "YES" : "NO"`), with the embed-dylibs phase honouring it when it re-signs. Debug stays
> off deliberately so lldb/Instruments behave normally. Verified on the current Release
> binary, not from the setting: `codesign -dv` reports `flags=0x10002(adhoc,runtime)`.
> **There is nothing left to do for this item.**

**② 🚨 The app links the builder's Homebrew prefix — this is the real distribution
blocker.** Four binaries carry absolute load commands into `/opt/homebrew`:

| Binary | Links |
|---|---|
| `Contents/MacOS/TextMate` | `libcapnp.1.5.0.dylib`, `libkj.1.5.0.dylib` |
| `Contents/MacOS/mate` | same |
| `Contents/MacOS/tm_query` | same |
| `Contents/Library/QuickLook/TextMateQL.qlgenerator/…/TextMateQL` | same |

On any Mac without capnp installed at that exact path, the app dies at launch with
`dyld: Library not loaded`. It would notarize fine and still be unusable — notarization
does not check this. Boost/sparsehash are header-only and Onigmo is static, so capnp/kj
are the *only* two.

**FIXED in the build (2026-07-26).** `ide/seed_xcodeproj.rb` now adds an *Embed
dependency dylibs* run-script phase to the app target, running last (after every copy
phase). It scans the built bundle for Mach-O binaries, transitively vendors any dylib
under `DEP_PREFIXES` into `Contents/Frameworks/`, rewrites ids and references to
`@rpath`, adds a correctly-computed `@loader_path/…/Frameworks` rpath, and re-signs what
it touched. It scans rather than hard-codes capnp/kj so a future dylib dependency cannot
silently reintroduce the bug. The phase fails the build if any external reference
survives.

Verified on a real Release build: `Contents/Frameworks/` holds the two dylibs, **0**
`/opt/homebrew` references remain, `codesign --verify --deep --strict` passes, the app
launches with both plug-ins loaded, capnp mapped from inside the bundle, and `mate` /
`tm_query` both run.

**③ `disable-library-validation` is genuinely required — do not drop it.**
`TMPlugInController.mm:126-128` loads `.tmplugin` bundles from
`~/Library/Application Support/TextMate/PlugIns` (all domains), i.e. **third-party code
signed by other developers**. Library validation would reject exactly those. Dropping the
entitlement removes the plugin architecture. The other three entitlements should still be
re-audited once a real cert exists.

**④ The "fewest entitlements" test can't be finished ad-hoc.** Library validation compares
*Team IDs*, and ad-hoc signatures have none — so an ad-hoc build can never satisfy it
(this is what makes ① pass only with the entitlement present). Re-run the audit once a
Developer ID cert is in the keychain.

**⑤ Hardened Runtime breaks the bundled CLI tools unless they are given the same
entitlement.** Caught only by running them. With `ENABLE_HARDENED_RUNTIME=YES`, library
validation applies to `mate`/`tm_query` too, and they load the embedded `libcapnp` — which
under an ad-hoc signature has no matching Team ID, so `dyld` refuses it. The app itself was
unaffected (it already carries `disable-library-validation`), so this fails *silently in
the GUI* and only shows up on the command line. Fixed by signing the nested executables
with a generated `ide/gen/entitlements/NestedTool.plist` carrying just
`disable-library-validation`. Note the app keeps its own full entitlement set: Xcode's
CodeSign step runs after this phase and supersedes the nested signature on
`Contents/MacOS/TextMate` — verified with `codesign -d --entitlements`.

**Signing inventory — 9 Mach-O objects, inside-out order:**
`Frameworks/libkj` → `Frameworks/libcapnp` → `Dialog.tmplugin/…/tm_dialog` →
`Dialog2.tmplugin/…/tm_dialog2` → `Dialog.tmplugin` → `Dialog2.tmplugin` →
`TextMateQL.qlgenerator` → `Resources/PrivilegedTool` → `MacOS/mate` → `MacOS/tm_query`
→ outer `.app` (entitlements only on the outer app).

Note `PrivilegedTool` sits in `Resources/`, not `MacOS/`, and `tm_dialog`/`tm_dialog2` are
Mach-O binaries inside plugin `Resources/`. Signable, but `--deep` will not do the right
thing — sign each explicitly.

**Not a notarization blocker, but flagged:** `PrivilegedTool` is invoked via
`AuthorizationExecuteWithPrivileges` (`Shared/include/oak/compat.h:19`, called from
`Frameworks/authorization/src/server.cc:26` and `Preferences/TerminalPreferences.mm:50`)
and does `setuid(geteuid())`. Deprecated since 10.7. Notarization checks signatures, not
API usage, so this passes — but it is the modern `SMAppService`/`SMJobBless` rewrite
waiting to happen.

## 2b. Bundle identifier moved to `com.j23software.*` (2026-07-26)

Done deliberately *before* the first public build: the move orphans prefs and saved
window state, and deferring it to the eventual individual→J23 Team ID migration would
have broken users twice. Bundle ID is independent of Team ID, so it did not need to wait
for enrollment. Verified: app builds, launches, and now writes
`~/Library/Preferences/com.j23software.TextMate.plist` and
`~/Library/Caches/com.j23software.TextMate/`. **311 tests green.**

**Renamed** — things that name *this app*: the three `CFBundleIdentifier`s (TextMate,
QuickLookGenerator, SyntaxMate) and `PRODUCT_BUNDLE_IDENTIFIER`; the bundles-index cache
path (writer `BundlesManager.mm` **plus** both readers, `gtm.cc` and the QuickLook
generator — they hardcode the same literal and silently break if moved apart); `mate`'s
`URLForApplicationWithBundleIdentifier:` lookup (would otherwise have launched *real*
TextMate); the QuickLook generator's `NSUserDefaults` suite name; the encoding and
updater cache paths; Touch Bar item identifiers; the tab-drag pasteboard type; the
`OakCommand`/`SyntaxMate` error domains; the commit-window port name; the `os_log`
subsystem.

**Renamed, and more than cosmetic:** `Frameworks/authorization/src/constants.h`. Those
constants name a **system-wide** LaunchDaemon, a helper in `/Library/PrivilegedHelperTools`,
a `/var/run` socket and an Authorization right. Shipping publicly under MacroMates' names
would have had TextMate-NG and a real TextMate install overwrite each other's daemon and
contend for one socket. ⚠️ Machines that already installed the old helper keep an orphaned
`com.macromates.auth_server` daemon and plist — nothing removes it, so this needs an
uninstall note (and the helper is separately due an `SMAppService` rewrite).

**Deliberately NOT renamed** — these name *data and formats*, not the app:

- **The 38 `com.macromates.textmate.*` UTIs** in `Info.plist`. They identify the tmbundle
  ecosystem's on-disk formats (`.tmbundle`, `.tmTheme`, `.tmLanguage`, `.tmSnippet`…),
  which VS Code, Sublime and Linguist also consume. Renaming would fork the format
  identity and break Finder association with every existing file. Most sit under
  `UTImportedTypeDeclarations` — renaming a type you merely *import* is simply wrong.
- **The `com.macromates.*` extended attributes** in `OakDocument.mm` (`bookmarks`,
  `selectionRange`, `crc32`, `folded`, `visibleIndex`, `backup.*`). These are written onto
  **the user's own files**. Keeping them is a feature: someone migrating from TextMate
  keeps their per-file bookmarks, selection and folds.
- **Submodule internals** (`PlugIns/dialog`, `dialog-1.x`): the plug-in bundle ids
  `com.macromates.plugin.*` and the Dialog IPC port names. Both sides of each IPC pair
  live in the submodule, so they stay consistent; nested bundle ids need no relation to
  the host app's. Changing them means forking the submodules — worth doing eventually for
  brand coherence, but it breaks nothing today.
- **`Changes.md`** — historical changelog; the `defaults write com.macromates.TextMate …`
  lines are a record of past releases, not live instructions.

## 2c. Deploy target vs. Homebrew bottle SDK — investigated, NOT a blocker (2026-07-27)

Surfaced by CI: the build emits **46** linker warnings of the form

```
ld: warning: building for macOS-15.0, but linking with dylib
'/opt/homebrew/opt/capnp/lib/libcapnp.1.5.0.dylib' which was built for newer version 26.0
```

`DEPLOY_TGT` is 15.0; Homebrew's capnp bottle is built for macOS 26 (`minos 26.0`,
`sdk 26.4`). 23 targets × the 2 dylibs — 5 shipped (`TextMate`, `mate`, `tm_query`,
`TextMateQL`, `bl`) and 18 test bundles. The two vendored copies in
`Contents/Frameworks/` carry `minos 26.0`; all 9 TextMate-built Mach-Os carry 15.0, and
`LSMinimumSystemVersion` is 15.0.

This looks like §2a finding ② — an app that notarizes cleanly and dies on a user's Mac.
**It is not.** Two independent tests, both negative:

**① `dyld` does not enforce `minos`.** A dylib was forged to `minos 99.0` with
`vtool -set-build-version macos 99.0 99.0`, re-signed ad-hoc, and loaded on macOS 26.5.2
— the same "dylib newer than the OS" relationship a `minos 26.0` dylib has on macOS 15.
It produced the *identical* linker warning and then **loaded and ran**. Tested on both
paths: `dlopen`, and launch-time `LC_LOAD_DYLIB` resolution via a linked executable.
There is no dyld refusal here. (The prior assumption — that `minos` is a hard gate — is
wrong; that is why this was tested rather than reasoned about.)

**② The dylibs need nothing macOS 15 lacks.** `libcapnp`/`libkj` link only
`libSystem.B.dylib` and `libc++.1.dylib`. Of 215 imported symbols, 1,179 are provided by
the capnp/kj pair itself, leaving **126 that must come from the system — all 126 present
in `MacOSX15.sdk`. Zero missing.**

```sh
FW=build/Release/TextMate.app/Contents/Frameworks
SDK15=/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk
nm -u $FW/libcapnp.1.5.0.dylib $FW/libkj.1.5.0.dylib | sed 's/^ *//' \
  | grep '^_' | sort -u > needed.txt
nm -g --defined-only $FW/libcapnp.1.5.0.dylib $FW/libkj.1.5.0.dylib \
  | awk '{print $NF}' | grep '^_' | sort -u > selfprovided.txt
find $SDK15/usr/lib -name '*.tbd' | xargs cat \
  | grep -oE "'[^']+'|\"[^\"]+\"|_[A-Za-z0-9_$.]+" | tr -d "'\"" \
  | grep '^_' | sort -u > sdk15.txt
comm -23 needed.txt selfprovided.txt | comm -23 - sdk15.txt   # -> empty
```

The `.tbd` harvest is a deliberately crude grep, so it was validated against a false
negative: harvesting `MacOSX26.5.sdk` the same way yields 191,340 symbols vs 156,243 for
15, and the 41,498-symbol difference correctly reports as absent from the 15 set. The
method discriminates; the zero is real.

**Conclusion: the 46 warnings are advisory noise, not a shipped-breakage signal.** No
action needed for notarization. Silencing them would mean building capnp from source
against the 15.0 SDK — not worth it.

**⚠️ Re-check trigger.** This result is specific to the **capnp 1.5.0 bottle as it exists
today**, and `brew install capnp` in `.github/workflows/build.yml` is *not* version-pinned
— it takes whatever is current (only the `xcodeproj` gem is pinned, at 1.28.1). A future
bottle could import a symbol that macOS 15 lacks and this analysis would silently go
stale. Re-run the snippet above after any capnp major/minor bump, or pin the formula.

**Not proven:** symbol availability is not behavioural equivalence, and none of this is a
substitute for launching on a real macOS 15 machine. For a hard guarantee rather than
strong evidence, that is a VM run — everything short of it points the same way.

## 3. Notarization process (Xcode project — the normal path)

1. **Developer ID Application** certificate (and Developer ID Installer if a `.pkg` is ever wanted).
2. **Build + archive.** Enable **Hardened Runtime**. Audit entitlements — a text editor with
   plugins, a shell/`mate` binary, and bundled frameworks will likely need some combination of
   `com.apple.security.cs.allow-unsigned-executable-memory`, `disable-library-validation`, or
   `allow-jit`. Grant the fewest that work; each one weakens the runtime.
3. **Sign inside-out, with a secure timestamp.** `PlugIns/`, `Frameworks/`, then helper tools, then
   the outer `.app`. `codesign --deep` is *not* reliable for this — sign nested code explicitly.
   Any bundled binary signed by someone else must be re-signed or removed.
4. **Submit:** `xcrun notarytool submit App.zip --keychain-profile <profile> --wait`
   (store creds once via `notarytool store-credentials`; use an App Store Connect **API key** for
   CI rather than an app-specific password).
5. **Staple:** `xcrun stapler staple App.app` — lets Gatekeeper validate offline.
6. **Verify:** `spctl -a -vvv -t install App.app` and `codesign --verify --deep --strict`.

On rejection, `notarytool log <submission-id>` gives the per-file reason. First attempts almost
always fail on an unsigned nested binary or a missing timestamp — budget for a few rounds.

Note: staple the `.app`, then build the DMG **from the stapled app**, then notarize and staple the
DMG too. Both layers should carry a ticket.

## 4. The "little folder" (DMG with Applications shortcut) — cheap

Exactly what it sounds like, and a solved problem:

```bash
brew install create-dmg
```

One invocation with `--volicon`, `--background`, `--icon-size`, `--app-drop-link 380 200` and a
couple of `--icon` positions produces the drag-to-Applications window. A "Project Home" item is
just a `.webloc` file dropped into the staging folder before packaging.

**~2–4 hours, mostly designing the background art.** It is entirely downstream of a signed `.app` —
the DMG is only a container.

## 5. Release automation

GitHub Actions on a `macos-*` runner, triggered by a `v*` tag:
import the cert from a base64 `.p12` secret into a temporary keychain → build → sign → notarize with
an App Store Connect API key → staple → `create-dmg` → attach the DMG + a `SHA256SUMS` to the
release. **~1 day** to get green the first time.

Secrets needed: `.p12` (base64) + its password, API key id / issuer id / `.p8`, and the Team ID.

## 6. Rough effort

| Piece | Effort |
|---|---|
| Apple org enrollment | ~0 work, **1–4 weeks waiting** ← start first |
| Signing + notarization working locally | ~1 day, plus entitlement iteration |
| GitHub Actions release pipeline | ~1 day |
| DMG with Applications shortcut | 2–4 hours |
| Trademark/branding decision | your call |

## 7. Open questions

- Individual or J23 Software as the signing identity? (Decide **before** the first public build.)
- Does it ship as "TextMate"-anything, or under a distinct J23 Software name?
- Is `johnmcgovern/textmate-ng` going public as-is, or does a `j23software` org own the release repo?
- Sparkle (or similar) for in-app updates? Affects entitlements and signing — cheaper to design in
  now than to retrofit.
