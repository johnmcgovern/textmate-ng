import Foundation
import Security
import os

// Ported from OakDownloadManager.mm. Signed downloads: a plain file fetch with an
// ETag round trip, and a streaming tar extraction that reports NSProgress.
//
// The class's ObjC face is the hand declaration in OakDownloadManager.h (rule 23).
// Its consumers are ObjC++ — BundlesManager.mm calls both entry points — so every
// selector is spelled out with @objc(...) rather than left to the importer's
// renaming, and t_software_update.mm pins them (rule 18).
//
// **The SecTransform calls are deprecated and are ported unchanged anyway.**
// SecVerifyTransformCreate went away in macOS 13 in favour of
// SecKeyVerifySignature. Swapping the signature-verification path during a port
// would change what the app trusts, which is not a translation — it is a
// security change wearing a translation's clothes. It stays byte-for-byte until
// somebody replaces it deliberately, with its own commit and its own testing.

// os_log(OS_LOG_DEFAULT, …) throughout the original, so a default-initialised
// Logger — same destination. A named subsystem would be easier to filter for and
// is exactly the kind of quiet change a port should not make; AppControllerMenus
// took the same decision for the same reason.
private let log = Logger()

private let OakHTTPHeaderSignee    = "x-amz-meta-x-signee"
private let OakHTTPHeaderSignature = "x-amz-meta-x-signature"

// sysctl(CTL_HW, …). `isInteger` was a C++ default argument, which Swift spells
// natively.
private func GetHardwareInfo(_ field: Int32, isInteger: Bool = false) -> String {
	var request = [CTL_HW, field]
	var buf = [CChar](repeating: 0, count: 1024)
	var bufSize = buf.count

	let ok = request.withUnsafeMutableBufferPointer { req in
		sysctl(req.baseAddress, UInt32(req.count), &buf, &bufSize, nil, 0) != -1
	}
	guard ok else { return "???" }

	if isInteger && bufSize == 4 {
		let value = buf.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
		return "\(value)"
	}
	return String(cString: buf)
}

// ==========================
// = OakDownloadArchiveTask =
// ==========================

// Private to this file, exactly as it was to the .mm. It keeps itself alive the
// same way too: NSURLSession retains its delegate until the session invalidates,
// and -finishTasksAndInvalidate is called immediately so that happens once the
// single task completes.
private final class OakDownloadArchiveTask: NSObject, ProgressReporting, URLSessionDataDelegate {
	private let publicKeys: [String: String]
	private var signee: String?
	private var signature: String?

	private let completionHandler: (URL?, Error?) -> Void

	private var data = Data()

	private let fileURLToReplace: URL?
	private var temporaryFileURL: URL?

	private var extractorTask: Process?
	private var extractorFileHandleStorage: FileHandle?
	private let extractorDispatchGroup = DispatchGroup()
	private var extractorError: Error?

	private var sampleStartDate: Date?
	private var sampleCountOfBytesReceived: Int64 = 0

	private var extractorTaskOutputData: Data?
	private var extractorTaskErrorData: Data?

	let progress: Progress

	init(url: URL, forReplacing localURL: URL?, publicKeys: [String: String], completionHandler: @escaping (URL?, Error?) -> Void) {
		self.fileURLToReplace  = localURL
		self.publicKeys        = publicKeys
		self.completionHandler = completionHandler
		self.progress          = Progress.discreteProgress(totalUnitCount: -1)

		super.init()

		progress.kind = .file
		progress.fileOperationKind = .downloading
		progress.localizedDescription = "Downloading \(url.lastPathComponent)…"

		var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60)
		request.setValue(OakDownloadManager.sharedInstance.userAgentString, forHTTPHeaderField: "User-Agent")

