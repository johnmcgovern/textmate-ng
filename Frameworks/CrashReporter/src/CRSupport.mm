#import "CRSupport.h"
#import <zlib.h>

BOOL CRWriteGZipFile (NSData* data, NSString* path)
{
	gzFile fp = gzopen(path.fileSystemRepresentation, "wb");
	if(!fp)
		return os_log_error(OS_LOG_DEFAULT, "Failed creating file %{public}@", path), NO;

	// gzwrite returns the number of *uncompressed* bytes written, and 0 for an
	// error — which the ObjC++ did not check. An empty NSData would also write
	// 0, so the length is tested first to keep those apart.
	BOOL res = YES;
	if(data.length != 0 && gzwrite(fp, data.bytes, (unsigned)data.length) == 0)
	{
		int err = 0;
		os_log_error(OS_LOG_DEFAULT, "Failed writing %{public}@: %{public}s", path, gzerror(fp, &err));
		res = NO;
	}

	gzclose(fp);
	return res;
}

// ============================================================================
// = The one delegate method Swift cannot implement in this project           =
// ============================================================================
//
// -userNotificationCenter:willPresentNotification:withCompletionHandler: is an
// *optional* requirement of UNUserNotificationCenterDelegate, and under this
// project's `-cxx-interoperability-mode=default` (SWIFT_OBJC_INTEROP_MODE=objcxx)
// NO Swift spelling can satisfy it. Both forms fail identically:
//
//   func …(_:willPresent:withCompletionHandler:)                // completion handler
//   func …(_:willPresent:) async -> UNNotificationPresentationOptions
//
// each producing
//
//   warning: instance method 'userNotificationCenter(_:willPresent:)' nearly
//   matches optional requirement 'userNotificationCenter(_:willPresent:)'
//
// — a method that "nearly matches" a requirement of *the same name*. Being only
// a warning on an optional requirement, it compiles, claims no selector, and is
// never called. Asking the ObjC runtime for the class's method list is the only
// way to see it.
//
// Without the C++ interop flag both spellings work, which is why this looks like
// a spelling mistake and is not one — and is very likely why five earlier
// attempts failed. The distinguishing detail is
// UNNotificationPresentationOptions: it is the only NS_OPTIONS type in these
// four delegate methods, and -didReceiveNotificationResponse:, whose handler
// takes nothing, is satisfied from Swift without complaint.
//
// So it lives here, as an ObjC++ category on the Swift class — the same recipe
// BEInterop.mm uses for C++-typed selectors, and the reason CrashReporter.h can
// stay unchanged.
#import "CrashReporter.h"
#import <UserNotifications/UserNotifications.h>

@implementation CrashReporter (CRPresentationInterop)

- (void)userNotificationCenter:(UNUserNotificationCenter*)center willPresentNotification:(UNNotification*)notification withCompletionHandler:(void(^)(UNNotificationPresentationOptions))completionHandler
{
	// UNNotificationPresentationOptionAlert in the ObjC++; deprecated since
	// macOS 11 in favour of …Banner, which names the same presentation.
	completionHandler(UNNotificationPresentationOptionBanner);
}

@end
