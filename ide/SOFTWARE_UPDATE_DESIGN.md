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

## Recommended verification, in order

1. **Manifest signature** — Ed25519 or ECDSA P-256, public key in `Info.plist`
   under a J23 signee, verified with `SecKeyVerifySignature`. Not DSA-1024, and
   not `SecTransform`, which Apple deprecated in macOS 12/13. The existing DSA
   path was ported verbatim on purpose and stays for the bundle index; nothing
   new should be built on it.
2. **Payload hash** — SHA-256 from the signed manifest, checked against the
   downloaded bytes **before extraction**. This is the ordering fix.
3. **Code signature of the unpacked bundle** — `SecStaticCodeCheckValidity`
   against a Developer ID requirement, before the bundle is swapped in. This is
   what stops the updater installing something Gatekeeper will then refuse to
   run.

Steps 1 and 3 answer different questions and both are worth having. (1) is "did
J23 publish this?"; (3) is "will this actually launch?".

### On the Team ID, and a correction

An earlier draft of this note said "do not key the update channel to the Team ID",
and then a later suggestion — verify by code signature alone and skip the custom
key — would have done exactly that. Both halves cannot be right.

The resolution is that they are different checks. **Step 1 must not depend on the
Team ID**: the update-signing key is independent of the Developer ID, and that
independence is what lets a build signed under `R22V2H7QF4` verify and install a
build signed under a future J23 organisation Team ID. **Step 3 necessarily does**
depend on it, and so its requirement must accept the old *or* the new identity for
at least one release either side of the transition. A user who skips that window
is otherwise stranded on an old build that refuses every update.

Verifying by code signature *alone* — no manifest key — is the option to reject,
for that reason.

## Two paths

### A. Finish the homegrown updater

Roughly a day or two of code plus a signing step in `bin/release`:

1. ~~relax the Content-Type match~~ — **done**, `7a06fffa`;
2. generate an Ed25519 keypair; public key into `TMSigningKeys` under a J23
   signee; verification via `SecKeyVerifySignature`;
3. teach `OakDownloadManager` a manifest-driven path: explicit signature and an
   expected SHA-256, checked before extraction — keeping the header path for
   `BundlesManager`, pinned both ways;
4. add the code-signature check before the bundle swap;
5. `bin/release` gains: a `.tbz` asset, a signed manifest with the hash,
   published at a stable URL;
6. set `channels` in `AppController`.

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
