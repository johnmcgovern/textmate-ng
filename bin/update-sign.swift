// The update-manifest signing tool. Compiled and run by `bin/update-sign`.
//
// Signs the update manifest with ECDSA P-256 / SHA-256. The public half goes into
// the application's Info.plist under TMSigningKeys; the app verifies with
// SecKeyVerifySignature (Frameworks/SoftwareUpdate/src/OakDownloadManager.swift).
//
// ## Where the private key lives, and how to change it later
//
// Today: a software key in the login keychain of the release Mac. That is
// option 1 of three in ide/SOFTWARE_UPDATE_PLAN.md step 2, and it was chosen
// knowing what it is and is not — see the probe table there. It is **not**
// non-exportable: `kSecAttrIsExtractable = false` was measured and prevents
// neither SecKeyCopyExternalRepresentation nor SecItemExport. What protects this
// key is FileVault, the login keychain, and physical control of the machine.
//
// The two stronger options are the Secure Enclave (requires the signer to be an
// app bundle carrying a provisioning profile, because keychain-access-groups is
// a restricted entitlement) and a hardware token such as a YubiKey in PIV mode.
//
// **Swapping to either is a `KeyStore` conformance and nothing else in this
// file**, because all three produce the same thing: a SecKey that answers
// SecKeyCreateSignature, and a P-256 public key that exports as 65-byte X9.63.
// macOS surfaces PIV tokens through CryptoTokenKit as ordinary SecKeys, so even
// the token case is a different `findKey` and the same `sign`.
//
// **The part that is not swappable, and therefore has to be right now:** a key
// cannot be moved into the Enclave or onto a token — both only generate
// internally — so changing option is always a key *rotation*. That is why the
// manifest carries a `keyID` and the app looks the key up in a dictionary rather
// than holding one. Rotation is two releases: ship one trusting old **and** new,
// wait for adoption, then sign with the new and drop the old later. Rotation is
// not a nicety here; it is what makes this decision reversible.

import Foundation
import Security

let defaultLabel = "j23-update-signing"

func die(_ message: String) -> Never {
	FileHandle.standardError.write(Data("update-sign: \(message)\n".utf8))
	exit(1)
}

func describe(_ error: Unmanaged<CFError>?) -> String {
	guard let error else { return "unknown error" }
	return String(describing: error.takeRetainedValue())
}

// MARK: - Key storage
//
// The seam. One conformance per option; nothing outside this protocol knows
// where the key lives.

protocol KeyStore {
	/// Human-readable, for messages: "login keychain", "Secure Enclave", …
	var describedLocation: String { get }

	/// Creates a new P-256 private key. Fails if one already exists for `label`.
	func createKey(label: String) throws -> SecKey

	/// The existing private key, or nil.
	func findKey(label: String) throws -> SecKey?

	/// Removes it. Used by self-test; not by the release flow.
	func deleteKey(label: String) throws
}

struct KeychainKeyStore: KeyStore {
	var describedLocation: String { "the login keychain (software key)" }

	private func tag(_ label: String) -> Data { Data(label.utf8) }

	func createKey(label: String) throws -> SecKey {
		if try findKey(label: label) != nil {
			die("a key labelled '\(label)' already exists — refusing to replace it. Use delete-key first if that is really what you want.")
		}

		let attributes: [String: Any] = [
			kSecAttrKeyType as String:       kSecAttrKeyTypeECSECPrimeRandom,
			kSecAttrKeySizeInBits as String: 256,
			kSecPrivateKeyAttrs as String: [
				kSecAttrIsPermanent as String:    true,
				kSecAttrApplicationTag as String: tag(label),
				kSecAttrLabel as String:          label,
			],
		]

		var error: Unmanaged<CFError>?
		guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
			die("could not create key: \(describe(error))")
		}
		return key
	}

	func findKey(label: String) throws -> SecKey? {
		let query: [String: Any] = [
			kSecClass as String:              kSecClassKey,
			kSecAttrKeyType as String:        kSecAttrKeyTypeECSECPrimeRandom,
			kSecAttrApplicationTag as String: tag(label),
			kSecReturnRef as String:          true,
		]

		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)
		switch status {
			case errSecSuccess:      return (item as! SecKey)
			case errSecItemNotFound: return nil
			default:                 die("keychain lookup failed (status \(status))")
		}
	}

	func deleteKey(label: String) throws {
		let query: [String: Any] = [
			kSecClass as String:              kSecClassKey,
			kSecAttrApplicationTag as String: tag(label),
		]
		let status = SecItemDelete(query as CFDictionary)
		if status != errSecSuccess && status != errSecItemNotFound {
			die("could not delete key (status \(status))")
		}
	}
}

// Option 2 (Secure Enclave) and option 3 (PIV token) each add a KeyStore here.
// The Enclave one differs only by kSecAttrTokenIDSecureEnclave plus an access
// control, and needs this tool to become an app bundle with a provisioning
// profile; the token one has no createKey at all — the key is generated on the
// device — and finds by kSecAttrTokenID. Both then sign through the same code
// below.

let store: KeyStore = KeychainKeyStore()

// MARK: - Operations

func publicKeyBase64(_ privateKey: SecKey) -> String {
	guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
		die("could not derive the public key")
	}
	var error: Unmanaged<CFError>?
	guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) else {
		die("could not export the public key: \(describe(error))")
	}
	// X9.63: 0x04 || X || Y, 65 bytes for P-256. This is exactly what the app's
	// +publicKeyFromBase64X963String: consumes — not DER, not PEM.
	return (data as Data).base64EncodedString()
}

