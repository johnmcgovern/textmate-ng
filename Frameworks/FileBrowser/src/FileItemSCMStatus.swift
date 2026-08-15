import AppKit

// The "scm://" data source: a repository presented as two folders, Uncommitted
// Changes and Untracked Items. SCMStatusFileItem is a FileItem subclass;
// SCMStatusObserver watches the repository and reports the matching URLs.
//
// The scm-map walk that produces those URLs is C++ and lives in
// FileItemSCMStatusSupport (ObjC++); everything here uses the C++-free SCMManager
// API. Both classes are reached only dynamically (the registry resolves
// SCMStatusFileItem via NSClassFromString; the observer via
// +makeObserverForURL:usingBlock:), so neither needs a hand-written header.

@objc(SCMStatusObserver)
final class SCMStatusObserver: NSObject {
	private var scmObserver: Any?

	@objc(initWithURL:usingBlock:)
	init(URL url: NSURL, usingBlock handler: @escaping ([URL]) -> Void) {
		super.init()

		let repositoryURL = NSURL(fileURLWithPath: url.path ?? "", isDirectory: true) as URL
		if url.query?.hasSuffix("unstaged") == true {
			scmObserver = SCMManager.sharedInstance.addObserverToRepository(at: repositoryURL) { repository in
				handler(FileItemSCMStatusSupport.unstagedURLs(in: repository))
			}
		} else if url.query?.hasSuffix("untracked") == true {
			scmObserver = SCMManager.sharedInstance.addObserverToRepository(at: repositoryURL) { repository in
				handler(FileItemSCMStatusSupport.untrackedURLs(in: repository))
			}
		} else if let repository = SCMManager.sharedInstance.repository(at: repositoryURL), repository.enabled {
			let encoded = repository.url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
			handler([
				URL(string: "scm://localhost\(encoded)/?show=unstaged")!,
				URL(string: "scm://localhost\(encoded)/?show=untracked")!,
			])
		}
	}

	deinit {
		if let scmObserver {
			SCMManager.sharedInstance.removeObserver(scmObserver)
		}
	}
}

@objc(SCMStatusFileItem)
final class SCMStatusFileItem: FileItem {
	private var repository: SCMRepository?
	private var observer: Any?

	@MainActor
	@objc(makeObserverForURL:usingBlock:)
	override class func makeObserver(forURL url: NSURL, usingBlock handler: @escaping ([URL]) -> Void) -> Any? {
		return SCMStatusObserver(URL: url, usingBlock: handler)
	}

	required init(URL url: NSURL) {
		super.init(URL: url)

		repository = SCMManager.sharedInstance.repository(at: NSURL(fileURLWithPath: url.path ?? "", isDirectory: true) as URL)
		if let repository, !repository.enabled {
			disambiguationSuffix = " (disabled)"
		} else if URL.query?.hasSuffix("unstaged") != true && URL.query?.hasSuffix("untracked") != true {
			if let repository {
				observer = SCMManager.sharedInstance.addObserverToRepository(at: repository.url) { [weak self] _ in
					self?.updateBranchName()
				}
			} else {
				disambiguationSuffix = " (no status)"
			}
		}
	}

	deinit {
		if let observer {
			SCMManager.sharedInstance.removeObserver(observer)
		}
	}

	@objc func updateBranchName() {
		if let repository {
			let branch = repository.variables["TM_SCM_BRANCH"]
			disambiguationSuffix = branch != nil ? " (\(branch!))" : ""
		}
	}

	override var localizedName: String! {
		get {
			if URL.query?.hasSuffix("unstaged") == true {
				return "Uncommitted Changes"
			} else if URL.query?.hasSuffix("untracked") == true {
				return "Untracked Items"
			} else if let repository {
				return FileManager.default.displayName(atPath: repository.url.path)
			}
			return super.localizedName
		}
		set { super.localizedName = newValue }
	}

	override var parentURL: NSURL? {
		if URL.query?.hasSuffix("unstaged") == true || URL.query?.hasSuffix("untracked") == true {
			let encoded = URL.path?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
			return NSURL(string: "scm://localhost\(encoded)/")
		}
		return NSURL(fileURLWithPath: URL.path ?? "")
	}
}