		let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
		session.dataTask(with: request).resume()
		session.finishTasksAndInvalidate()
	}

	deinit {
		if let temporaryFileURL {
			do {
				try FileManager.default.removeItem(at: temporaryFileURL)
			} catch {
				log.error("Unable to remove \(temporaryFileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	// Lazily launches tar and returns the pipe to write the archive into. Returns
	// nil — having recorded `extractorError` — if either the replacement directory
	// or the launch fails, and -URLSession:dataTask:didReceiveData: then cancels.
	private var extractorFileHandle: FileHandle? {
		if let extractorFileHandleStorage {
			return extractorFileHandleStorage
		}

		// No "already tried and failed" guard, deliberately. The ObjC++ tested only
		// `if(!_extractorFileHandle)`, so a failed attempt left the ivar nil and the
		// *next* -didReceiveData: retried the whole thing — reachable, because
		// -cancel is asynchronous and more data can arrive after it. Retrying also
		// overwrites _temporaryFileURL and so leaks the previous replacement
		// directory. Both are preserved: this is a translation, and the leak is a
		// pre-existing bug to be fixed on its own terms, not silently during a port.
		let temporaryDirectory: URL
		do {
			temporaryDirectory = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: fileURLToReplace, create: true)
		} catch {
			log.error("Failed to obtain NSItemReplacementDirectory: \(error.localizedDescription, privacy: .public)")
			extractorError = error
			return nil
		}
		temporaryFileURL = temporaryDirectory

		let inputPipe  = Pipe()
		let outputPipe = Pipe()
		let errorPipe  = Pipe()

		let task = Process()
		task.launchPath     = "/usr/bin/tar"
		task.arguments      = [ "-jxmkC", temporaryDirectory.path, "--strip-components", "1", "--disable-copyfile", "--exclude", "._*" ]
		task.standardInput  = inputPipe
		task.standardOutput = outputPipe
		task.standardError  = errorPipe

		extractorDispatchGroup.enter()
		DispatchQueue.global().async {
			self.extractorTaskOutputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
			outputPipe.fileHandleForReading.closeFile()
			self.extractorDispatchGroup.leave()
		}

		extractorDispatchGroup.enter()
		DispatchQueue.global().async {
			self.extractorTaskErrorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
			errorPipe.fileHandleForReading.closeFile()
			self.extractorDispatchGroup.leave()
		}

		let group = extractorDispatchGroup // Avoid capturing ‘self’ in terminationHandler
		group.enter()
		task.terminationHandler = { _ in
			group.leave()
		}

		do {
			try task.run()
		} catch {
			log.error("Failed to launch tar: \(error.localizedDescription, privacy: .public)")

			extractorDispatchGroup.leave() // Termination handler will never be called
			outputPipe.fileHandleForWriting.closeFile()
			errorPipe.fileHandleForWriting.closeFile()

			extractorTask  = nil
			extractorError = error

			return nil
		}

		extractorTask = task
		extractorFileHandleStorage = inputPipe.fileHandleForWriting
		return extractorFileHandleStorage
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
		signee    = signee    ?? response.allHeaderFields[OakHTTPHeaderSignee] as? String
		signature = signature ?? response.allHeaderFields[OakHTTPHeaderSignature] as? String
		completionHandler(request)
	}

	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
		let headers = (response as? HTTPURLResponse)?.allHeaderFields
		signee    = signee    ?? headers?[OakHTTPHeaderSignee] as? String
		signature = signature ?? headers?[OakHTTPHeaderSignature] as? String
		completionHandler(.allow)
	}

	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		guard let fileHandle = extractorFileHandle, !progress.isCancelled else {
			dataTask.cancel()
			return
		}

		fileHandle.write(data)
		self.data.append(data)

		if dataTask.countOfBytesExpectedToReceive != NSURLSessionTransferSizeUnknown {
			if sampleStartDate == nil {
				sampleStartDate = Date()
			} else {
				let bytesLeft = dataTask.countOfBytesExpectedToReceive - dataTask.countOfBytesReceived
				if bytesLeft != 0 {
					let secondsSampled = -(sampleStartDate?.timeIntervalSinceNow ?? 0)
					if secondsSampled > 0.9 {
						let bytesReceivedSinceLastSample = dataTask.countOfBytesReceived - sampleCountOfBytesReceived
						progress.setUserInfoObject(ceil(Double(bytesLeft) * secondsSampled / Double(bytesReceivedSinceLastSample)), forKey: .estimatedTimeRemainingKey)

						sampleStartDate            = Date()
						sampleCountOfBytesReceived = dataTask.countOfBytesReceived
					}
				} else {
					progress.setUserInfoObject(nil, forKey: .estimatedTimeRemainingKey)
				}
			}
		}

		progress.totalUnitCount     = dataTask.countOfBytesExpectedToReceive
		progress.completedUnitCount = dataTask.countOfBytesReceived
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError downloadError: Error?) {
		extractorFileHandleStorage?.closeFile()
		progress.totalUnitCount = task.countOfBytesReceived

		// `_extractorError ?: (_extractorTask ? downloadError : «unable to launch»)`.
		// The third branch is the case where no byte ever arrived, so the extractor
		// was never asked for and never recorded an error of its own.
		let error = extractorError ?? (extractorTask != nil ? downloadError : NSError(domain: "OakDownloadManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to launch tar."]))

		if let error {
			log.error("Failed to download \(task.originalRequest?.url?.absoluteString ?? "", privacy: .public): \(error.localizedDescription, privacy: .public)")
			completionHandler(nil, error)
		} else if !OakDownloadManager.sharedInstance.data(data, hasValidBase64EncodedSignature: signature, usingPublicKeyString: signee.flatMap { publicKeys[$0] }) {
			log.error("Unable to verify signature")
			completionHandler(nil, NSError(domain: "OakDownloadManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to verify signature."]))
		} else {
			extractorDispatchGroup.notify(queue: .main) {
				let status = self.extractorTask?.terminationStatus ?? -1
				if status == 0 {
					let url = self.temporaryFileURL
					self.temporaryFileURL = nil
					self.completionHandler(url, nil)
				} else {
					let errorString  = (self.extractorTaskErrorData?.isEmpty  == false) ? String(data: self.extractorTaskErrorData!,  encoding: .utf8) : nil
					let outputString = (self.extractorTaskOutputData?.isEmpty == false) ? String(data: self.extractorTaskOutputData!, encoding: .utf8) : nil

					log.error("Abnormal exit from tar: \(status)")
					if let errorString  { log.error("\(errorString, privacy: .public)") }
					if let outputString { log.error("\(outputString, privacy: .public)") }

					var description = errorString ?? outputString ?? "Abnormal exit from tar: \(status)"
					description = description.trimmingCharacters(in: .whitespacesAndNewlines)
					description = description.replacingOccurrences(of: "\n", with: " ")
					self.completionHandler(nil, NSError(domain: "OakDownloadManager", code: 0, userInfo: [NSLocalizedDescriptionKey: description]))
				}
			}
		}
	}
}

