Title: Re-enabling software update

# Re-enabling software update

Written 2026-09-06, immediately after porting the SoftwareUpdate framework to
Swift, so the code descriptions here are first-hand rather than remembered.

## Where things actually stand

**The updater works.** `SoftwareUpdate` and `OakDownloadManager` are Swift now,
pinned by `t_software_update.mm`, and the download/verify path they share with
`BundlesManager` runs in production every day — the bundle index is fetched from
`api.textmate.org` and signature-verified on a schedule. Nothing is broken.

What is missing is **ownership**, and only that:

    AppController.applicationWillFinishLaunching()
      // SoftwareUpdate.sharedInstance.channels is deliberately left unconfigured

`channels` is nil, so every check reports "No channel named 'release'." That was
a deliberate Phase 2.5 decision: the previous value resolved to MacroMates'
`api.textmate.org/releases`, which would have offered this fork's users *another
product's* builds.

**Signing and notarization are done and were done long before this note.**
Developer ID `John McGovern (R22V2H7QF4)`, secure timestamps, `bin/notarize`
driving `notarytool` and stapling, `bin/release` publishing to
<https://github.com/johnmcgovern/textmate-ng/releases> behind five checks —
Gatekeeper acceptance, version agreement across `Changes.md`/tag/Info.plist,
re-verification of the *unpacked zip*, and UUID-matched dSYMs. There is no
prerequisite infrastructure to build. **GitHub Releases is already the
distribution channel**, which is what makes it the natural update backend rather
than a new dependency.

## The four mismatches, measured

The updater was written against MacroMates' S3 bucket. Four things differ on
GitHub, all checked against live endpoints on 2026-09-06 rather than assumed:

| # | What the code requires | What GitHub does |
| --- | --- | --- |
| 1 | ~~`contentType == "application/json"` — **exact** string compare~~ **fixed, `7a06fffa`** | API, Pages *and* raw all return `application/json; charset=utf-8` or `text/plain; charset=utf-8` |
| 2 | signature in `x-amz-meta-x-signee` / `x-amz-meta-x-signature` **response headers** | release assets redirect to `release-assets.githubusercontent.com` (Azure blob) — no such headers, and no way to set them |
| 3 | archive unpacked with `tar -jxmkC` — a **bzip2 tar** | `bin/release` publishes a `ditto -c -k` **zip** |
| 4 | public key looked up in `Info.plist` `TMSigningKeys` | the only key there is `org.textmate.duff` — MacroMates', **DSA**, verified through **SecTransform** (deprecated macOS 12/13) |

(1) is a one-line fix and arguably a latent bug: a media type with parameters is
legal and should match on the type alone.

(2) is the real design question. The signature has to move into the manifest,
which means `OakDownloadManager` needs a path that takes an explicit signature
instead of reading headers — and that class is shared with `BundlesManager`, so
the header path has to stay. It is also the security-critical code in the app.

(3) is a choice: publish a second `.tbz` asset, or teach the updater to unpack a
zip. Publishing both is cheap and leaves the human-facing download alone.

(4) is the one worth thinking hardest about. See below.

## What the current code actually does, and where it is weak

Two things I confirmed by reading the ported code rather than assuming:

**`TMSigningKeys` is read in exactly one place** — `SUDownloadViewController.swift`,
the updater. `BundlesManager` does *not* use it: its keys (`org.textmate.duff`,
`org.textmate.msheets`) come from inside the downloaded bundle index. So the
Info.plist key serves the update channel alone, and changing it cannot affect
bundle installation.

**The archive is extracted before it is verified.** `-URLSession:dataTask:
didReceiveData:` streams each chunk straight into `tar`'s stdin as it arrives;
the signature is checked in `-didCompleteWithError:`, after the whole download.
The signature therefore gates *installation*, not *extraction* — `tar` has
already run on unverified bytes by the time anything is checked. That is
pre-existing, not something the Swift port introduced, and it is the single
biggest thing to fix here.

**The updater runs in a process anything can hook.** `Entitlements.plist` sets
`com.apple.security.cs.disable-library-validation` — necessarily, because
`TMPlugInController` loads third-party `.tmplugin` bundles into the TextMate
process via `Bundle.principalClass`. So the hardened runtime does not restrict
what code runs alongside the verifier. This is the concrete basis for Tier 2
below; it is not hypothetical. (`allow-dyld-environment-variables` is *not* set,
so `DYLD_INSERT_LIBRARIES` is still blocked; the door is plug-ins, not the
environment.) CI, for what it is worth, never holds a signing key — builds there
are ad-hoc, and `bin/notarize` runs on the release Mac.

## How Chrome does it, and what transfers

Worth looking at, because it is the most-attacked updater on the platform.
Chrome used Keystone on macOS; Google has now moved to **Omaha 4** (the
"Chromium Updater", in the Chromium tree), which is cross-platform and current on
macOS and Windows as of September 2026.

