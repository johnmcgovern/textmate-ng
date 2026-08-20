import AppKit

// Ported from OakPasteboard.mm (2026-08-20). Its C++ was extracted first, over four
// commits: the exported constants (OakPasteboardConstants), the SQLite store
// (OakPasteboardDatabase), the run-loop idle observer (OakPasteboardIdleObserver) and
// -findOptions (the OakPasteboardEntryFindOptions category). This file is the
// translation of what was left — the model, the history queries and the
// system-pasteboard bookkeeping.
//
// Not @MainActor: it is the same synchronous, main-thread-only object the ObjC++ was
// (its callers are all UI, its idle callback fires on the main run loop), and its
// three instances are permanent singletons that never deinit. NSApp is the one
// main-actor read, wrapped where it happens.
//
// The @objc(…) names are load-bearing: t_pasteboard.mm pins the selector surface
// (rule 18) and ObjC++ consumers (OakTextView, clipboard.mm, AppController, the
// chooser) call these selectors, while Swift consumers (Find.swift,
// DocumentWindowController.swift) use the trimmed Swift spellings (.find, .current(),
// .addEntry(with:…)). Both have to keep working.

// The clipboard-history and pasteboard-type names that were file-static in
// OakPasteboard.mm and used only here.
private let OakReplacePboard                             = "OakReplacePboard"
private let OakPasteboardOptionsPboardType               = "OakPasteboardOptionsPboardType"
private let kUserDefaultsClipboardHistoryKeepAtLeast     = "clipboardHistoryKeepAtLeast"
private let kUserDefaultsClipboardHistoryKeepAtMost      = "clipboardHistoryKeepAtMost"
private let kUserDefaultsClipboardHistoryDaysToKeep      = "clipboardHistoryDaysToKeep"

private let kLogSQLite = OSLog(subsystem: "Pasteboard", category: "sqlite")

// The store returns an NSArray whose shape depends on the query (rule 6, preserved):
// rows for a single row-returning statement, an array of those for several. These keep
// the call sites reading the way the ObjC++ did (`… .firstObject`, `for row in …`).
private extension OakPasteboardDatabase {
	func rows(_ query: String, _ variables: [String: Any] = [:]) -> [[AnyHashable: Any]] {
		(executeQuery(query, variables: variables) as? [[AnyHashable: Any]]) ?? []
	}
	func firstRow(_ query: String, _ variables: [String: Any] = [:]) -> [AnyHashable: Any]? {
		rows(query, variables).first
	}
}

// The `options` BLOB is a binary property list of an NSDictionary, as it was in the
// ObjC++ (rule 6). A free function keeps the `try?` and the cast off one line, which
// the type checker could not untangle inline.
private func plistDictionary(from value: Any?) -> [AnyHashable: Any]? {
	guard let data = value as? Data else { return nil }
	var format = PropertyListSerialization.PropertyListFormat.binary
	// ReadOptions imports as Int here; 0 is NSPropertyListImmutable, as the ObjC++ used.
	guard let plist = try? PropertyListSerialization.propertyList(from: data, options: 0, format: &format) else { return nil }
	return plist as? [AnyHashable: Any]
}

@objc(OakPasteboardEntry)
class OakPasteboardEntry: NSObject {
	@objc(strings) let strings: [String]
	@objc(options) let options: [AnyHashable: Any]
	private var flaggedValue: Bool

	init(strings: [String], options: [AnyHashable: Any]?, flagged: Bool) {
		self.strings = strings
		self.options = options ?? [:]
		self.flaggedValue = flagged
		super.init()
	}

	@objc(string) var string: String {
		strings.joined(separator: "\n")
	}

	@objc(historyId) var historyId: Int {
		(options["historyId"] as? NSNumber)?.intValue ?? 0
	}

	// getter=isFlagged / setter=setFlagged: — two methods rather than a property,
	// because Swift cannot give a property that asymmetric selector pair (rule 4). The
	// hand-written header declares the property; these answer its selectors.
	@objc(isFlagged) func isFlagged() -> Bool {
		flaggedValue
	}

