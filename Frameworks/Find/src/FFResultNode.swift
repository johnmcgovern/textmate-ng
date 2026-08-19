import AppKit

// The model behind the find results outline view: a root, one branch per file,
// one leaf per match.
//
// FFResultNode.h stays hand-written, so no consumer changed — the pattern
// TMFileReference established. It is deliberately absent from
// Find-Bridging-Header.h: it declares this class, and importing it would give
// the class two declarations.
//
// The C++ half — path strings, match excerpts, and the text::pos_t arithmetic
// behind lineSpan — lives in FFResultNodeSupport.mm. None of it is reachable
// from Swift and none of it is stateful.

@objc(FFResultNode)
class FFResultNode: NSObject {

	// Weak, as in the ObjC++: a parent owns its children through `children`, and
	// a two-way strong link would retain the whole tree forever.
	@objc weak var parent: FFResultNode?

	@objc private(set) var match: OakDocumentMatch?

	@objc dynamic var replaceString: String?
	@objc dynamic var displayPath: NSAttributedString?

	private var storedChildren: NSMutableArray?
	private var cachedExcerpt: NSAttributedString?
	private var cachedReplaceString: String?

	private var leafs: UInt = 0
	private var excluded_: UInt = 0
	private var readOnly_: UInt = 0
	private var excludedReadOnly_: UInt = 0

	private init(match: OakDocumentMatch?) {
		self.match = match
		super.init()
	}

	// The root is built with `[FFResultNode new]` (Find.swift's -clearMatches) — no match, no
	// children, counting nothing. Swift does not inherit -init once another
	// initializer exists, so this has to be spelled out or every search dies at
	// "unimplemented initializer".
	@objc override init() {
		super.init()
	}

	// =================
	// = Construction  =
	// =================

	// A file row. `children` is set up front, which is what makes it a branch
	// counting nothing rather than a leaf counting itself.
	@objc(resultNodeWithMatch:baseDirectory:)
	static func resultNode(with aMatch: OakDocumentMatch?, baseDirectory base: String?) -> FFResultNode {
		let res = FFResultNode(match: aMatch)
		res.storedChildren = NSMutableArray()
		let path = (base != nil && aMatch?.document?.path != nil) ? aMatch?.document?.path : aMatch?.document?.displayName
		res.displayPath = FFPathComponentString(path, base, NSFont.controlContentFont(ofSize: 0))
		return res
	}

	// A match row.
	@objc(resultNodeWithMatch:)
	static func resultNode(with aMatch: OakDocumentMatch?) -> FFResultNode {
		let res = FFResultNode(match: aMatch)
		res.countOfLeafs = 1
		return res
	}

	// ==============================================================
	// = The four counters, maintained incrementally up the tree     =
	// ==============================================================

	// Each setter pushes its own delta into the parent; nothing is ever
	// recomputed from the tree. Two things this port has to preserve exactly:
	//
	//  - `&+` / `&-` are load-bearing, not defensive. Converting a leaf into a
	//    branch (see addResultNode) sets a count of 1 to 0, so the delta handed
	//    to the parent is `0 - 1` — an NSUInteger wraparound in the ObjC++ that
	//    lands back on the right total when the parent adds it. Swift's `UInt`
	//    traps on the plain operators, so `-` here is a crash on the second
	//    match in a file, from a build that compiles clean.
	//  - The parent is updated *before* self, as in the ObjC++. Nothing reads
	//    back across the two today, so this is fidelity rather than necessity —
	//    but the ordering is free to keep and not free to rediscover.
	@objc private(set) var countOfLeafs: UInt {
		get { leafs }
		set {
			guard newValue != leafs else { return }
			if let parent { parent.countOfLeafs = parent.countOfLeafs &+ (newValue &- leafs) }
			leafs = newValue
		}
	}

	@objc private(set) var countOfExcluded: UInt {
		get { excluded_ }
		set {
			guard newValue != excluded_ else { return }
			if let parent { parent.countOfExcluded = parent.countOfExcluded &+ (newValue &- excluded_) }
			excluded_ = newValue
		}
	}

	@objc private(set) var countOfReadOnly: UInt {
		get { readOnly_ }
		set {
			guard newValue != readOnly_ else { return }
			if let parent { parent.countOfReadOnly = parent.countOfReadOnly &+ (newValue &- readOnly_) }
			readOnly_ = newValue
		}
	}

	@objc private(set) var countOfExcludedReadOnly: UInt {
		get { excludedReadOnly_ }
		set {
			guard newValue != excludedReadOnly_ else { return }
			if let parent { parent.countOfExcludedReadOnly = parent.countOfExcludedReadOnly &+ (newValue &- excludedReadOnly_) }
			excludedReadOnly_ = newValue
		}
	}

