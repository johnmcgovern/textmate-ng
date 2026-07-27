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
