# Removing the dependency on api.textmate.org

Decided 2026-09-19. **The fork must not depend on MacroMates' servers, now or
later.** This is the plan for getting there, what it costs, and the one place
the current design cannot simply be re-pointed.

## What the dependency actually is

Two hosts, both live, neither ours:

| Host | What it serves | Reached from |
| --- | --- | --- |
| `api.textmate.org/bundles` | the bundle index **and every `.tbz` payload** | `REST_API` in `default.rave` and `ide/seed_xcodeproj.rb` |
| `archive.textmate.org` | a Ruby 1.8.7 build, x86_64 only | the `ruby18` shim inside Bundle Support |

The second is already solved by `bin/patch-bundles`, which replaces the shim
with one that uses the Ruby macOS ships and downloads nothing.

The first is the real work, and it is larger than changing a URL, for three
reasons found by reading the code rather than assuming:

1. **Bundles do not ship with the application.** `DefaultBundles.tbz` is 132
   bytes in every release, alpha.29 and alpha.30 included — `bl` cannot run
   during a Release build because signing it with a Developer ID gives it a
   hardened runtime, which then refuses to load Homebrew's `libcapnp`. The build
   treats that as a warning. Every bundle a user has arrived over the network
   from `api.textmate.org`, installed automatically the first time the index
   updated. So this is not a fallback path; it is the only path.
2. **Signatures arrive as S3 object metadata**, in `x-amz-meta-x-signee` and
   `x-amz-meta-x-signature`. MacroMates serves from S3. **GitHub cannot set
   custom response headers on raw files or release assets**, so the existing
   verification cannot work from a GitHub repo no matter where it is pointed.
3. **The trust anchor is theirs.** `BundlesManager.publicKeys` falls back to two
   hardcoded MacroMates DSA keys, `org.textmate.duff` and `org.textmate.msheets`.
   While those remain, a compromise of their infrastructure is a code-execution
   path into this fork's users, because a bundle command is arbitrary code.

## The design

The application already contains the answer. `ArchiveVerification` has two
cases, and the software updater has been using the second against GitHub
releases since alpha.24:

```swift
private enum ArchiveVerification {
    case headerSignature(publicKeys: [String: String])   // what bundles use — needs S3
    case digest(sha256: String, size: Int64)             // what updates use — needs nothing
}
```

So bundles move to `.digest`, and integrity comes from **one signed index that
carries a hash and size for every payload**, exactly as `release.json` already
does for the application itself. A dumb static host is then sufficient, which is
what makes GitHub viable.

- **Hosting**: a GitHub repository, per the decision of 2026-09-19. Payloads as
  release assets, the index as an asset beside them. The default set is 4.7 MB
  across 33 bundles; all 255 would be 26.5 MB.
- **Trust**: the index is signed inline with the existing ECDSA key through
  `bin/update-sign`, the same key and tool that already sign `release.json`. No
  new key, no new ceremony, and no DSA.
- **Payload provenance**: built from each bundle's own GitHub repository pinned
  to a commit SHA, not copied from `api.textmate.org`. The index records the
  repository and SHA, so what a user installs is auditable back to a commit.
- **Patches**: `bin/patch-bundles` runs while the payload is being built. This is
  also the answer to a problem that had no good home — patches applied at build
  time went into an archive nobody unpacks, and patches applied on the user's
  machine would fight the bundle updater. Applied at mirror time they are simply
  part of what we serve.

## The steps

1. ~~`bin/mirror-bundles`~~ **Done 2026-09-19.** 33 bundles from their own
   repositories at pinned commits, patched, byte-reproducible across runs.
2. ~~Sign and publish.~~ **Done 2026-09-20.** `bin/publish-bundles` signs the
   index with `j23-2026`, the key that already signs release.json, and uploads
   34 assets to the `bundles` release. Verified from outside: the published
   signature checks out with openssl against the public key, and a downloaded
   payload matches the digest in the signed index.
   `https://github.com/johnmcgovern/textmate-ng/releases/download/bundles/bundles.json`
3. Application, and this is the one that has to be **atomic**: point `REST_API`
   at the new index, switch bundle downloads from `.headerSignature` to
   `.digest`, and delete the two hardcoded MacroMates keys — in a single commit.
   Deleting those keys while `REST_API` still points at api.textmate.org would
   make every bundle install fail signature verification, and the error a user
   sees would look like a network fault.
4. Ship it, and verify on a machine with no bundles installed.
5. Fix `bl` in Release builds so `DefaultBundles.tbz` stops being empty, which
   makes a first run work with no network at all. Independent of the above and
   worth doing on its own.

Steps 1 and 2 changed nothing for any user: the release exists and nothing reads
it. The dependency is not removed until step 3 ships.

## What this does not fix

Bundle content is still other people's open-source work, and mirroring does not
make it ours to vouch for. What changes is that a user installs a specific
audited commit from a host we control, instead of whatever a third party serves
today under a key we do not hold.
