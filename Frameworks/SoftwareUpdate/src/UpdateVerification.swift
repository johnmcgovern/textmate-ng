import Foundation
import Security
import os

// The last two checks before the running application is replaced. Step 5 of
// ide/SOFTWARE_UPDATE_PLAN.md.
//
// The manifest's signature answers "did J23 publish this?"; these answer "will
// this actually launch, and is it the thing the manifest described?". Both are
// worth having and they fail differently: a payload can be perfectly signed by us
// and still be a build macOS will refuse to run.
//
// Order matters here too. The code signature is checked **before** anything reads
// the bundle as a bundle — the Info.plist below is parsed as a *file*, not
// through NSBundle, so nothing in the downloaded tree gets a chance to be loaded
// on the way to deciding whether to trust it.

private let log = Logger()

// **Why these are distinguishable.** Everything reaching UpdateVerification has
// already matched the manifest's SHA-256 and size, so "the download is corrupt"
// is *almost* never the explanation — the bytes were exactly what J23 described.
// The one exception is damage after extraction, which is what
// SecStaticCodeCheckValidityWithErrors catches and what the old
// "the system has been deleting temporary files" wording was really about.
//
// A wrong signer, a different application, or a version that disagrees with the
// manifest are a different thing entirely: the download succeeded and what
// arrived is not acceptable. Redownloading cannot help, and offering it as the
// remedy sends the user round a loop that fails identically every time.
//
// So the codes exist to let the UI say which happened, and the tests to pin that
// the two families stay apart. Codes are stable: SUDownloadViewController
// switches on them.
@objc(TMUpdateVerificationError)
enum UpdateVerificationError: Int, Error, CustomNSError {
	case notCodeSigned      = 1   // no signature at all — damage, or not an app
	case signatureNotValid  = 2   // signature present and unacceptable, or damaged resources
	case malformedRequirement = 3 // our bug, not the download's
	case unreadableInfoPlist  = 4
	case differentApplication = 5
	case versionMismatch      = 6

	static var errorDomain: String { "SoftwareUpdate" }
	var errorCode: Int { rawValue }

	// True when trying again could plausibly produce a different outcome: the
	// bundle arrived damaged. False when the payload is intact and simply not
	// something this build will install.
	var isWorthRetrying: Bool {
		switch self {
			case .notCodeSigned, .signatureNotValid, .unreadableInfoPlist: return true
			case .malformedRequirement, .differentApplication, .versionMismatch: return false
		}
	}
}

@objc(TMUpdateVerification)
final class UpdateVerification: NSObject {
	// **A typo here is an updater that never installs anything**, and it would look
	// like a corrupt download rather than a bad string, so it is pinned as a
	// literal in t_software_update.mm.
	//
	// `anchor apple generic` plus the leaf's OU is the Developer ID form: the OU
	// field of a Developer ID leaf certificate is the Team ID. The identifier
	// clause stops a validly-signed *different* J23 application being installed
	// over this one.
	//
	// **When the Team ID changes**, this becomes a disjunction —
	// `(certificate leaf[subject.OU] = "R22V2H7QF4" or certificate
	// leaf[subject.OU] = "<NEW>")` — and stays that way for at least one release
	// either side of the transition. Anyone who skips that window is stranded on a
	// build that refuses every update. See ide/SOFTWARE_UPDATE_DESIGN.md; this is
	// the one place in the updater that is deliberately coupled to the signing
	// identity, and the manifest key deliberately is not.
	@objc static let designatedRequirement =
		"anchor apple generic and identifier \"com.j23software.TextMate-NG\" and certificate leaf[subject.OU] = \"R22V2H7QF4\""

	// `requirement` is a parameter rather than the constant above so the mechanism
	// can be pinned against a bundle that actually exists on the test machine —
	// with `anchor apple` as the control that must pass and a wrong Team ID as the
	// control that must fail (rule 59).
	@objc(checkCodeSignatureOfBundleAtURL:requirement:error:)
	static func checkCodeSignature(ofBundleAt url: URL, requirement: String) throws {
		var staticCode: SecStaticCode?
		let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
		guard createStatus == errSecSuccess, let staticCode else {
			throw failure(.notCodeSigned, "The update is not code-signed (status \(createStatus)).")
		}

		var secRequirement: SecRequirement?
		let requirementStatus = SecRequirementCreateWithString(requirement as CFString, [], &secRequirement)
		guard requirementStatus == errSecSuccess, let secRequirement else {
			// A malformed requirement string is our bug, not a bad download, and it
			// would otherwise present as every update failing its integrity check.
			throw failure(.malformedRequirement, "Internal error: the update requirement is malformed (status \(requirementStatus)).")
		}

		let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
		var cfError: Unmanaged<CFError>?
		let status = SecStaticCodeCheckValidityWithErrors(staticCode, flags, secRequirement, &cfError)
		guard status == errSecSuccess else {
			let detail = cfError.map { String(describing: $0.takeRetainedValue()) } ?? "status \(status)"
			log.error("Update failed its code-signature check: \(detail, privacy: .public)")
			throw failure(.signatureNotValid, "The update is not signed by J23.")
		}
	}

	// The bundle must be the one the manifest described. Without this a valid,
	// correctly-signed *older* build could be served under a newer manifest — the
	// hash would match the archive, and the archive would contain something else
	// than advertised.
	//
	// Info.plist is read as a file on purpose. `Bundle(path:)` would register the
	// bundle with the runtime, and nothing in a not-yet-trusted tree should be
	// handed to the loader to answer a question about whether to trust it.
	@objc(checkBundleAtURL:matchesManifest:error:)
	static func checkBundle(at url: URL, matches manifest: UpdateManifest) throws {
		let infoURL = url.appendingPathComponent("Contents/Info.plist")
		guard let data = try? Data(contentsOf: infoURL),
		      let info = (try? PropertyListSerialization.propertyList(from: data, options: 0, format: nil)) as? [String: Any]
		else {
			throw failure(.unreadableInfoPlist, "The update has no readable Info.plist.")
		}

		guard let identifier = info["CFBundleIdentifier"] as? String, identifier == "com.j23software.TextMate-NG" else {
			throw failure(.differentApplication, "The update is a different application (\(info["CFBundleIdentifier"] as? String ?? "no identifier")).")
		}

		guard let version = info["CFBundleShortVersionString"] as? String, version == manifest.version else {
			throw failure(.versionMismatch, "The update is version \(info["CFBundleShortVersionString"] as? String ?? "?"), but its manifest says \(manifest.version).")
		}
	}

	// The message stays the authority on what the user reads; the code only says
	// which family it belongs to. Spelled this way so the existing pins on these
	// strings keep testing the strings.
	private static func failure(_ code: UpdateVerificationError, _ message: String) -> Error {
		return NSError(domain: UpdateVerificationError.errorDomain, code: code.rawValue,
		               userInfo: [NSLocalizedDescriptionKey: message])
	}

	// Whether a failed verification is worth downloading again. Exposed for the
	// UI and pinned, because getting it backwards is how you offer somebody an
	// infinite retry loop on a build that will never be acceptable.
	@objc(isWorthRetryingError:)
	static func isWorthRetrying(_ error: Error) -> Bool {
		let nsError = error as NSError
		guard nsError.domain == UpdateVerificationError.errorDomain,
		      let code = UpdateVerificationError(rawValue: nsError.code)
		else {
			// An error from somewhere else: assume damage rather than rejection, which
			// is the conservative answer — it offers a retry that may fail, instead of
			// refusing one that would have worked.
			return true
		}
		return code.isWorthRetrying
	}
}
