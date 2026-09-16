import Foundation

// Ported from OakHistoryList.mm — a most-recently-used stack of at most
// `stackSize` objects, persisted in NSUserDefaults under `name`. Find's glob
// history and recent folders, and the Run Command window's command history.
// Pinned by t_history_list.mm, written first. OakFoundation's first Swift file.
//
// OakHistoryList.h stays as the hand-written declaration (rule 23): both
// consumers are Swift in other modules and reach the class through it, and it
// carries the lightweight generic the ObjC spelling had, which a Swift class
// cannot declare and the runtime never sees.
//
// The variadic -initWithName:stackSize:defaultItems: is gone. Swift cannot
// define a C variadic method, nothing has called it since the array spelling
// was added for the Run Command port, and the pins say which initializers
// must exist.
//
// `list` is an NSMutableArray mutated in place, as it was, and not `dynamic`:
// the bindings observe `list` and `head` through the explicit will/didChange
// pairs in addObject(_:), exactly the notifications the ObjC++ sent, and an
// automatically observed Swift array would send a second set. `head` is
// `dynamic` because its setter is where the runtime's automatic notification
// comes from — the pins count both.

private func SplitKeyPath(_ keyPath: String) -> [String] {
	guard let range = keyPath.range(of: ".") else {
		return [ keyPath ]
	}
	return [ String(keyPath[..<range.lowerBound]), String(keyPath[range.upperBound...]) ]
}

private func StoreObjectAtKeyPath(_ obj: Any, _ keyPath: String) {
	let pathArray = SplitKeyPath(keyPath)
	if pathArray.count == 1 {
		UserDefaults.standard.set(obj, forKey: keyPath)
	}
	else if pathArray.count == 2 {
		var dict: [String: Any] = [:]
		if let existingDict = UserDefaults.standard.dictionary(forKey: pathArray[0]) {
			dict = existingDict
		}
		dict[pathArray[1]] = obj
		UserDefaults.standard.set(dict, forKey: pathArray[0])
	}
}

private func RetrieveObjectAtKeyPath(_ keyPath: String) -> Any? {
	let pathArray = SplitKeyPath(keyPath)
	if pathArray.count == 1 {
		return UserDefaults.standard.object(forKey: keyPath)
	}
	else if pathArray.count == 2 {
		return UserDefaults.standard.dictionary(forKey: pathArray[0])?[pathArray[1]]
	}
	return nil
}

@objc(OakHistoryList)
class OakHistoryList: NSObject {
	private let name: String
	@objc private(set) var stackSize: UInt
	@objc private(set) var list: NSMutableArray

	@objc(initWithName:stackSize:)
	init(name defaultsName: String, stackSize size: UInt) {
		stackSize = size
		name      = defaultsName
		list      = NSMutableArray(capacity: Int(size))
		super.init()

		if let array = RetrieveObjectAtKeyPath(name) as? [Any] {
			list.setArray(Array(array.prefix(Int(stackSize))))
		}
	}

	@objc(initWithName:stackSize:fallbackUserDefaultsKey:)
	convenience init(name defaultsName: String, stackSize size: UInt, fallbackUserDefaultsKey fallbackDefaultsName: String) {
		self.init(name: defaultsName, stackSize: size)
		if list.count == 0 {
			if let array = UserDefaults.standard.array(forKey: fallbackDefaultsName) {
				list.setArray(array)
			}
		}
	}

	@objc(initWithName:stackSize:defaultItemsArray:)
	convenience init(name defaultsName: String, stackSize size: UInt, defaultItemsArray items: [Any]) {
		self.init(name: defaultsName, stackSize: size)
		// Only seeds an empty list: the stored history wins over the defaults, which
		// is what makes these "default items" rather than "always-present items".
		if list.count == 0 {
			list.addObjects(from: items)
		}
	}

	@objc(addObject:)
	func addObject(_ newItem: Any?) {
		// OakIsEmptyString, spelled for an `id`: nil and the empty string are
		// ignored. (The ObjC++ would have sent -isEqualToString: to whatever it was
		// given; the consumers only ever give it strings.)
		guard let newItem else {
			return
		}
		if let string = newItem as? String, string.isEmpty {
			return
		}
		if let first = list.firstObject, (newItem as AnyObject).isEqual(first) {
			return
		}

		willChangeValue(forKey: "head")
		willChangeValue(forKey: "currentObject")
		willChangeValue(forKey: "list")

		list.remove(newItem)

		if UInt(list.count) == stackSize {
			list.removeLastObject()
		}

		list.insert(newItem, at: 0)

		didChangeValue(forKey: "list")
		didChangeValue(forKey: "currentObject")
		didChangeValue(forKey: "head")

		StoreObjectAtKeyPath(list, name)
	}

	@objc func objectEnumerator() -> NSEnumerator {
		return list.objectEnumerator()
	}

	@objc(objectAtIndex:)
	func object(at index: UInt) -> Any {
		return list.object(at: Int(index))
	}

	@objc var count: UInt {
		return UInt(list.count)
	}

	@objc dynamic var head: Any? {
		get { list.firstObject }
		set { addObject(newValue) }
	}
}
