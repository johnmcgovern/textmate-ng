# Software update — the execution plan

_Written 2026-09-06, immediately after porting the SoftwareUpdate framework to
Swift and writing `ide/SOFTWARE_UPDATE_DESIGN.md`. This is the design turned into
commits. Everything here about the current code was read from it that day, not
remembered; everything about GitHub was measured with `curl`. Where it says
"probe", nobody has checked yet, and you should before building on it._

**Read first, in this order:**

1. `ide/RULES.md` — all 64. Rules 8, 18, 40, 54, 55, 59, 62, 64 are load-bearing
   for this work specifically.
2. `ide/SOFTWARE_UPDATE_DESIGN.md` — the *why*. This file is the *how*. Do not
   re-derive the threat model; if you disagree with it, change the design note
   first and say so in the commit.
3. The two Swift files you will be changing: `Frameworks/SoftwareUpdate/src/
   OakDownloadManager.swift` and `SoftwareUpdate.swift`, and their pins in
   `Frameworks/SoftwareUpdate/tests/t_software_update.mm`.

## Standing rules, restated so they are in the same file as the work

- **Pin → extract → translate**, one commit each. Here there is no translate
  step — it is already Swift — so it is **pin → change**, and the pin still goes
  in first, written against the code as it is, with a mutation check that fails
  it (rule 40). Pins have caught a real defect on most of the files they were
  written for; write them expecting to find one.
- **Rule 8**: exercise every change in the running app, not just the suite.
  Where that is impossible, say so in the commit and put the surface on the
  smoke list in `ide/NEXT_SESSION_HANDOFF.md`. This plan has one step that is
  *structurally* impossible to test automatically — the self-replacing install —
  and it is marked.
- **Rule 54, all three greps** on every full suite run:
  `grep -c "Restarting after unexpected exit"`, `grep -c "Fatal error:"`, and
  started-vs-passed. A crashed test process reports zero failures.
- **Re-seed after every test-file or spec change**:
  `ruby ide/extract_specs.rb > ide/gen/specs.json && ruby ide/seed_xcodeproj.rb`.
- The remote is **`GH-johnmcgovern`**, not `origin`. Stage explicit paths.
  Re-check `HEAD` before committing. **Do not push while CI is running on the
  previous push** — the workflow cancels in-progress runs.
- **Check CI** (`gh run list -L 1`) after every push.
- **Do not improve things during a security change.** The temptation here is
  real: the code is fresh Swift and easy to tidy. Every commit in this plan
  changes one property and pins it. Tidying goes in its own commit or not at all.

## Where this starts

| step | state | commit |
| --- | --- | --- |
| Content-Type media-type match | **done** | `7a06fffa` |
| SoftwareUpdate framework in Swift, pinned | **done** | `bfa64512`…`999a1795` |
| design note + threat model | **done** | `0a568adf`, `44dcf12e` |
| everything below | not started | |

Suite is **1015/1015** at `44dcf12e`. `bin/notarize` and `bin/release` exist and
work; the app is Developer ID-signed (`R22V2H7QF4`), notarized and stapled;
releases are published to GitHub Releases as a `ditto` zip plus a dSYM zip.
Bundle identifier is `com.j23software.TextMate-NG`.

## What only John can do

Three things. Everything else in this plan can proceed around them, and the
plan says at each step what to do while waiting.

- **J1. DONE 2026-09-08.** Key `j23-update-signing` created on the release Mac
  with the tool below; its public half is in `Info.plist` under
  `TMUpdateManifestKeys` as `j23-2026`, and pinned by
  `test_the_shipped_info_plist_carries_a_usable_signing_key`. The private key is
  a software key in the login keychain — see step 2 for what that does and does
  not protect. For reference, the command was:

        TM_CODE_SIGN_IDENTITY="Developer ID Application: John McGovern (R22V2H7QF4)" \
            bin/update-sign create-key

  It prints the public key; that string goes into `Info.plist` under
  `TMSigningKeys`. **Option 1 was chosen** (2026-09-08) — a software key in the
  login keychain, with the storage seam in place to move to the Enclave or a
  token later. See step 2 for what that does and does not protect, and why the
  move is always a key rotation rather than a migration.