Its transport security is **CUP-ECDSA** (Client Update Protocol): ECDSA with
SHA-256, the *server's public key hardcoded in the client binary*, and the server
signs request/response **pairs** — returned in an `X-Cup-Server-Proof` header or
an `ETag`. The point is that authenticity does not depend on TLS: a hostile or
compromised CDN cannot substitute a response.

The payload is not signed separately. The **CUP-signed response carries the
payload's `hash_sha256`**, and integrity is verified during download, before
installation.

    <package name="…" hash_sha256="…" size="…" required="true"/>

Two things I could *not* confirm from the public specification and so will not
claim: whether the updater independently verifies macOS code signatures or
notarization, and what anti-rollback protection exists.

**The transferable idea is the shape, not the protocol.** Sign the *manifest*,
and pin the payload by hash inside it. That is strictly better than this
project's current design in two ways:

* it fixes the ordering problem for free — a SHA-256 can be checked on the
  complete downloaded bytes *before* they are handed to `tar`, whereas a
  signature arriving in a response header cannot be checked until the transfer
  is finished, by which point the streaming extractor has consumed it;
* the signature covers *what you should receive* (version, URL, hash), not just
  the bytes, so an attacker who controls the transport cannot serve an older
  signed release in place of a newer one.

Also worth taking from CUP: **TLS is not the security boundary.** GitHub is a CDN
you do not control. The manifest signature is what makes that acceptable.

## Threat model

The question that motivates all of this: *how does my code-signing identity get
burned?* Answering it properly means listing who the attacker is, because the
controls differ.

| Attacker | Can do | Stopped by |
| --- | --- | --- |
| **Network MITM** (hostile Wi-Fi, corporate proxy with a trusted root) | substitute the manifest or the archive | manifest signature; payload hash |
| **Hostile or compromised CDN** (GitHub, its Azure asset host, any redirect target) | same, plus **freeze** you on a stale-but-valid manifest so you never get a security fix | manifest signature; payload hash; manifest expiry |
| **Compromised GitHub account** | publish a release, rewrite a tag | cannot sign a manifest or codesign a bundle → updater rejects it. **This is the scenario the manifest signature exists for.** |
| **Rollback** | serve an older, validly-signed, vulnerable release | background checks never install below the running version |
| **In-process hook** — a malicious `.tmplugin`, which runs inside TextMate with library validation off | swizzle the verifier, replace the embedded key in memory, lie about the result | only a **separate verifying process** with library validation on. See below. |
| **Local same-user attacker** | replace the app bundle directly, no updater needed | nothing here — they already own the account. Out of scope, and any design claiming otherwise is wrong. |
| **Compromised release Mac** | sign anything | nothing in the updater. This is the machine to protect; see key hygiene. |

**The Developer ID private key is never touched by the updater.** It is used once,
at release time, by `bin/notarize` on the release Mac. Hooking the update process
cannot burn it. It gets burned by theft from that Mac, or by Apple revoking it
because malware was signed with it — and the updater's job is to make sure the
*only* thing carrying your signature that ever gets installed is something you
built.

## Recommended verification, in order

### Tier 1 — closes every remote vector. Do all of it.

1. **Manifest signature: ECDSA P-256, private key in the Secure Enclave of the
   release Mac.** Not Ed25519, and not a key file. The Secure Enclave only does
   P-256, and it makes the key **non-exportable**: signing a release requires
   physical presence at that Mac, and a stolen disk image contains nothing.
   Create with `SecKeyCreateRandomKey` + `kSecAttrTokenIDSecureEnclave`; clients
   verify with `SecKeyVerifySignature` and
   `kSecKeyAlgorithmECDSASignatureMessageX962SHA256`. This is what Ed25519-in-a-
   file cannot give you, and it is the modern, Apple-native answer to the
   "burned key" worry.
2. **Manifest contents**, signed as canonical bytes:
   `version`, `url`, `sha256`, `size`, `issued`, `expires`, `keyID`,
   `minimumSystemVersion`. Everything the client will act on is inside the
   signature; the URL is just where to fetch bytes that must hash correctly.
3. **Freshness.** Reject a manifest past `expires`. A CDN that can only replay
   what you signed can still replay it *forever*; expiry is what turns "stale"
   into "rejected". Re-sign on a schedule shorter than the expiry — `bin/release`
   already has the discipline for this.
4. **Anti-rollback.** A background check never installs a version below the
   running one. The existing user-initiated "Downgrade to X" stays; it is
   explicit and that is the difference.
5. **Hash before extraction.** Download to a file, verify `size` (a bound
   against decompression bombs), verify `sha256`, and only then run `tar`. This
   is the fix for the ordering weakness above, and it is the single most
   important code change in the whole plan.
