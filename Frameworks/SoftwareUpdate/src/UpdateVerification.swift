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
			throw failure("The update is not code-signed (status \(createStatus)).")
		}

		var secRequirement: SecRequirement?
		let requirementStatus = SecRequirementCreateWithString(requirement as CFString, [], &secRequirement)
		guard requirementStatus == errSecSuccess, let secRequirement else {
			// A malformed requirement string is our bug, not a bad download, and it
			// would otherwise present as every update failing its integrity check.
			throw failure("Internal error: the update requirement is malformed (status \(requirementStatus)).")
		}

		let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
		var cfError: Unmanaged<CFError>?
		let status = SecStaticCodeCheckValidityWithErrors(staticCode, flags, secRequirement, &cfError)
		guard status == errSecSuccess else {
			let detail = cfError.map { String(describing: $0.takeRetainedValue()) } ?? "status \(status)"
			log.error("Update failed its code-signature check: \(detail, privacy: .public)")
			throw failure("The update is not signed by J23.")
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
			throw failure("The update has no readable Info.plist.")
		}

		guard let identifier = info["CFBundleIdentifier"] as? String, identifier == "com.j23software.TextMate-NG" else {
			throw failure("The update is a different application (\(info["CFBundleIdentifier"] as? String ?? "no identifier")).")
		}

		guard let version = info["CFBundleShortVersionString"] as? String, version == manifest.version else {
			throw failure("The update is version \(info["CFBundleShortVersionString"] as? String ?? "?"), but its manifest says \(manifest.version).")
		}
	}

	private static func failure(_ message: String) -> Error {
		return NSError(domain: "SoftwareUpdate", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
	}
}