- **J2. Decide Tier 2** (the separate verifying helper, step 7). The design note
  is honest that it protects the update *decision*, not the account. It is
  real work and a real property; it is a judgement call.
- **J3. The first self-update, on one machine, before anyone else.** Step 8. The
  install path replaces the running application and cannot be tested by a test.

## The steps

Each step is one commit unless it says otherwise. Each has: what changes, what is
pinned, how the pin is mutation-checked, how rule 8 is satisfied, and what "done"
means.

### Step 1 — hash-before-extract (the ordering fix)

**Why first.** It is the single most important security change in the plan, it
is independent of every design decision still open (key type, hosting, Tier 2),
and it is a strict improvement even if nothing else here ever ships.

**What.** `OakDownloadArchiveTask` (private, in `OakDownloadManager.swift`) today
streams each `didReceive data:` chunk into `tar`'s stdin and verifies the
signature in `didCompleteWithError:`. Change it to:

1. write the download to a temporary **file** (in the same `NSItemReplacement-
   Directory` it already creates), accumulating nothing in memory beyond what
   `NSProgress` needs;
2. on completion, verify — signature today, hash once step 4 lands — against the
   **complete file**;
3. only then launch `tar` with that file as stdin, wait for it, and proceed as
   before.

Keep the `NSProgress` estimation code exactly as it is; it reads
`countOfBytesReceived` from the task, not from the pipe.

**Behaviour that must not change**, and is pinned: the completion handler's
contract (URL on success, error otherwise), the error strings, the retry-on-next-
chunk oddity described in the file's comment (it becomes moot once nothing is
extracted mid-download, but do not *remove* the comment — replace it with one
saying why it is moot), and the `deinit` cleanup of `temporaryFileURL`.

**Pin (before the change).** `t_software_update.mm` cannot drive a real download.
Pin the *ordering* through the seam that exists: extract
`OakDownloadArchiveTask`'s "extract this verified file into this directory" into
an internal function on `OakDownloadManager` —
`func extractArchive(at fileURL: URL, into directory: URL) throws` — declared in
`SoftwareUpdateTesting.h` under `(Testing)`, and pin it with a real `.tbz` built
in the test with `tar -cjf` from a temp dir. Then pin that
**a file whose hash does not match is never extracted**: this needs step 4's
expected-hash parameter, so in this step pin the extraction function alone and
add the ordering pin in step 4. Say so in the commit.

**Mutation.** Make `extractArchive` a no-op; the extraction pin must fail.

**Rule 8.** `BundlesManager` uses the *file* download path, not the archive path,
so the bundle-index check does not exercise this. Installing a bundle from
Preferences ▸ Bundles does — it calls `downloadArchiveAtURL:`. If the
environment can open Preferences, install one small bundle and check the log. If
it cannot, say so and rely on the pin.

**Done when**: suite green with the three greps; the file's top comment says
the archive is now verified before extraction and why that matters (link the
design note).

### Step 2 — the signing tool, and the key

**The probe is done, and it changed this step. Read the results before planning
around them.** Measured 2026-09-08 on the release Mac (Apple Silicon, so a Secure
Enclave is present), with a throwaway label, key deleted after each run.

| # | Configuration | Result |
| --- | --- | --- |
| A | Secure Enclave, ad-hoc signed CLI | `-34018` errSecMissingEntitlement — "failed to add key to keychain" |
| B | Secure Enclave, **Developer ID** signed CLI, no entitlements | same `-34018` |
| C | Secure Enclave, Developer ID + `keychain-access-groups` entitlement | **process SIGKILLed at launch** (exit 137). The entitlement is in the signature; it is restricted, and without a provisioning profile authorising it the kernel refuses to run the binary. |
| D | Secure Enclave + `kSecUseDataProtectionKeychain` | same `-34018` |
| E | Software P-256, permanent, `kSecAttrIsExtractable = false` | creates, signs, verifies — **and is fully exportable anyway** |

