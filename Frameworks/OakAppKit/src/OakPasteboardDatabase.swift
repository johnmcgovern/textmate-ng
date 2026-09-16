import Cocoa
import SQLite3
import os

// Ported from OakPasteboardDatabase.mm — the SQLite store behind OakPasteboard:
// one process-wide connection, opened on first use (in memory when
// disablePersistentClipboardHistory is set), the schema created on that first
// open, and a garbage-collecting close at termination. The API is a query
// string plus a dictionary of `:name` → String / Data / NSNumber / NSNull.
// Pinned by the database half of t_pasteboard.mm.
//
// It was extracted from OakPasteboard.mm as a C++ boundary so the pasteboard
// could become Swift, but its only C++ was a std::map from @encode strings to
// bind functions, and the sqlite3 C API is Swift's to call. So the boundary
// itself is Swift now, and OakPasteboardDatabase.h stays as the hand-written
// declaration (rule 23) for t_pasteboard.mm; OakPasteboard.swift sees the class
// directly, in the same module.
//
// One deliberate difference from the ObjC++, measured before the port: the
// frameworks compile with an unsigned char, so @encode(char) was "C" and the
// table never had a "c" entry — a boxed BOOL (objCType "c", boxed by a
// Foundation built with a signed char) fell through to the text fallback and
// bound as "1". The table below is keyed by the letters themselves, so "c"
// binds as an integer, which is what the ObjC++ meant. No caller binds a
// boolean; the pin that recorded the old behaviour records the new one.
//
// Text and blobs are bound with SQLITE_TRANSIENT: the ObjC++ bound pointers
// into autoreleased buffers with SQLITE_STATIC, which held for the duration of
// one statement; Swift's temporary buffers do not make that promise.

private let kLogSQLite     = OSLog(subsystem: "Pasteboard", category: "sqlite")
private let kLogPasteboard = OSLog(subsystem: "Pasteboard", category: "history")

// Used only here now (the persistent-history toggle is a database concern).
private let kUserDefaultsDisablePersistentClipboardHistory = "disablePersistentClipboardHistory"

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func ColumnsAsDictionary(_ stmt: OpaquePointer) -> [String: Any] {
	var item: [String: Any] = [:]
	for i in 0..<sqlite3_data_count(stmt) {
		var value: Any?
		switch sqlite3_column_type(stmt, i) {
			case SQLITE_INTEGER: value = NSNumber(value: sqlite3_column_int(stmt, i))
			case SQLITE_FLOAT:   value = NSNumber(value: sqlite3_column_double(stmt, i))
			case SQLITE_TEXT:    value = sqlite3_column_text(stmt, i).map { String(cString: $0) }
			case SQLITE_BLOB:    value = sqlite3_column_blob(stmt, i).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(stmt, i))) } ?? Data()
			case SQLITE_NULL:    value = nil
			default:             value = nil
		}

		if let value {
			item[String(cString: sqlite3_column_name(stmt, i))] = value
		}
	}
	return item
}

// The @encode → sqlite3_bind dispatch, by the objCType letter. "l"/"L" are the
// same letters as "q"/"Q" on this platform and the map kept one of each.
private func BindNumber(_ stmt: OpaquePointer, _ index: Int32, _ value: NSNumber) -> Int32 {
	switch String(cString: value.objCType) {
		case "B": return sqlite3_bind_int(stmt, index, value.boolValue ? 1 : 0)
		case "c": return sqlite3_bind_int(stmt, index, Int32(value.int8Value))
		case "C": return sqlite3_bind_int(stmt, index, Int32(value.uint8Value))
		case "s": return sqlite3_bind_int(stmt, index, Int32(value.int16Value))
		case "S": return sqlite3_bind_int(stmt, index, Int32(value.uint16Value))
		case "i": return sqlite3_bind_int64(stmt, index, Int64(value.int32Value))
		case "I": return sqlite3_bind_int64(stmt, index, Int64(value.uint32Value))
		case "l", "q": return sqlite3_bind_int64(stmt, index, value.int64Value)
		case "L", "Q": return sqlite3_bind_int64(stmt, index, Int64(bitPattern: value.uint64Value))
		case "f": return sqlite3_bind_double(stmt, index, Double(value.floatValue))
		case "d": return sqlite3_bind_double(stmt, index, value.doubleValue)
		default:  return sqlite3_bind_text(stmt, index, value.stringValue, -1, SQLITE_TRANSIENT)
	}
}