func signatureBase64(_ privateKey: SecKey, over payload: Data) -> String {
	var error: Unmanaged<CFError>?
	guard let signature = SecKeyCreateSignature(privateKey, .ecdsaSignatureMessageX962SHA256, payload as CFData, &error) else {
		die("could not sign: \(describe(error))")
	}
	return (signature as Data).base64EncodedString()
}

func labelArgument(_ arguments: [String]) -> String {
	if let index = arguments.firstIndex(of: "--label") {
		guard index + 1 < arguments.count else { die("--label needs a value") }
		return arguments[index + 1]
	}
	return defaultLabel
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
	die("""
	usage:
	  update-sign create-key  [--label L]      create the signing key, print its public half
	  update-sign public-key  [--label L]      print the public key (base64 X9.63)
	  update-sign sign FILE   [--label L]      print the signature (base64 DER ECDSA)
	  update-sign delete-key  [--label L]      remove the key
	  update-sign verify FILE [--label L]      check a signed manifest against the key
	  update-sign self-test                    throwaway key: create, sign, verify, delete
	""")
}
let label = labelArgument(arguments)

switch command {
	case "create-key":
		let key = try store.createKey(label: label)
		FileHandle.standardError.write(Data("created '\(label)' in \(store.describedLocation)\n".utf8))
		FileHandle.standardError.write(Data("this key is NOT non-exportable — see ide/SOFTWARE_UPDATE_PLAN.md step 2\n".utf8))
		print(publicKeyBase64(key))

	case "public-key":
		guard let key = try store.findKey(label: label) else { die("no key labelled '\(label)'") }
		print(publicKeyBase64(key))

	case "sign":
		let paths = arguments.dropFirst().filter { $0 != "--label" && $0 != label }
		guard let path = paths.first else { die("sign needs a file") }
		guard let payload = FileManager.default.contents(atPath: path) else { die("cannot read \(path)") }
		guard let key = try store.findKey(label: label) else { die("no key labelled '\(label)'") }
		print(signatureBase64(key, over: payload))

	case "delete-key":
		try store.deleteKey(label: label)
		FileHandle.standardError.write(Data("deleted '\(label)'\n".utf8))

	// Checks a wrapper the way the *application* will: decode the base64 manifest,
	// rebuild the public key from its string form, verify the signature over those
	// exact bytes. bin/release runs this on what it just produced, because a
	// release whose manifest does not verify is worse than no release — every user
	// gets an integrity error and no way to tell it from an attack.
	case "verify":
		let paths = arguments.dropFirst().filter { $0 != "--label" && $0 != label }
		guard let path = paths.first else { die("verify needs a file") }
		guard let blob = FileManager.default.contents(atPath: path) else { die("cannot read \(path)") }

		guard let wrapper = (try? JSONSerialization.jsonObject(with: blob)) as? [String: Any],
		      let encodedManifest = wrapper["manifest"] as? String,
		      let encodedSignature = wrapper["signature"] as? String,
		      let keyID = wrapper["keyID"] as? String,
		      let signedBytes = Data(base64Encoded: encodedManifest),
		      let signature = Data(base64Encoded: encodedSignature)
		else {
			die("\(path) is not a signed manifest")
		}

		guard let key = try store.findKey(label: label), let publicKey = SecKeyCopyPublicKey(key) else {
			die("no key labelled '\(label)' to verify against")
		}

		guard SecKeyVerifySignature(publicKey, .ecdsaSignatureMessageX962SHA256, signedBytes as CFData, signature as CFData, nil) else {
			die("signature does not verify — this manifest would be refused by every client")
		}

		guard let inner = (try? JSONSerialization.jsonObject(with: signedBytes)) as? [String: Any],
		      let version = inner["version"] as? String,
		      let expires = inner["expires"] as? String
		else {
			die("the signed bytes are not a manifest")
		}
		print("verified: keyID \(keyID), version \(version), expires \(expires)")

	case "self-test":
		// The pin for this tool. Runs on the release Mac, not in CI, and leaves
		// nothing behind.
		let throwaway = "j23-update-sign-selftest-\(UUID().uuidString)"
		let key = try store.createKey(label: throwaway)
		defer { try? store.deleteKey(label: throwaway) }

		let encoded = publicKeyBase64(key)
		guard let raw = Data(base64Encoded: encoded), raw.count == 65 else {
			die("public key is \(Data(base64Encoded: encoded)?.count ?? -1) bytes, expected 65 (X9.63 P-256)")
		}

		let payload = Data("{\"version\":\"self-test\"}".utf8)
		let signature = Data(base64Encoded: signatureBase64(key, over: payload))!

		// Verify the way the *app* will: rebuild the public key from its string
		// form, then SecKeyVerifySignature. If this passes, the two sides agree.
		let attributes: [String: Any] = [
			kSecAttrKeyType as String:  kSecAttrKeyTypeECSECPrimeRandom,
			kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
		]
		var error: Unmanaged<CFError>?
		guard let publicKey = SecKeyCreateWithData(raw as CFData, attributes as CFDictionary, &error) else {
			die("the app's key-import path rejected our public key: \(describe(error))")
		}

		guard SecKeyVerifySignature(publicKey, .ecdsaSignatureMessageX962SHA256, payload as CFData, signature as CFData, nil) else {
			die("signature did not verify")
		}

		var tampered = payload
		tampered[0] ^= 0x01
		guard !SecKeyVerifySignature(publicKey, .ecdsaSignatureMessageX962SHA256, tampered as CFData, signature as CFData, nil) else {
			die("a tampered payload verified — the verifier is not checking anything")
		}

		print("self-test ok: created, signed, verified, rejected a tampered payload, deleted")

	default:
		die("unknown command '\(command)'")
}