**So the Secure Enclave is not available to a command-line tool.** It needs a
provisioning profile authorising a keychain access group, which a CLI signed with
a bare Developer ID cannot have.

**And the fallback does not give what the fallback was for.** `isExtractable:
false` prevented nothing: `SecKeyCopyExternalRepresentation` returned the private
key as 97 bytes from the freshly-created reference *and* from the reference
fetched back out of the keychain, and `SecItemExport` returned 121 bytes. The
attribute governs some export paths and not the ones that matter here. A software
keychain key is a key on the disk of the release Mac, and calling it
"non-exportable" would be false.

The design note's claim that the key is non-exportable therefore **does not hold
for any option currently on the table**, and has been corrected there.

#### The decision, taken 2026-09-08

**Option 1**, with the seam. The tool is built and its self-test passes; creating
the real key is one command (see "What only John can do"). The three options
were:

1. **Software key on the release Mac.** Simplest; the tool below works today.
   Protection is FileVault, the login keychain, and physical control of the
   machine — not the key's own properties. Describe it that way, in the note and
   in `bin/release`'s output.
2. **Secure Enclave inside a signed app bundle with a provisioning profile.**
   This is the standard way to reach the Enclave on macOS: an App ID with the
   keychain-sharing capability, a profile embedded in a small `.app` that
   `bin/release` invokes headlessly. **Open question nobody has checked: whether
   a *Developer ID* provisioning profile can authorise `keychain-access-groups`
   at all.** That is answerable only in the developer portal, and only by John.
