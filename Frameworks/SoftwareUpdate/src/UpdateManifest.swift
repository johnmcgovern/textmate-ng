import Foundation
import Security
import os

// The signed update manifest. Step 4 of ide/SOFTWARE_UPDATE_PLAN.md.
//
// This is the document a channel URL returns, and everything the updater acts on
// is inside the signature: which version, where to fetch it, and what those bytes
// must hash to. The payload is not signed separately — it is pinned by hash from
// here, which is Chrome's shape (a CUP-signed response carrying `hash_sha256`)
// and the reason a hostile CDN cannot substitute a build or serve an older signed
// one. See ide/SOFTWARE_UPDATE_DESIGN.md.
//
//     {
//       "manifest":  "<base64 of the exact UTF-8 bytes of the inner document>",
//       "keyID":     "j23-2026",
//       "signature": "<base64 DER ECDSA P-256/SHA-256 over those exact bytes>"
//     }
//
// **The inner document travels base64-encoded, and that is the whole trick.** The
// signature covers those bytes literally, so the client verifies *first* and
// parses *second*, and neither side has to agree with the other about JSON
// whitespace, key order or escaping. Nothing here canonicalises anything.
//
// Keys live in Info.plist under `TMUpdateManifestKeys`, a dictionary of key ID to
// base64 X9.63 public key. Deliberately **not** the existing `TMSigningKeys`,
// which is signee-to-PEM for the legacy DSA archive signatures that
// BundlesManager still relies on; mixing the two would mean a dictionary with two
// value shapes and a cast that breaks.
//
// More than one key is expected to be present — current and next. That is what
// makes key rotation a normal release rather than an emergency, and rotation is
// what keeps the choice of key *storage* reversible: a key cannot be moved into
// the Secure Enclave or onto a hardware token, so changing to either is always a
// rotation. bin/update-sign.swift says the same thing from the other end.

private let log = Logger()

@objc(TMUpdateManifestError)
enum UpdateManifestError: Int, Error, CustomNSError {
	case malformed
	case unknownKey
	case badSignature
	case expired
	case incomplete

	static var errorDomain: String { "SoftwareUpdate" }
	var errorCode: Int { rawValue }

	var errorUserInfo: [String: Any] {
		let description: String
		switch self {
			case .malformed:    description = "Malformed update manifest."
			case .unknownKey:   description = "Update manifest is signed by an unknown key."
			case .badSignature: description = "Update manifest signature is not valid."
			case .expired:      description = "Update manifest has expired."
			case .incomplete:   description = "Update manifest is missing required fields."
		}
		return [NSLocalizedDescriptionKey: description]
	}
}

// @unchecked Sendable, and it is not a paper-over: every stored property below is
// a `let` holding an immutable value, the class is final, and nothing mutates one
// after -manifestFromData: returns it. The "unchecked" is only because NSObject
// is not Sendable, which it has to be to cross into ObjC.
@objc(TMUpdateManifest)
final class UpdateManifest: NSObject, @unchecked Sendable {
	@objc let version: String
	@objc let url: URL
	@objc let sha256: String
	@objc let size: Int64
	@objc let minimumSystemVersion: String?

	init(version: String, url: URL, sha256: String, size: Int64, minimumSystemVersion: String?) {
		self.version              = version
		self.url                  = url
		self.sha256               = sha256
		self.size                 = size
		self.minimumSystemVersion = minimumSystemVersion
	}

	// `now` is a parameter rather than Date() so expiry is testable without
	// waiting a month or lying to the clock.
	@objc(manifestFromData:keys:now:error:)
	static func manifest(from data: Data, keys: [String: String], now: Date) throws -> UpdateManifest {
		guard let wrapper = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
			throw UpdateManifestError.malformed
		}

		guard let encodedManifest = wrapper["manifest"] as? String,
		      let keyID           = wrapper["keyID"] as? String,
		      let encodedSignature = wrapper["signature"] as? String,
		      let signedBytes = Data(base64Encoded: encodedManifest, options: [.ignoreUnknownCharacters]),
		      let signature   = Data(base64Encoded: encodedSignature, options: [.ignoreUnknownCharacters])
		else {
			throw UpdateManifestError.malformed
		}

		// Verified before parsed. The order is the point.
		guard let encodedKey = keys[keyID] else {
			log.error("Update manifest names key '\(keyID, privacy: .public)', which this build does not carry")
			throw UpdateManifestError.unknownKey
		}
		guard let publicKey = OakDownloadManager.publicKey(fromBase64X963String: encodedKey) else {
			log.error("TMUpdateManifestKeys entry '\(keyID, privacy: .public)' is not a usable P-256 public key")
			throw UpdateManifestError.unknownKey
		}
		guard OakDownloadManager.sharedInstance.data(signedBytes, hasValidECDSASignature: signature, usingPublicKey: publicKey) else {
			throw UpdateManifestError.badSignature
		}

		guard let inner = (try? JSONSerialization.jsonObject(with: signedBytes)) as? [String: Any] else {
			throw UpdateManifestError.malformed
		}

		// Freshness. A CDN that can only replay something we signed can still replay
		// it forever, which would pin every user to a build with a known hole; the
		// expiry is what turns "stale" into "rejected". bin/release re-signs on a
		// schedule shorter than this.
		if let expires = inner["expires"] as? String {
			guard let expiryDate = ISO8601DateFormatter().date(from: expires) else {
				throw UpdateManifestError.malformed
			}
			if now > expiryDate {
				log.error("Update manifest expired at \(expires, privacy: .public)")
				throw UpdateManifestError.expired
			}
		} else {
			// Absent expiry is a malformed manifest, not an eternal one.
			throw UpdateManifestError.incomplete
		}

		guard let version = inner["version"] as? String,
		      let urlString = inner["url"] as? String,
		      let url = URL(string: urlString),
		      let sha256 = inner["sha256"] as? String,
		      let size = (inner["size"] as? NSNumber)?.int64Value,
		      size > 0
		else {
			throw UpdateManifestError.incomplete
		}

		return UpdateManifest(version: version,
		                      url: url,
		                      sha256: sha256.lowercased(),
		                      size: size,
		                      minimumSystemVersion: inner["minimumSystemVersion"] as? String)
	}

	// The keys this build carries. Two are expected — current and next.
	@objc static func embeddedKeys() -> [String: String] {
		return (Bundle.main.object(forInfoDictionaryKey: "TMUpdateManifestKeys") as? [String: String]) ?? [:]
	}
}