6. **Code-signature check of the unpacked bundle**, before the swap:
   `SecStaticCodeCheckValidityWithErrors` with `kSecCSStrictValidate`, against a
   designated requirement of the form
   `anchor apple generic and identifier "com.j23software.TextMate-NG" and
   certificate leaf[subject.OU] = "R22V2H7QF4"` — with the new Team ID accepted
   as well for one release either side of the transition. Then confirm the
   bundle's `CFBundleShortVersionString` and identifier match the manifest, so a
   mismatched payload fails loudly. Do **not** instantiate `NSBundle` on it or
   load anything from it before this check passes; read `Info.plist` as a file.
7. **Two embedded public keys** — current and next — with the manifest naming
   which one signed it. Rotation is then a normal release; revocation is a
   release that drops a key. Users who never update are stranded either way,
   under every scheme ever built.
8. **HTTPS only, no certificate pinning.** Pinning GitHub's certificates is
   fragile and buys nothing the manifest signature does not already provide. This
   is precisely CUP's reasoning: TLS is transport, not trust.

### Tier 2 — closes the in-process hook. Do it if plug-ins keep you up at night.

Because library validation is off, a malicious `.tmplugin` runs inside TextMate
and can hook `OakDownloadManager` at will. Every Tier 1 check runs in that same
process and can be lied to.

9. **Do the fetch, verify and swap in a separate helper** — an XPC service or a
   bundled tool in the mould of `CommitWindowTool` — built **with library
   validation on** and **no plug-in loading**. The app shows UI and asks; the
   helper decides. This is Chrome's architecture, and this is the reason for it.
10. In that helper, **re-check the code signature at the moment of the swap**,
    from a directory the helper itself created (TOCTOU).

**Be honest about what Tier 2 buys.** A malicious plug-in already runs as the
user and can replace the app directly, so this does not protect the account. It
protects the *integrity of the update decision*: the updater cannot be turned
into a channel that installs something and then vouches for it. That is a real
property, and a bounded one.

### Key hygiene — the actual answer to "burned"

* **Developer ID key**: never in CI (true today — keep it so); ideally
  hardware-backed. The updater never uses it.
* **Update-signing key**: Secure Enclave, non-exportable, on the release Mac.
* **Separation is the point.** A GitHub account compromise cannot produce a
  valid manifest signature *or* a valid code signature; the updater rejects the
  release. The one machine whose compromise burns everything is the release Mac,
  and that is a much smaller thing to defend than "GitHub, Azure, every network
  a user is on, and every plug-in they install."

### What this does not do, stated plainly

It does not defend against a same-user local attacker, a compromised release Mac,
or Apple. No client-side design can. Anyone selling you one is selling you
something else.

## Two paths

### A. Finish the homegrown updater

Roughly a day or two of code plus a signing step in `bin/release`:

1. ~~relax the Content-Type match~~ — **done**, `7a06fffa`;
2. generate a P-256 key **in the Secure Enclave** of the release Mac; public
   key(s) into `TMSigningKeys` under a J23 signee, with a key ID;
3. teach `OakDownloadManager` a manifest-driven path — download to a file,
   check `size` and `sha256`, *then* extract — keeping the header path for
   `BundlesManager`, pinned both ways;
4. code-signature check of the unpacked bundle before the swap, plus the
   version/identifier consistency check;
5. `bin/release` gains: a `.tbz` asset and a signed manifest with `expires`,
   published at a stable URL;
6. anti-rollback in the background path; set `channels` in `AppController`;
7. *(Tier 2, optional)* move 3–4 into a library-validated helper.

### B. Adopt Sparkle 2

Sparkle does appcast-over-GitHub-releases with EdDSA signatures natively and has
had far more security review than anything written here will get. Its model is
essentially the recommendation above.

**Against:** it discards a Swift port finished the same week, adds a dependency
and its own UI, and duplicates release-pipeline work that already exists and is
carefully checked.

## Recommendation

**Path A**, with the verification order above. The calculus changed once
`bin/release` was on the table: the one thing that would have argued for Sparkle —
not having to build release and notarization infrastructure — is already built,
and Sparkle's actual security design is reproducible here in a few hundred lines
against APIs the app already links.

Ship it to one machine before anyone else. The first real test of an updater is a
build that updates itself.

## What no test can cover

Nothing touches `SoftwareUpdate.sharedInstance` at launch — both entry points are
user-initiated — so the update panel is unreachable from any automated run
(rule 64). It is on the pre-release smoke list for that reason. An update channel
makes that worse, not better: the install-and-relaunch path cannot be exercised
by a test at all, because its last act is to replace the running application.

## Sources

* [Client Update Protocol (CUP) — Chromium docs](https://chromium.googlesource.com/chromium/src.git/+/master/docs/updater/cup.md)
* [Chromium Updater functional specification](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/updater/functional_spec.md)
* [`components/client_update_protocol/ecdsa.h`](https://github.com/chromium/chromium/blob/master/components/client_update_protocol/ecdsa.h)

GitHub's response headers were measured directly on 2026-09-06 with `curl -sI`
against `api.github.com`, a `github.io` Pages host, `raw.githubusercontent.com`,
and a release asset download; see the table above.