// ======================
// = OakDownloadManager =
// ======================

@objc(OakDownloadManager)
class OakDownloadManager: NSObject {
	// nonisolated(unsafe), matching BundleInstallHelper and KEventManager: this is
	// not a MainActor object — -downloadFileAtURL:… runs its completion on a
	// URLSession queue — and the ObjC++ singleton it replaces was a plain
	// function-local static with an unsynchronised lazily-computed ivar. The
	// annotation states that unchanged situation rather than introducing one.
	@objc nonisolated(unsafe) static let sharedInstance = OakDownloadManager()

	private var userAgentStringStorage: String?

	// Computed once and cached, as the ivar-backed getter was. Still settable —
	// the header declares it readwrite and the .mm let the setter be synthesised.
	@objc var userAgentString: String {
		get {
			if let userAgentStringStorage {
				return userAgentStringStorage
			}

			var uuidBytes = [UInt8](repeating: 0, count: 16)
			var wait = timespec()
			gethostuuid(&uuidBytes, &wait)

			let appName    = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? ""
			let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
			let uuid       = NSUUID(uuidBytes: uuidBytes) as UUID

			let osVersion = ProcessInfo.processInfo.operatingSystemVersion

			let res = "\(appName)/\(appVersion)/\(uuid.uuidString) \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)/\(GetHardwareInfo(HW_MACHINE))/\(GetHardwareInfo(HW_MODEL))/\(GetHardwareInfo(HW_NCPU, isInteger: true))"
			userAgentStringStorage = res
			return res
		}
		set { userAgentStringStorage = newValue }
	}

