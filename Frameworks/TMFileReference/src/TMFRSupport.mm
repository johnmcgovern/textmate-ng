#import "TMFRSupport.h"
#import "TMFileReference.h"

// Defined here rather than in the Swift: this is an exported C symbol that
// consumers link against (`extern NSNotificationName const` in
// TMFileReference.h), and a Swift `NSNotification.Name` extension does not emit
// one. The Swift reads it back through the bridging header.
NSNotificationName const TMURLWillCloseNotification = @"TMURLWillCloseNotification";

NSImage* TMAliasBadgeImage (void)
{
	// Deprecated since macOS 11, and the suggested replacements
	// (-[NSWorkspace iconForFileType:] and friends) do not vend the *badge* on
	// its own — only whole icons. Kept behind the same diagnostic suppression
	// the ObjC++ used, so the port is not quietly a behaviour change.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	IconRef iconRef;
	if(GetIconRef(kOnSystemDisk, kSystemIconsCreator, kAliasBadgeIcon, &iconRef) != noErr)
		return nil;

	NSImage* res = [[NSImage alloc] initWithIconRef:iconRef];
	ReleaseIconRef(iconRef);
	return res;
#pragma clang diagnostic pop
}