	@objc(setFlagged:) func setFlagged(_ newFlagged: Bool) {
		flaggedValue = newFlagged
		let historyId = self.historyId
		if historyId != 0 {
			let query = flaggedValue ? "INSERT INTO flags (id) VALUES (:historyId);" : "DELETE FROM flags WHERE id = :historyId;"
			_ = OakPasteboardDatabase.sharedInstance().executeQuery(query, variables: [":historyId": historyId])
		}
	}

	@objc(fullWordMatch)     var fullWordMatch: Bool     { (options[OakFindFullWordsOption] as? NSNumber)?.boolValue ?? false }
	@objc(ignoreWhitespace)  var ignoreWhitespace: Bool  { (options[OakFindIgnoreWhitespaceOption] as? NSNumber)?.boolValue ?? false }
	@objc(regularExpression) var regularExpression: Bool { (options[OakFindRegularExpressionOption] as? NSNumber)?.boolValue ?? false }
	// -findOptions is the OakPasteboardEntryFindOptions category (ObjC++, find::options_t).

	override func isEqual(_ object: Any?) -> Bool {
		guard let other = object as? OakPasteboardEntry else { return false }
		return historyId == other.historyId
	}

	override var hash: Int { historyId }

	override var description: String {
		"<\(type(of: self)): \(strings.joined(separator: "|")) [\(options.keys.map { "\($0)" }.joined(separator: "|"))]>"
	}
}

@objc(OakPasteboard)
class OakPasteboard: NSObject, OakPasteboardIdleObserving {
	@objc(name) let name: String
	private let pasteboard: NSPasteboard
	private let avoidsDuplicates: Bool
	private var changeCount: Int = 0

	private init(name: String, systemPasteboard pboard: NSPasteboard, avoidsDuplicates flag: Bool) {
		self.name = name
		self.pasteboard = pboard
		self.avoidsDuplicates = flag
		super.init()
	}