3. **Hardware token** (YubiKey PIV via PKCS#11). Genuinely non-exportable, works
   from a CLI, costs a device and a dependency.

What non-exportability actually buys, so the choice is made with open eyes: an
attacker who reaches the release Mac can sign releases under *every* option — the
key is usable there by definition. What options 2 and 3 prevent is the key being
*taken away* and used later, elsewhere, after the machine is cleaned up. That is
worth something, and it is not the whole threat.

**Why starting at 1 does not foreclose 2 or 3.** All three produce the same
artifact — a P-256 key that answers `SecKeyCreateSignature`, and a 65-byte X9.63
public key — so *the application's verification code never changes*, and macOS
surfaces PIV tokens through CryptoTokenKit as ordinary `SecKey`s. Storage lives
behind a `KeyStore` protocol in `bin/update-sign.swift`; another option is one
conformance.

**What is not swappable, and so has to be right from the start.** A key cannot be
moved into the Enclave or onto a token — both only generate internally — so
changing option is always a key **rotation**. That is why the manifest carries a
`keyID` and the app embeds two public keys, current and next. Ship those in step
4 or the later swap strands every user who has not updated. This is the part that
makes the decision reversible; the protocol is just tidiness.

#### The tool, which is the same either way

    bin/update-sign create-key   [--label j23-update-signing]
    bin/update-sign public-key   [--label …]      # prints base64 X9.63, for Info.plist
    bin/update-sign sign <file>  [--label …]      # prints base64 DER ECDSA
    bin/update-sign self-test                      # throwaway key, sign, verify, delete

Signing is `SecKeyCreateSignature` with
`kSecKeyAlgorithmECDSASignatureMessageX962SHA256`; the public key is exported
with `SecKeyCopyExternalRepresentation` (X9.63, 65 bytes — **not** DER; an
earlier draft of this plan said DER and was wrong). Keep key *storage* behind one
function so option 1 can become option 2 or 3 without touching the rest.

`self-test` is the pin, and it runs on the release Mac rather than in CI. It
creates a throwaway key, signs, verifies **through the app's own key-import
path**, checks that a tampered payload is rejected, and deletes the key.

`bin/update-sign` compiles and code-signs the tool rather than running it through
`swift`, and that is not incidental: a software key's keychain ACL binds to the
program that created it. Created by the interpreter, the ACL would name `swift`,
and any script run through it could then use the key unprompted. Bound to a
Developer ID-signed binary, the ACL matches on the designated requirement, so
rebuilding keeps access and nothing else gains it.

**Done** — `bin/update-sign` and `bin/update-sign.swift`, plus a fixture test
(`test_a_signature_from_the_signing_tool_verifies`) that checks a signature the
tool actually produced against the app's verifier. Nothing else covers that: the
tool and the verifier each have their own pins and could be internally consistent
while disagreeing about a format.

### Step 3 — `SecKeyVerifySignature` alongside `SecTransform`

**What.** Add to `OakDownloadManager`:

    func data(_ data: Data, hasValidECDSASignature signature: Data,
              usingPublicKey publicKey: SecKey) -> Bool

using `SecKeyVerifySignature` with
`kSecKeyAlgorithmECDSASignatureMessageX962SHA256`. Add a companion that builds a
`SecKey` from the DER-base64 string the Info.plist will carry
(`SecKeyCreateWithData`, `kSecAttrKeyTypeECSECPrimeRandom`, `kSecAttrKeyClassPublic`).

**Leave the existing DSA/SecTransform path exactly as it is.** `BundlesManager`
verifies MacroMates' bundle index with it, using keys that come from *inside*
that index, and that is not ours to change. The two verifiers coexist; the
signee name chooses. Put both facts in a comment above the new function.

**Pin.** In `t_software_update.mm`, through `SoftwareUpdateTesting.h`:
generate a P-256 keypair *in the test* (`SecKeyCreateRandomKey`, no token —
software key, fine for a test), sign a known string, and assert:
valid signature verifies; one flipped bit in the data fails; one flipped bit in
the signature fails; a signature by a different key fails. The DER round trip of
the public key through the string form is pinned too.

**Mutation.** Make the verifier return `true`; three of four assertions must
fail. (The "valid verifies" one must keep passing — that is the guard.)

**Rule 8.** Nothing in the app reaches this yet. Say so.

### Step 4 — the manifest, and a download path that takes one

**The manifest format**, so nobody has to canonicalise JSON:

    {
      "manifest":  "<base64 of the exact UTF-8 bytes of the inner document>",
      "keyID":     "j23-2026",
      "signature": "<base64 DER ECDSA over those exact bytes>"
    }

The inner document is JSON:

    {
      "version": "2026.9-alpha.22",
      "url":     "https://github.com/johnmcgovern/textmate-ng/releases/download/v2026.9-alpha.22/TextMate-NG-2026.9-alpha.22.tbz",
      "sha256":  "<hex>",
      "size":    12345678,
      "issued":  "2026-09-06T12:00:00Z",
      "expires": "2026-10-06T12:00:00Z",
      "minimumSystemVersion": "15.0"
    }

Signing the *bytes* and shipping them base64-encoded inside the wrapper means
the client verifies first and parses second, and never has to agree with the
signer about whitespace or key order. One file, atomic.

**What changes.**

*`SoftwareUpdate.checkForTestBuild`* gains a manifest branch. Today it expects
`{url, version}` from the channel URL. Add: if the response parses as the wrapper
above, (a) look up `keyID` in `Info.plist` `TMSigningKeys` — which becomes a
dictionary of `signee → {algorithm, publicKey}` so the DSA entry and the new
P-256 entries can coexist; (b) verify the signature over the decoded bytes
with step 3's verifier; (c) reject if `expires` is past; (d) parse the inner
document and hand `url`, `version`, `sha256`, `size` onward. Every rejection
is a distinct error string; they are pinned.

*`OakDownloadManager`* gains:

    @objc(downloadArchiveAtURL:forReplacingURL:expectedSHA256:expectedSize:completionHandler:)
    func downloadArchive(at:, forReplacing:, expectedSHA256: String,
                         expectedSize: Int64, completionHandler:) -> ProgressReporting

which uses step 1's file-then-verify path with a **hash and size** check instead
of a header signature. The old header-signature entry point stays for
`BundlesManager` and is *also* pinned as still working — that is rule 18 applied
to the thing you did not mean to change. **Reject on size before hashing**: a
`size` mismatch is checked as bytes arrive (cancel the task past `expectedSize`),
and the hash is checked on the complete file. Order matters; pin it.

*`SUDownloadViewController`* passes the hash and size through.

**Pin.** The manifest parser, with a test keypair: valid manifest parses;
bad signature rejected; expired rejected; unknown `keyID` rejected; each with
its own error string. The download path: build a real `.tbz` in the test, serve
it from a `file://` URL — **probe whether `URLSession` data tasks accept
`file://` in a test bundle before relying on it**; if not, use a local
`NSURLProtocol` subclass registered for a fake scheme, which is the standard
trick — and assert: correct hash extracts; wrong hash does not extract and
reports the hash error; oversize is cancelled. This is where the step-1 ordering
pin lands: **assert that on a hash mismatch, the extraction directory does not
exist.**

**Mutation.** Swap the hash comparison for `true`; the wrong-hash test must fail.
Move the extraction before the hash check; the directory-does-not-exist test
must fail.

**Rule 8.** Still nothing in the app reaches this — `channels` is nil. Say so.

### Step 5 — code signature of the unpacked bundle, and consistency

**What.** Before `SUDownloadViewController.takeURLToInstallFrom` calls
`replaceItem(at:withItemAt:…)`, and *in place of* the executable-bit check in
`isInstallableApplication(at:)`:

1. `SecStaticCodeCreateWithPath` on the unpacked `.app`;
2. `SecRequirementCreateWithString` with
   `anchor apple generic and identifier "com.j23software.TextMate-NG" and
   (certificate leaf[subject.OU] = "R22V2H7QF4" or certificate leaf[subject.OU]
   = "<NEW TEAM ID>")` — the second clause is a placeholder until J23's
   organisation Team ID exists; leave it as a single OU until then, with a
   comment saying where the second one goes;
3. `SecStaticCodeCheckValidityWithErrors` with `kSecCSStrictValidate |
   kSecCSCheckAllArchitectures`;
4. read the unpacked bundle's `Info.plist` **as a file** (`PropertyListSerial-
   ization`, not `Bundle(path:)` — do not give the runtime a chance to load
   anything from it) and assert `CFBundleIdentifier` and
   `CFBundleShortVersionString` match the manifest.

Any failure presents the existing "Integrity Check Failed" alert path.

**Pin.** The requirement string is pinned as a literal (a typo in a requirement
is a silent "nothing ever installs"). The consistency check is pinned with a
fake bundle directory built in the test: matching Info.plist passes the
consistency part, mismatched identifier fails, mismatched version fails. The
codesign check itself can be pinned against the *test bundle's own host* or
against `/System/Applications/TextEdit.app` with an `anchor apple` requirement
as a "the API works" control, and with a wrong-OU requirement as the control
that must fail (rule 59).

**Mutation.** Return `true` from the codesign check; the wrong-OU control must
fail.

**Rule 8.** Not reachable yet.

### Step 6 — `bin/release`, and wiring `channels`

**Two commits**, because one is shell and one is Swift, and because the second
is the one that turns everything on.

**6a — `bin/release`.** After the zip is built and re-verified (it already
unpacks to `$WORK/unpacked` and checks it), add:

1. `tar -cjf "$ROOT/build/TextMate-NG-$VERSION.tbz" -C "$WORK/unpacked" TextMate-NG.app`
   — from the *verified* unpacked copy, not from `build/`;
2. `shasum -a 256` and `stat -f %z` of the tbz;
3. write the inner manifest document; `bin/update-sign sign` it; write the
   wrapper;
4. add the tbz to the `gh release create` line at line 263, alongside the zip
   and the dSYM zip;
5. publish the wrapper at a **stable URL**. Recommended: a `gh-pages` branch
   holding `update/release.json`, which `bin/release` commits and pushes.
   GitHub Pages returns `application/json; charset=utf-8`, which step 0 already
   made acceptable. (Alternative: a rolling GitHub Release named `updates`
   whose single asset is overwritten; the URL is stable but the API is the
   only way to find it. Pages is simpler. Decide once and write it down.)
6. **`--dry-run` must exercise all of the above except the push**, printing the
   manifest it would sign. Run it before and after; paste the output in the
   commit.

The `expires` value: 35 days from `issued`. `bin/release` re-signs the manifest
every release; if a month passes without a release, run
`bin/release --resign-manifest` (add it) to refresh the expiry without publishing
anything. Put that in the handoff's release checklist.

**6b — `channels`.** In `AppController.applicationWillFinishLaunching`, replace
the Phase 2.5 comment block with:

    SoftwareUpdate.sharedInstance.channels = [
        kSoftwareUpdateChannelRelease: URL(string: "https://johnmcgovern.github.io/textmate-ng/update/release.json")!,
    ]

(one channel; `beta` and `nightly` can be added when they mean something), and
add the **anti-rollback** guard to `SoftwareUpdate`'s scheduler path: if the
manifest's `version` is not greater than the running one by
`OakCompareVersionStrings`, log and finish without presenting. The
user-initiated path keeps its existing "Up To Date" / "Downgrade to" behaviour.

**Pin for 6b.** Anti-rollback: with a manifest naming an older version, the
background path's completion is called with no UI. (Reach it through
`checkForTestBuild` with a stubbed manifest URL via the `NSURLProtocol` trick
from step 4.)

**Rule 8 for 6b — this is the first time it is reachable.** Build Release, launch,
**open Preferences ▸ Software Update and click Check Now**. With `--dry-run`
output published nowhere, it should report the manifest fetch failure cleanly.
This is the step where the environment's inability to bring the app frontmost
bites; if you are in that environment, say so, and J3 covers it.

### Step 7 — Tier 2, if J2 says yes

**What.** A new tool target, `TextMateUpdateHelper`, built like `CommitWindowTool`
but with library validation **on** (do *not* copy the app's
`disable-library-validation` entitlement) and no plug-in loading. It takes the
manifest URL and the channel on stdin, does steps 4–5 and the swap, and reports
progress and result as JSON lines on stdout. `SUDownloadViewController` launches
it with `Process`, parses the stream into its existing `NSProgress`, and shows
the same UI. The helper re-runs the codesign check **immediately before**
`replaceItem`, from a directory it created itself.

**Probe first**: whether a helper *inside* the app bundle can replace the bundle
it is running from. `bin/release`'s own model (the app replaces itself, then a
shell script relaunches it) suggests yes — the `open "$0"` relaunch dance in
`takeURLToInstallFrom` is the thing to keep.

**Pin.** The JSON-lines protocol, both directions, with a fake helper script.

**Rule 8.** Same as 6b, and J3.

### Step 8 — J3, the first self-update

Not a commit. On one machine that is *not* the release Mac:

1. install the last published release the normal way, from the zip;
2. cut a new release with `bin/release` (a real one, with a `Changes.md` entry);
3. on the test machine, Check for Updates → Download → Install & Relaunch;
4. confirm the relaunched app reports the new version, is Developer ID-signed
   (`codesign -dvv`), stapled (`stapler validate`), and passes
   `spctl -a -t exec -vv`;
5. confirm the *old* bundle is gone and no `NSItemReplacementDirectory` leftovers
   remain in `~/Library/…/TemporaryItems`.

Then, deliberately: publish a manifest with a **wrong hash**, check for updates,
and confirm the app refuses with the hash error and **extracts nothing**. That is
step 1 and step 4 proving themselves against the real pipeline. Revert the
manifest.

Write what happened into the handoff. If anything in this list did not happen,
the feature is not done.

## Known gaps — things believed true that no test guards

- **"Nothing is extracted before verification" is structural, not pinned.**
  Step 1 moved extraction after verification and step 4b verifies by checksum,
  and both are visible in ten readable lines of `-didCompleteWithError:`. But
  moving extraction back in front of `verify` **fails no test in the suite** —
  confirmed by mutation on 2026-09-08. It is not observable from a test:
  extraction goes into an `NSItemReplacementDirectory`, all of those land under
  `<TMPDIR>/TemporaryItems`, and that directory is not readable
  (`contentsOfDirectoryAtPath:` → nil, "Operation not permitted"). A test that
  counted them was written, passed, and was deleted, because it could not fail.

  To close it, the extraction destination would have to be injectable — a
  `KeyStore`-shaped seam for the filesystem — which is API added for a test. Left
  open deliberately; whoever changes that method should know the guard is a code
  review, not a test.

- **A missing `dynamic` on `FFTextFieldViewController.hasFocus`/`stringValue`
  is unguarded.** The binding pins set the property from ObjC++, which reaches
  the setter through `objc_msgSend` and fires KVO regardless. `dynamic` matters
  for the Swift-side set, which happens inside `-observeValueForKeyPath:` and
  needs a window. See `6ca214c8`.

## Hazards, specific to this work

- **Rule 64 — custom getters.** `checking` is already handled (`isChecking`
  computed alongside). Any *new* `@objc` Bool property you add: grep the header
  for `getter =` and list the *selector* in the pin, not the Swift name.
- **Rule 56 — do not subclass across a module boundary.** Nothing in this plan
  needs to, and `SoftwareUpdate` is observed from Preferences across that
  boundary already, which is fine (observing, not subclassing).
- **`OakDownloadManager` is shared with `BundlesManager`.** Every step that
  touches it pins the old path too. The bundle index fetch is the rule-8 check
  for that: shorten `bundleUpdateFrequency` to 60, relaunch, watch for
  `GET https://api.textmate.org/bundles using entity tag`, restore it. Exactly
  as `97ffa70f` did.
- **`default.rave` globs.** If you add a `.swift` to a framework that has none,
  `sources src/*.mm` silently compiles nothing and the symptom is an undefined
  ObjC class symbol in an *unrelated* target. `SoftwareUpdate` is already
  `src/*.{mm,swift}`; a new tool target will need its own line.
- **`nonisolated(unsafe)` is the established form** for non-MainActor singletons
  and for the explicit queue crossings in `checkForTestBuild`. Do not "fix" them
  into `@MainActor` — that class is deliberately not.
- **Two logging conventions.** `Logger()` where the ObjC++ had `OS_LOG_DEFAULT`;
  a named subsystem only where the ObjC++ had one. New code in this framework
  follows the file it lives in.
- **The probe's own flags (rule 62).** Any header you add to
  `SoftwareUpdate-Bridging-Header.h`, probe at `-std=c++2a` with a control that
  fails. The script shape is in the session notes for 2026-09-05.
- **Do not touch the DSA path.** It is deprecated, it is MacroMates', and it is
  how bundles get verified. It goes when the bundle index goes, which is not
  this plan.

## Done means

- Every step's pin exists, was mutation-checked, and the mutation is recorded in
  the commit message.
- Suite green with all three rule-54 greps on every commit; CI green on every
  push.
- The design note's "four mismatches" table shows all four struck through.
- Step 8 happened, on a real machine, including the wrong-hash refusal, and is
  written up in the handoff.
- The smoke list's Software Update row is updated to say what the release
  process now checks automatically and what it still does not.