// Verbatim in shape from the ObjC++ RunSQLStatement: `;`-separated statements,
// each prepared, bound by parameter name, stepped; the result is the rows of a
// single row-returning statement, an array of those for several, nil for none
// or for any error.
private func RunSQLStatement(_ db: OpaquePointer, _ query: String, _ variables: [String: Any] = [:]) -> [Any]? {
	var resultSet: [[[String: Any]]]? = []

	query.withCString { queryStart in
		var query: UnsafePointer<CChar>? = queryStart
		var res = true
		while let q = query, q.pointee != 0, res {
			var stmt: OpaquePointer?
			var nextQuery: UnsafePointer<CChar>?
			if sqlite3_prepare_v2(db, q, -1, &stmt, &nextQuery) == SQLITE_OK, let stmt {
				var rows: [[String: Any]]?

				for i in 0..<sqlite3_bind_parameter_count(stmt) {
					let name = sqlite3_bind_parameter_name(stmt, i+1).map { String(cString: $0) } ?? ""
					if let value = variables[name] {
						if value is NSNull {
							sqlite3_bind_null(stmt, i+1)
						}
						else if let string = value as? String {
							sqlite3_bind_text(stmt, i+1, string, -1, SQLITE_TRANSIENT)
						}
						else if let data = value as? Data {
							data.withUnsafeBytes { bytes in
								_ = sqlite3_bind_blob(stmt, i+1, bytes.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
							}
						}
						else if let number = value as? NSNumber {
							_ = BindNumber(stmt, i+1, number)
						}
					}
					else {
						os_log("sqlite3: no variable for binding: ‘%{public}s’", log: kLogSQLite, type: .error, name)
					}
				}

				var status: Int32
				repeat {
					status = sqlite3_step(stmt)
					if status == SQLITE_ROW {
						if rows == nil {
							rows = []
						}
						rows?.append(ColumnsAsDictionary(stmt))
					}
				} while status == SQLITE_ROW

				if status != SQLITE_DONE {
					os_log("sqlite3_step: %{public}s executing %{public}s", log: kLogSQLite, type: .error, String(cString: sqlite3_errmsg(db)), String(cString: q))
					res = false
				}

				if sqlite3_finalize(stmt) != SQLITE_OK {
					os_log("sqlite3_finalize: %{public}s", log: kLogSQLite, type: .error, String(cString: sqlite3_errmsg(db)))
					res = false
				}

				if res, let rows {
					resultSet?.append(rows)
				}
			}
			else {
				os_log("sqlite3_prepare_v2(%{public}s): %{public}s", log: kLogSQLite, type: .error, String(cString: q), String(cString: sqlite3_errmsg(db)))
				res = false
			}
			query = nextQuery

			if !res {
				resultSet = nil
			}
		}
	}

	guard let resultSet else {
		return nil
	}
	if resultSet.count > 1 {
		return resultSet
	}
	return resultSet.last
}

@objc(OakPasteboardDatabase)
class OakPasteboardDatabase: NSObject {
	// nonisolated(unsafe) for the reason OakDocumentController's is: not a
	// MainActor object, and the ObjC++ was a function-local static.
	nonisolated(unsafe) private static let instance = OakPasteboardDatabase()

	@objc class func sharedInstance() -> OakPasteboardDatabase {
		return instance
	}

	// Process-wide, as +[OakPasteboard SQLDatabase]'s static was; there is one
	// shared instance, and the terminate block below captures this static directly.
	nonisolated(unsafe) private static var db: OpaquePointer?

	private var databaseURL: URL? {
		do {
			let appSupport = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("TextMate")
			try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true, attributes: nil)
			return appSupport.appendingPathComponent("PasteboardHistory.db")
		}
		catch {
			MainActor.assumeIsolated {
				NSApp.presentError(error)
			}
			return nil
		}
	}

	private var database: OpaquePointer? {
		// One connection, main-thread-only by contract: OakPasteboard is main-thread-
		// only, and the terminate observer runs on the posting thread, which is
		// main. Enforced in Debug (concurrency audit, 2026-09-16).
		assert(Thread.isMainThread, "OakPasteboardDatabase is main-thread-only")
		if Self.db == nil {
			// =========================
			// = Delete CoreData files =
			// =========================

			for appSupport in FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask) {
				for file in [ "ClipboardHistory.db", "ClipboardHistory.db-shm", "ClipboardHistory.db-wal" ] {
					let url = appSupport.appendingPathComponent("TextMate").appendingPathComponent(file)
					if FileManager.default.fileExists(atPath: url.path) {
						var res: NSURL?
						if (try? FileManager.default.trashItem(at: url, resultingItemURL: &res)) != nil {
							os_log("Moved CoreData file to trash: %{public}@ → %{public}@", log: kLogPasteboard, type: .info, (url.path as NSString).abbreviatingWithTildeInPath, ((res?.path ?? "") as NSString).abbreviatingWithTildeInPath)
						}
					}
				}
			}

			// =========================

			let memoryDatabase = UserDefaults.standard.bool(forKey: kUserDefaultsDisablePersistentClipboardHistory)
			let path = memoryDatabase ? ":memory:" : (databaseURL?.path ?? "")
			var db: OpaquePointer?
			if sqlite3_open(path, &db) == SQLITE_OK, let db {
				Self.db = db
				os_log("Opening sqlite3 database: %{public}@", log: kLogSQLite, type: .info, memoryDatabase ? ":memory:" : (path as NSString).abbreviatingWithTildeInPath)

				NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
					guard let db = Self.db else {
						return
					}

					if !memoryDatabase {
						let query =
							"SELECT COUNT(*) AS count FROM strings LEFT JOIN groups ON string_id = strings.id WHERE string_id IS NULL;" +
							"DELETE FROM strings WHERE id IN (SELECT strings.id FROM strings LEFT JOIN groups ON string_id = strings.id WHERE string_id IS NULL);"

						if let row = RunSQLStatement(db, query)?.first as? [String: Any], let count = (row["count"] as? NSNumber)?.intValue, count != 0 {
							os_log("Garbage collected %lu string(s) from database", log: kLogSQLite, type: .info, count)
						}
					}

					os_log("Closing sqlite3 database", log: kLogSQLite, type: .info)
					if sqlite3_close(db) != SQLITE_OK {
						os_log("sqlite3_close: %{public}s", log: kLogSQLite, type: .error, String(cString: sqlite3_errmsg(db)))
					}
					Self.db = nil
				}

				let query =
					"PRAGMA foreign_keys = on;" +
					"CREATE TABLE IF NOT EXISTS 'clipboards' (" +
					"   'id'               INTEGER PRIMARY KEY," +
					"   'name'             TEXT NOT NULL," +
					"   UNIQUE (name) ON CONFLICT IGNORE" +
					");" +
					"CREATE TABLE IF NOT EXISTS 'strings' (" +
					"   'id'               INTEGER PRIMARY KEY," +
					"   'string'           TEXT NOT NULL," +
					"   UNIQUE (string) ON CONFLICT IGNORE" +
					");" +
					"CREATE TABLE IF NOT EXISTS 'history' (" +
					"   'id'               INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT," +
					"   'clipboard_id'     INTEGER NOT NULL," +
					"   'options'          BLOB DEFAULT NULL," +
					"   'date'             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP," +
					"   CONSTRAINT fk_clipboard FOREIGN KEY (clipboard_id) REFERENCES clipboards (id) ON DELETE CASCADE" +
					");" +
					"CREATE TABLE IF NOT EXISTS 'flags' (" +
					"   'id'               INTEGER NOT NULL," +
					"   CONSTRAINT fk_id FOREIGN KEY (id) REFERENCES history (id) ON DELETE CASCADE" +
					");" +
					"CREATE TABLE IF NOT EXISTS 'groups' (" +
					"   'id'               INTEGER NOT NULL PRIMARY KEY," +
					"   'history_id'       INTEGER NOT NULL," +
					"   'string_id'        INTEGER NOT NULL," +
					"   CONSTRAINT fk_history FOREIGN KEY (history_id) REFERENCES history (id) ON DELETE CASCADE," +
					"   CONSTRAINT fk_string  FOREIGN KEY (string_id)  REFERENCES strings (id) ON DELETE CASCADE" +
					");" +
					"CREATE TABLE IF NOT EXISTS 'meta' (" +
					"   'key'              TEXT NOT NULL," +
					"   'value'            TEXT NOT NULL," +
					"   UNIQUE (key)" +
					");" +
					"INSERT OR IGNORE INTO meta ('key', 'value') VALUES ('version', '1'),('uuid', :uuid)"

				// Remove superfluous whitespace to improve output of sqlite3’s ‘.schema’ command
				let pretty = query.replacingOccurrences(of: "(\\(| ) +", with: "$1", options: .regularExpression)

				_ = RunSQLStatement(db, pretty, [ ":uuid": UUID().uuidString ])
			}
		}
		return Self.db
	}

	@objc(executeQuery:)
	func executeQuery(_ query: String) -> [Any]? {
		return executeQuery(query, variables: [:])
	}

	@objc(executeQuery:variables:)
	func executeQuery(_ query: String, variables: [String: Any]?) -> [Any]? {
		guard let db = database else {
			return nil
		}
		return RunSQLStatement(db, query, variables ?? [:])
	}
}