	// +initialize's work: register the history defaults and start/stop the idle
	// observer with app activation, once. A Swift class has no +initialize (rule 20),
	// so a lazy static runs it the first time a pasteboard is asked for.
	private static let registerOnce: Void = {
		UserDefaults.standard.register(defaults: [
			kUserDefaultsClipboardHistoryKeepAtLeast: 25,
			kUserDefaultsClipboardHistoryKeepAtMost:  500,
			kUserDefaultsClipboardHistoryDaysToKeep:  30,
		])
		// object: nil, not NSApp — only NSApp posts these, and reading NSApp from this
		// nonisolated static would be a cross-actor access.
		NotificationCenter.default.addObserver(OakPasteboard.self, selector: #selector(applicationDidBecomeActiveNotification(_:)), name: NSApplication.didBecomeActiveNotification, object: nil)
		NotificationCenter.default.addObserver(OakPasteboard.self, selector: #selector(applicationDidResignActiveNotification(_:)), name: NSApplication.didResignActiveNotification, object: nil)
	}()

	@objc private static func applicationDidBecomeActiveNotification(_ sender: Any?) {
		OakPasteboardIdleObserver.sharedInstance().start()
	}

	@objc private static func applicationDidResignActiveNotification(_ sender: Any?) {
		OakPasteboardIdleObserver.sharedInstance().stop()
	}

	// Main-thread-only, as the ObjC++ static NSMutableDictionary was (rule 26).
	nonisolated(unsafe) private static var sharedInstances: [String: OakPasteboard] = [:]

	private static func pasteboard(name: String, systemPasteboard pboard: NSPasteboard, avoidsDuplicates flag: Bool) -> OakPasteboard {
		_ = registerOnce
		if let existing = sharedInstances[name] {
			return existing
		}
		let res = OakPasteboard(name: name, systemPasteboard: pboard, avoidsDuplicates: flag)
		sharedInstances[name] = res
		OakPasteboardIdleObserver.sharedInstance().addObject(res)
		return res
	}

	@objc(generalPasteboard) static var general: OakPasteboard { pasteboard(name: "General", systemPasteboard: NSPasteboard(name: .general), avoidsDuplicates: false) }
	@objc(findPasteboard)    static var find: OakPasteboard    { pasteboard(name: "Find",    systemPasteboard: NSPasteboard(name: .find),    avoidsDuplicates: true) }
	@objc(replacePasteboard) static var replace: OakPasteboard { pasteboard(name: "Replace", systemPasteboard: NSPasteboard(name: NSPasteboard.Name(OakReplacePboard)), avoidsDuplicates: true) }

	private func ensurePasteboardItemIsInDatabase() {
		if pasteboard.availableType(from: [NSPasteboard.PasteboardType(OakPasteboardOptionsPboardType)]) != nil {
			// Already in database, but check that historyId is valid
			let options = pasteboard.propertyList(forType: NSPasteboard.PasteboardType(OakPasteboardOptionsPboardType)) as? [AnyHashable: Any]
			if let historyId = options?["historyId"] as? NSNumber {
				if OakPasteboardDatabase.sharedInstance().firstRow("SELECT id FROM history WHERE id = :history_id", [":history_id": historyId]) != nil {
					return
				}
			}
		}

		// Do not add these types to database, see http://nspasteboard.org
		if pasteboard.availableType(from: [NSPasteboard.PasteboardType("org.nspasteboard.TransientType"), NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"), NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")]) != nil {
			return
		}

		let strings = (pasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [String]) ?? []
		if strings.isEmpty {
			os_log("No strings on %{public}@ pasteboard. Available types: %{public}@", log: OSLog(subsystem: "Pasteboard", category: "history"), name as NSString, pasteboard.types ?? [])
			return
		}

		if let lastEntry = lastEntry, lastEntry.strings == strings {
			return
		}

		if changeCount == pasteboard.changeCount {
			os_log("New content on %{public}@ pasteboard with stale change count (%lu): %{public}@", log: OSLog(subsystem: "Pasteboard", category: "history"), type: .error, name as NSString, pasteboard.changeCount, strings.joined())
		}

		_ = addEntry(withStrings: strings, options: nil)
	}

	@objc(updatePasteboardWithEntry:)
	func updatePasteboard(with pasteboardEntry: OakPasteboardEntry?) {
		changeCount = pasteboard.clearContents()

		if let pasteboardEntry = pasteboardEntry {
			pasteboard.writeObjects(pasteboardEntry.strings as [NSString])
			pasteboard.setPropertyList(pasteboardEntry.options, forType: NSPasteboard.PasteboardType(OakPasteboardOptionsPboardType))
		}

		NotificationCenter.default.post(name: NSNotification.Name.OakPasteboardDidChange, object: self)
	}

	@objc(updatePasteboardWithEntries:)
	func updatePasteboard(withEntries pasteboardEntries: [OakPasteboardEntry]) {
		let historyIds = pasteboardEntries.map { $0.historyId }
		var options: [AnyHashable: Any] = ["historyIds": historyIds]

		let strings = pasteboardEntries.flatMap { $0.strings }
		let string: String
		if self.isEqual(OakPasteboard.find) {
			string = strings.joined(separator: "|")
			options[OakFindRegularExpressionOption] = true
		} else {
			string = strings.joined(separator: "\n")
		}

		pasteboard.declareTypes([.string, NSPasteboard.PasteboardType(OakPasteboardOptionsPboardType), NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")], owner: nil)
		pasteboard.setString(string, forType: .string)
		pasteboard.setPropertyList(options, forType: NSPasteboard.PasteboardType(OakPasteboardOptionsPboardType))
		pasteboard.setPropertyList(true, forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))

		changeCount = pasteboard.changeCount

		NotificationCenter.default.post(name: NSNotification.Name.OakPasteboardDidChange, object: self)
	}

	@objc(currentEntry) var currentEntry: OakPasteboardEntry? {
		ensurePasteboardItemIsInDatabase()

		let strings = (pasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [String]) ?? []
		var options = pasteboard.propertyList(forType: NSPasteboard.PasteboardType(OakPasteboardOptionsPboardType)) as? [AnyHashable: Any]
		if options == nil, lastEntry?.strings == strings {
			options = lastEntry?.options
		}
		return strings.isEmpty ? nil : OakPasteboardEntry(strings: strings, options: options, flagged: false)
	}

	private func fetchEntry(withHistoryId historyId: Int) -> OakPasteboardEntry? {
		if historyId == 0 {
			return nil
		}

		let query = "SELECT options, flags.id AS flagged, string FROM history LEFT JOIN flags USING (id) LEFT JOIN groups ON history.id = history_id LEFT JOIN strings ON strings.id = string_id WHERE history.id = :history_id AND string IS NOT NULL;"
		let rows = OakPasteboardDatabase.sharedInstance().rows(query, [":history_id": historyId])
		let strings = rows.compactMap { $0["string"] as? String }

		var options: [AnyHashable: Any] = ["historyId": historyId]
		if let plist = plistDictionary(from: rows.first?["options"]) {
			options.merge(plist) { _, new in new }
		}

		return OakPasteboardEntry(strings: strings, options: options, flagged: rows.first?["flagged"] != nil)
	}

	@objc(entries)
	func entries() -> [OakPasteboardEntry] {
		var res: [OakPasteboardEntry] = []

		// The ObjC++ held each entry's strings array by reference and appended
		// same-history_id rows to it as they arrived; OakPasteboardEntry.strings is an
		// immutable Swift value, so a group is accumulated and finalised before the
		// entry is built. Rows are ordered so a history_id's rows are contiguous.
		var groupHistoryId: NSNumber?
		var groupStrings: [String] = []
		var groupOptions: [AnyHashable: Any] = [:]
		var groupFlagged = false

		func flush() {
			if groupHistoryId != nil {
				res.append(OakPasteboardEntry(strings: groupStrings, options: groupOptions, flagged: groupFlagged))
			}
		}

		let query = "SELECT history.id AS history_id, options, flags.id AS flagged, string FROM history LEFT JOIN clipboards ON clipboards.id = clipboard_id LEFT JOIN flags USING (id) LEFT JOIN groups ON history.id = history_id LEFT JOIN strings ON strings.id = string_id WHERE name = :name ORDER BY history.id DESC;"
		for row in OakPasteboardDatabase.sharedInstance().rows(query, [":name": name]) {
			let historyId = row["history_id"] as? NSNumber
			if groupHistoryId != nil, historyId == groupHistoryId {
				if let string = row["string"] as? String {
					groupStrings.append(string)
				}
			} else {
				flush()
				groupHistoryId = historyId
				groupStrings = (row["string"] as? String).map { [$0] } ?? []
				groupOptions = ["historyId": historyId ?? 0]
				if let plist = plistDictionary(from: row["options"]) {
					groupOptions.merge(plist) { _, new in new }
				}
				groupFlagged = row["flagged"] != nil
			}
		}
		flush()

		return res
	}

	private var firstEntry: OakPasteboardEntry? {
		let query = "SELECT MIN(history.id) AS history_id FROM history LEFT JOIN clipboards ON clipboards.id = clipboard_id WHERE name = :name;"
		if let row = OakPasteboardDatabase.sharedInstance().firstRow(query, [":name": name]) {
			return fetchEntry(withHistoryId: (row["history_id"] as? NSNumber)?.intValue ?? 0)
		}
		return nil
	}

	private var lastEntry: OakPasteboardEntry? {
		let query = "SELECT MAX(history.id) AS history_id FROM history LEFT JOIN clipboards ON clipboards.id = clipboard_id WHERE name = :name;"
		if let row = OakPasteboardDatabase.sharedInstance().firstRow(query, [":name": name]) {
			return fetchEntry(withHistoryId: (row["history_id"] as? NSNumber)?.intValue ?? 0)
		}
		return nil
	}

	private func entryBefore(_ laterEntry: OakPasteboardEntry) -> OakPasteboardEntry? {
		let query = "SELECT MAX(history.id) AS history_id FROM history LEFT JOIN clipboards ON clipboards.id = clipboard_id WHERE history.id < :history_id AND name = :name;"
		if let row = OakPasteboardDatabase.sharedInstance().firstRow(query, [":name": name, ":history_id": laterEntry.historyId]) {
			return fetchEntry(withHistoryId: (row["history_id"] as? NSNumber)?.intValue ?? 0)
		}
		return nil
	}

	private func entryAfter(_ earlierEntry: OakPasteboardEntry) -> OakPasteboardEntry? {
		let query = "SELECT MIN(history.id) AS history_id FROM history LEFT JOIN clipboards ON clipboards.id = clipboard_id WHERE history.id > :history_id AND name = :name;"
		if let row = OakPasteboardDatabase.sharedInstance().firstRow(query, [":name": name, ":history_id": earlierEntry.historyId]) {
			return fetchEntry(withHistoryId: (row["history_id"] as? NSNumber)?.intValue ?? 0)
		}
		return nil
	}

	@objc(addEntryWithStrings:options:)
	@discardableResult
	func addEntry(withStrings someStrings: [String], options someOptions: [AnyHashable: Any]?) -> OakPasteboardEntry? {
		if someStrings.isEmpty {
			os_log("Adding empty array in [%{public}@ addEntryWithStrings:options:updatePasteboard:]", log: OSLog(subsystem: "Pasteboard", category: "history"), type: .error, "\(type(of: self))")
			return nil
		}

		// Drop option keys whose value is a boolean NO, keep the rest (the ObjC++
		// keysOfEntriesPassingTest).
		var options: [AnyHashable: Any] = [:]
		for (key, value) in (someOptions ?? [:]) {
			if let number = value as? NSNumber, number.boolValue == false { continue }
			options[key] = value
		}

		var stringIds: [Any] = []
		var values: [String] = []
		for str in someStrings {
			let query = "INSERT INTO strings ('string') VALUES (:string); SELECT id FROM strings WHERE string = :string;"
			if let row = OakPasteboardDatabase.sharedInstance().firstRow(query, [":string": str]), let stringId = row["id"] {
				stringIds.append(stringId)
				values.append("((SELECT seq FROM sqlite_sequence WHERE name = 'history'), \(stringId))")
			}
		}

		// NSNull binds NULL, as the store's absent/nil case does (rule 6).
		let optionsData = options.isEmpty ? nil : try? PropertyListSerialization.data(fromPropertyList: options, format: .binary, options: 0)
		let variables: [String: Any] = [":name": name, ":options": (optionsData ?? NSNull())]

		let stringIdList = stringIds.map { "\($0)" }.joined(separator: ", ")

		var isFlagged = false
		if avoidsDuplicates {
			let query = "SELECT COUNT(*) AS flagCount FROM (SELECT history_id, COUNT(*) AS count FROM history LEFT JOIN flags USING (id) LEFT JOIN groups ON history_id = history.id LEFT JOIN clipboards ON clipboard_id = clipboards.id LEFT JOIN strings ON strings.id = string_id WHERE name = :name AND string_id IN (\(stringIdList)) AND flags.id IS NOT NULL GROUP BY history_id HAVING count = \(stringIds.count));"
			if let res = OakPasteboardDatabase.sharedInstance().firstRow(query, variables) {
				isFlagged = (res["flagCount"] as? NSNumber)?.intValue ?? 0 != 0
			}
		}

		// text::format's %s substitution, as Swift interpolation.
		let deleteQuery = avoidsDuplicates ? "DELETE FROM history WHERE id IN (SELECT history_id FROM (SELECT history_id, COUNT(*) AS count FROM groups LEFT JOIN history ON history_id = history.id LEFT JOIN clipboards ON clipboard_id = clipboards.id LEFT JOIN strings ON string_id = strings.id WHERE name = :name AND string_id IN (\(stringIdList)) GROUP BY history_id HAVING count = \(stringIds.count)));" : ""
		let flagQuery = isFlagged ? "INSERT INTO flags (id) VALUES (LAST_INSERT_ROWID());" : ""
		let query = "BEGIN TRANSACTION;INSERT INTO clipboards ('name') VALUES (:name);\(deleteQuery)INSERT INTO history ('options', 'clipboard_id') SELECT :options, id FROM clipboards WHERE name = :name;SELECT LAST_INSERT_ROWID() AS history_id;\(flagQuery)INSERT INTO groups ('history_id', 'string_id') VALUES \(values.joined(separator: ","));END TRANSACTION;"

		if let res = OakPasteboardDatabase.sharedInstance().firstRow(query, variables), let historyId = res["history_id"] {
			options["historyId"] = historyId
		}

		pruneHistory(self)

		return OakPasteboardEntry(strings: someStrings, options: options, flagged: false)
	}

	@objc(addEntryWithString:options:)
	func addEntry(with string: String, options someOptions: [AnyHashable: Any]?) {
		if let entry = addEntry(withStrings: [string], options: someOptions) {
			updatePasteboard(with: entry)
		}
	}

	@objc(addEntryWithString:)
	func addEntry(with string: String) {
		addEntry(with: string, options: nil)
	}

	@objc(removeEntries:)
	func removeEntries(_ pasteboardEntries: [OakPasteboardEntry]) {
		guard !pasteboardEntries.isEmpty else { return }

		let historyIds = pasteboardEntries.map { $0.historyId }
		let query = "DELETE FROM history WHERE id IN (\(historyIds.map { "\($0)" }.joined(separator: ", ")));"
		_ = OakPasteboardDatabase.sharedInstance().executeQuery(query)

		if pasteboard.availableType(from: [NSPasteboard.PasteboardType(OakPasteboardOptionsPboardType)]) != nil {
			let options = pasteboard.propertyList(forType: NSPasteboard.PasteboardType(OakPasteboardOptionsPboardType)) as? [AnyHashable: Any]
			if let historyId = options?["historyId"] as? NSNumber, historyIds.contains(historyId.intValue) {
				let strings = (pasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [String]) ?? []
				var mutableOptions = options ?? [:]
				mutableOptions.removeValue(forKey: "historyId")

				changeCount = pasteboard.clearContents()
				pasteboard.writeObjects(strings as [NSString])
				pasteboard.setPropertyList(mutableOptions, forType: NSPasteboard.PasteboardType(OakPasteboardOptionsPboardType))
			}
		}
	}

	@objc(removeAllEntries)
	func removeAllEntries() {
		let query = "DELETE FROM history WHERE clipboard_id = (SELECT id FROM clipboards WHERE name = :name) AND id NOT IN (SELECT id FROM flags);"
		_ = OakPasteboardDatabase.sharedInstance().executeQuery(query, variables: [":name": name])
	}

	func checkForExternalPasteboardChanges() {
		// Do not touch clipboard unless we are active as CFPasteboardCopyData can stall.
		// This fires from the main run loop's idle observer, so the NSApp read is on the
		// main actor.
		guard MainActor.assumeIsolated({ NSApp.isActive }) else { return }

		if changeCount != pasteboard.changeCount {
			ensurePasteboardItemIsInDatabase()
			changeCount = pasteboard.changeCount
			NotificationCenter.default.post(name: NSNotification.Name.OakPasteboardDidChange, object: self)
		}
	}

	private func pruneHistory(_ sender: Any?) {
		let keepAtLeast = UserDefaults.standard.integer(forKey: kUserDefaultsClipboardHistoryKeepAtLeast)
		let keepAtMost  = UserDefaults.standard.integer(forKey: kUserDefaultsClipboardHistoryKeepAtMost)
		let daysToKeep  = CGFloat(UserDefaults.standard.float(forKey: kUserDefaultsClipboardHistoryDaysToKeep))

		guard let row = OakPasteboardDatabase.sharedInstance().firstRow("SELECT COUNT(*) AS count FROM history LEFT JOIN flags USING (id) LEFT JOIN clipboards ON clipboards.id = clipboard_id WHERE flags.id IS NULL AND name = :name", [":name": name]) else { return }
		let count = (row["count"] as? NSNumber)?.intValue ?? 0

		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "YYYY-MM-dd HH:mm:ss"
		dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
		var keepUntil = "\"\(dateFormatter.string(from: Date(timeIntervalSinceNow: -daysToKeep * 24 * 60 * 60)))\""

		if keepAtLeast != 0, keepAtLeast <= count {
			let query = "SELECT date FROM history LEFT JOIN flags USING (id) LEFT JOIN clipboards ON clipboards.id = clipboard_id WHERE flags.id IS NULL AND name = :name ORDER BY history.id LIMIT :offset, 1;"
			if let row = OakPasteboardDatabase.sharedInstance().firstRow(query, [":name": name, ":offset": count - keepAtLeast]), let date = row["date"] {
				keepUntil = "MIN(\"\(date)\", \(keepUntil))"
			}
		}

		if keepAtMost != 0, keepAtMost <= count {
			let query = "SELECT date FROM history LEFT JOIN flags USING (id) LEFT JOIN clipboards ON clipboards.id = clipboard_id WHERE flags.id IS NULL AND name = :name ORDER BY history.id LIMIT :offset, 1;"
			if let row = OakPasteboardDatabase.sharedInstance().firstRow(query, [":name": name, ":offset": count - keepAtMost]), let date = row["date"] {
				keepUntil = "MAX(\"\(date)\", \(keepUntil))"
			}
		}

		let query = "SELECT COUNT(*) AS count FROM history LEFT JOIN flags USING (id) WHERE date < \(keepUntil) AND flags.id IS NULL AND clipboard_id = (SELECT id FROM clipboards WHERE name = :name);DELETE FROM history WHERE id IN (SELECT history.id FROM history LEFT JOIN flags USING (id) WHERE date < \(keepUntil) AND flags.id IS NULL AND clipboard_id = (SELECT id FROM clipboards WHERE name = :name));SELECT COUNT(*) AS count FROM strings LEFT JOIN groups ON string_id = strings.id WHERE string_id IS NULL;DELETE FROM strings WHERE id IN (SELECT strings.id FROM strings LEFT JOIN groups ON string_id = strings.id WHERE string_id IS NULL);"
		if let rows = OakPasteboardDatabase.sharedInstance().executeQuery(query, variables: [":name": name]) as? [[[AnyHashable: Any]]] {
			let deletedItemsCount   = rows[0][0]["count"] as? NSNumber
			let deletedStringsCount = rows[1][0]["count"] as? NSNumber
			if (deletedItemsCount?.intValue ?? 0) != 0 || (deletedStringsCount?.intValue ?? 0) != 0 {
				os_log("Deleted %{public}@ %{public}@ pasteboard item(s) and garbage collected %{public}@ string(s)", log: kLogSQLite, deletedItemsCount ?? 0, name as NSString, deletedStringsCount ?? 0)
			}
		}
	}

	@objc(previous)
	func previous() -> OakPasteboardEntry? {
		let entry = currentEntry.flatMap { entryBefore($0) } ?? firstEntry ?? currentEntry
		updatePasteboard(with: entry)
		return entry
	}

	@objc(current)
	func current() -> OakPasteboardEntry? {
		currentEntry
	}

	@objc(next)
	func next() -> OakPasteboardEntry? {
		let entry = currentEntry.flatMap { entryAfter($0) } ?? lastEntry ?? currentEntry
		updatePasteboard(with: entry)
		return entry
	}

	// @MainActor: drives OakPasteboardSelector, an NSWindowController. Always called from
	// a control (selectItemForControl:), i.e. the main thread.
	@MainActor
	private func selectItem(atPosition location: NSPoint, width: CGFloat, respondToSingleClick singleClick: Bool) {
		let entries = self.entries()

		let selectedRow = currentEntry.flatMap { entries.firstIndex(of: $0) } ?? 0
		let pasteboardSelector = OakPasteboardSelector.sharedInstance!
		pasteboardSelector.setEntries(entries)
		pasteboardSelector.setIndex(UInt(selectedRow))
		if width != 0 {
			pasteboardSelector.setWidth(width)
		}
		if singleClick {
			pasteboardSelector.setPerformsActionOnSingleClick()
		}

		let newSelection = pasteboardSelector.show(atLocation: location)
		let newEntries = pasteboardSelector.entries()

		let keep = Set((newEntries as? [OakPasteboardEntry]) ?? [])
		let remove = entries.filter { !keep.contains($0) }
		removeEntries(remove)

		if newSelection != -1, let newEntries = newEntries as? [OakPasteboardEntry] {
			updatePasteboard(with: newEntries[newSelection])
		}
	}

	@objc(selectItemForControl:)
	@MainActor
	func selectItem(forControl controlView: NSView) {
		let origin = controlView.window?.convertToScreen(controlView.convert(controlView.bounds, to: nil)).origin ?? .zero
		selectItem(atPosition: origin, width: NSWidth(controlView.frame), respondToSingleClick: true)
	}
}
