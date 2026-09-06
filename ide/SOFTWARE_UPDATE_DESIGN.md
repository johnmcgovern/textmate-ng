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
| 1 | `contentType == "application/json"` — **exact** string compare | API, Pages *and* raw all return `application/json; charset=utf-8` or `text/plain; charset=utf-8` |
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

## Do not rebuild on DSA-1024 and SecTransform

The existing scheme is a ~1024-bit DSA key verified with `SecVerifyTransformCreate`,
which Apple deprecated in macOS 12/13. It was ported **verbatim** and on purpose —
changing signature verification during a translation is a security change wearing
a translation's clothes — but that reasoning does not extend to *building a new
channel on it*.

A new J23 key has to be generated regardless. That is the moment to move to
**Ed25519 via `SecKeyVerifySignature`**, which also retires the deprecated API.

One property worth noticing, because it is load-bearing for the Team ID question
below: **the update-signing key is independent of the codesigning identity.** They
answer different questions — "did J23 publish this?" versus "will Gatekeeper run
it?" — so a change of Developer ID does not invalidate an update channel, provided
the update key persists.

## The Team ID change

Enrollment is individual (`R22V2H7QF4`); a move to a J23 organisation Team ID has
been anticipated for a while. For an updater this is mostly benign — the whole
bundle is replaced, so there is no partial-signature state — but two things follow:

* Old builds must be able to verify *new* ones. They can, because the update key
  is independent of the Developer ID (above). Do not key the update channel to the
  Team ID.
* Anything scoped to a Team ID (keychain access groups, app groups) would not
  survive. Worth a grep before the change, not before the updater.

## Two paths

### A. Finish the homegrown updater

Roughly a day or two of code, plus a signing step in `bin/release`:

1. relax the Content-Type match to compare the media type only, with a pin;
2. add an explicit-signature path to `OakDownloadManager`, keeping the header path
   for `BundlesManager`, pinned both ways;
3. generate an Ed25519 keypair; public key into `TMSigningKeys` under a J23
   signee; move verification to `SecKeyVerifySignature`;
4. `bin/release` gains: publish a `.tbz` asset, sign it, and write a manifest
   (`{url, version, signee, signature}`) — published to GitHub Pages, or as a
   release asset with a stable "latest" URL;
5. set `channels` in `AppController`.

**For:** the UI is already built, ported, and tested; `bin/release` already has
the verification discipline this needs; no new dependency; the panel matches the
rest of the app.

**Against:** it is a bespoke code-execution channel maintained by one person.

### B. Adopt Sparkle 2

Sparkle does appcast-over-GitHub-releases with EdDSA signatures natively, and has
had far more security review than anything written here will get.

**For:** the security-critical part stops being ours.

**Against:** it discards a Swift port finished the same week, adds a dependency
and its own UI, and duplicates release-pipeline work that already exists and is
carefully checked. The case was stronger when I believed there was no release
pipeline; there is one, and it is good.

## Recommendation

**Path A**, and the calculus genuinely changed once `bin/release` was on the
table. The remaining work is small, the pieces it touches are freshly ported and
pinned, and the one thing that would have argued for Sparkle — not having to
build release/notarization infrastructure — is already built.

Sequence, each step shippable on its own:

1. Content-Type fix + pin. Correct regardless of path.
2. Ed25519 verification alongside the existing DSA path, with the DSA path kept
   for `BundlesManager`'s MacroMates-signed bundle index. Pin both.
3. Explicit-signature download path + pin.
4. `bin/release`: `.tbz` asset, signature, manifest. Dry-run first — it has a
   `--dry-run` already.
5. Wire `channels`. Ship it to one machine before anyone else.

**Do not skip the last part.** The first real test of an updater is a build that
updates itself, and the failure mode is an app that no longer launches.

## What no test can cover

Nothing touches `SoftwareUpdate.sharedInstance` at launch — both entry points are
user-initiated — so the update panel is unreachable from any automated run
(rule 64). It is on the pre-release smoke list for that reason. An update channel
makes that worse, not better: the install-and-relaunch path cannot be exercised
by a test at all, because its last act is to replace the running application.