	@objc(downloadFileAtURL:replacingFileAtURL:publicKeys:completionHandler:)
	func downloadFile(at serverURL: URL, replacingFileAt localFileURL: URL, publicKeys: [String: String], completionHandler: @escaping (Bool, Error?) -> Void) {
		var request = URLRequest(url: serverURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
		request.setValue(userAgentString, forHTTPHeaderField: "User-Agent")

		if let entityTag = Self.extendedAttribute("org.w3.http.etag", at: localFileURL) {
			request.setValue(entityTag, forHTTPHeaderField: "If-None-Match")
			log.log("GET \(serverURL.absoluteString, privacy: .public) using entity tag \(entityTag, privacy: .public)")
		}

		let dataTask = URLSession.shared.dataTask(with: request) { data, response, error in
			var error = error
			var wasUpdated = false

			let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
			if error != nil || statusCode != 200 {
				if error == nil && statusCode != 304 {
					error = NSError(domain: "OakDownloadManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Server returned \(statusCode) for \(serverURL.absoluteString)"])
				}
			} else {
				let headers = (response as? HTTPURLResponse)?.allHeaderFields
				let signee    = headers?[OakHTTPHeaderSignee] as? String
				let signature = headers?[OakHTTPHeaderSignature] as? String
				if let signee, let signature {
					if let publicKey = publicKeys[signee] {
						if self.data(data, hasValidBase64EncodedSignature: signature, usingPublicKeyString: publicKey) {
							do {
								try data?.write(to: localFileURL, options: .atomic)
								wasUpdated = true

								if let newETag = headers?["ETag"] as? String {
									if !Self.setExtendedAttribute("org.w3.http.etag", to: newETag, at: localFileURL) {
										log.error("setxattr(\(localFileURL.path, privacy: .public)): \(errno)")
									}
								} else {
									log.error("No ETag: \(serverURL.absoluteString, privacy: .public)")
								}
							} catch let writeError {
								error = writeError
							}
						} else {
							error = NSError(domain: "OakDownloadManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to verify signature."])
						}
					} else {
						error = NSError(domain: "OakDownloadManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to obtain public key for \(signee)."])
					}
				} else {
					error = NSError(domain: "OakDownloadManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing signature"])
				}
			}

			completionHandler(wasUpdated, error)
		}
		dataTask.resume()
	}

	@objc(downloadArchiveAtURL:forReplacingURL:publicKeys:completionHandler:)
	func downloadArchive(at serverURL: URL, forReplacing localURL: URL?, publicKeys: [String: String], completionHandler: @escaping (URL?, Error?) -> Void) -> ProgressReporting {
		return OakDownloadArchiveTask(url: serverURL, forReplacing: localURL, publicKeys: publicKeys, completionHandler: completionHandler)
	}

	// MARK: - Extended attributes

	private static func extendedAttribute(_ name: String, at url: URL) -> String? {
		return url.withUnsafeFileSystemRepresentation { fsr -> String? in
			guard let fsr else { return nil }
			let size = getxattr(fsr, name, nil, 0, 0, 0)
			guard size != -1 else { return nil }

			var buffer = [UInt8](repeating: 0, count: size)
			guard getxattr(fsr, name, &buffer, size, 0, 0) != -1 else { return nil }
			return String(data: Data(buffer), encoding: .utf8)
		}
	}

	private static func setExtendedAttribute(_ name: String, to value: String, at url: URL) -> Bool {
		return url.withUnsafeFileSystemRepresentation { fsr -> Bool in
			guard let fsr else { return false }
			let bytes = Array(value.utf8)
			return setxattr(fsr, name, bytes, bytes.count, 0, 0) != -1
		}
	}

	// MARK: - Signature verification
	//
	// Deprecated SecTransform API, ported unchanged — see the note at the top.

	func signingKey(forPublicKeyString publicKeyString: String) -> SecKey? {
		guard let publicKeyData = publicKeyString.data(using: .utf8) else { return nil }

		var params = SecItemImportExportKeyParameters()
		var type: SecExternalItemType = .itemTypePublicKey
		var format: SecExternalFormat = .formatPEMSequence
		var items: CFArray?

		let err = SecItemImport(publicKeyData as CFData, nil, &format, &type, [], &params, nil, &items)
		guard err == errSecSuccess else {
			if let message = SecCopyErrorMessageString(err, nil) {
				log.error("SecItemImport() failed: \(message as String, privacy: .public)")
			}
			return nil
		}

		guard let items = items as? [AnyObject], let first = items.first else { return nil }
		return (first as! SecKey)
	}

	func data(_ contentData: Data?, hasValidBase64EncodedSignature encodedSignature: String?, usingPublicKeyString publicKeyString: String?) -> Bool {
		guard let encodedSignature, let contentData, let publicKeyString else { return false }

		guard let signatureData = Data(base64Encoded: encodedSignature, options: []) else {
			log.error("Unable to decode signature: \(encodedSignature, privacy: .public)")
			return false
		}

		guard let publicKey = signingKey(forPublicKeyString: publicKeyString) else { return false }

		var err: Unmanaged<CFError>?
		guard let verifier = SecVerifyTransformCreate(publicKey, signatureData as CFData, &err) else {
			log.error("SecVerifyTransformCreate: \(String(describing: err?.takeUnretainedValue()), privacy: .public)")
			return false
		}

		guard SecTransformSetAttribute(verifier, kSecTransformInputAttributeName, contentData as CFData, &err) else {
			log.error("SecTransformSetAttribute: \(String(describing: err?.takeUnretainedValue()), privacy: .public)")
			return false
		}

		let result = SecTransformExecute(verifier, &err)
		if (result as AnyObject) === kCFBooleanTrue {
			return true
		}
		if let err {
			log.error("SecTransformExecute: \(String(describing: err.takeUnretainedValue()), privacy: .public)")
		}
		return false
	}
}