	// ==========
	// = Tree   =
	// ==========

	// Returns the live NSMutableArray, not a copy: FFResultsViewController and
	// -removeFromParent both mutate through this property, and an ObjC caster
	// (`(NSMutableArray*)node.children`) has to reach the same object the ObjC++
	// gave it.
	@objc var children: NSArray? {
		get { storedChildren }
		set {
			if let mutable = newValue as? NSMutableArray {
				storedChildren = mutable
			} else if let newValue {
				storedChildren = NSMutableArray(array: newValue as! [Any])
			} else {
				storedChildren = nil
			}
		}
	}

	@objc(addResultNode:)
	func addResultNode(_ aMatch: FFResultNode) {
		if storedChildren == nil {
			storedChildren = NSMutableArray()
			// This node stops counting itself as it starts counting children.
			if leafs != 0 {
				countOfLeafs = countOfLeafs &- 1
			}
		}

		aMatch.parent = self

		storedChildren?.add(aMatch)
		countOfLeafs            = countOfLeafs            &+ aMatch.countOfLeafs
		countOfExcluded         = countOfExcluded         &+ aMatch.countOfExcluded
		countOfReadOnly         = countOfReadOnly         &+ aMatch.countOfReadOnly
		countOfExcludedReadOnly = countOfExcludedReadOnly &+ aMatch.countOfExcludedReadOnly
	}

	@objc func removeFromParent() {
		(parent?.children as? NSMutableArray)?.remove(self)
		guard let parent else { return }
		parent.countOfExcludedReadOnly = parent.countOfExcludedReadOnly &- excludedReadOnly_
		parent.countOfReadOnly         = parent.countOfReadOnly         &- readOnly_
		parent.countOfExcluded         = parent.countOfExcluded         &- excluded_
		parent.countOfLeafs            = parent.countOfLeafs            &- leafs
	}

	@objc var firstResultNode: FFResultNode? { storedChildren?.firstObject as? FFResultNode }
	@objc var lastResultNode: FFResultNode? { storedChildren?.lastObject as? FFResultNode }

	// ===========================================
	// = excluded / readOnly, derived not stored =
	// ===========================================

	// A leaf compares its own count against 1; a branch against its leaf total.
	// A branch whose children have all been removed therefore compares 0 to 0
	// and reports itself excluded — pinned by test, and the reason `children` is
	// an optional here rather than an always-present empty array.
	@objc dynamic var excluded: Bool {
		get { excluded_ == (storedChildren != nil ? leafs : 1) }
		set {
			if let children = storedChildren {
				// Read-only children are skipped: excluding a file that cannot be
				// written is meaningless and would leave the branch permanently mixed.
				for case let child as FFResultNode in children where !child.readOnly {
					child.excluded = newValue
				}
			} else {
				countOfExcluded         = newValue ? 1 : 0
				countOfExcludedReadOnly = (newValue && readOnly_ != 0) ? 1 : 0
			}
		}
	}

	// `getter = isReadOnly` on a *readwrite* property — the accessors are
	// annotated individually because `@objc(isReadOnly)` on the property itself
	// renames the setter to `setIsReadOnly:`, which is the OakTabItem crash
	// recorded in PROJECT_PHASES.md.
	@objc dynamic var readOnly: Bool {
		@objc(isReadOnly) get { readOnly_ == (storedChildren != nil ? leafs : 1) }
		@objc(setReadOnly:) set {
			if let children = storedChildren {
				for case let child as FFResultNode in children {
					child.readOnly = newValue
				}
			} else {
				countOfReadOnly         = newValue ? 1 : 0
				// Note the asymmetry with -setExcluded: above, which reads the
				// read-only *count*. This one reads the derived `excluded`.
				countOfExcludedReadOnly = (newValue && excluded) ? 1 : 0
			}
		}
	}

	// ==================
	// = Match-derived  =
	// ==================

	@objc var document: OakDocument? { match?.document }
	@objc var path: String? { match?.document?.path }

	@objc var lineSpan: UInt {
		guard let match else { return 0 }
		return FFLineSpanForMatch(match)
	}

	// Cached because the outline view asks for it on every row redraw. The ObjC++
	// compared the replacement by pointer *or* -isEqualToString:; Swift's `==` on
	// String? is the same test, nil included.
	@objc(excerptWithReplacement:font:)
	func excerpt(withReplacement replacementString: String?, font: NSFont?) -> NSAttributedString? {
		if let cachedExcerpt, replacementString == cachedReplaceString {
			return cachedExcerpt
		}

		guard let match else { return nil }
		let res = FFExcerptForMatch(match, replacementString, font)
		cachedExcerpt = res
		cachedReplaceString = replacementString
		return res
	}
}
