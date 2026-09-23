import XCTest

// Shipped values of security-relevant defaults.
//
// **Read from the registration domain, not through
// `UserDefaults.standard.bool(forKey:)`.** That accessor answers with whatever
// this developer has set in their own preferences, so it would pass whatever the
// application actually ships — which is the whole of what these tests are for.
final class DefaultsTests: XCTestCase {
	private func registered(_ key: String) -> Any? {
		RegisterDefaults()
		return UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)[key]
	}

	// The rmate server opens a TCP listener on 52698. A TCP socket carries no
	// owner and no mode, so unlike the `mate` UNIX socket there is no file
	// permission to lean on; loopback is not a boundary between accounts on one
	// machine; and nothing behind it authenticates, because the protocol's
	// `token` is an opaque string the client picks to match replies to requests.
	// A connection can open any file the application can read and, with
	// `data-on-close`, have the contents written back down the connection.
	//
	// So it is off unless somebody asks for it. Local `mate` is unaffected: it
	// goes over the UNIX socket, which RMateServer.mm binds unconditionally.
	func testTheRMateTCPListenerIsOffByDefault() {
		XCTAssertEqual((registered(kUserDefaultsDisableRMateServerKey) as? NSNumber)?.boolValue, true)
	}

	// And if somebody does switch it on, it reaches only this machine until they
	// separately choose otherwise.
	func testRMateListensOnLoopbackByDefault() {
		XCTAssertEqual(registered(kUserDefaultsRMateServerListenKey) as? String, kRMateServerListenLocalhost)
	}
}
