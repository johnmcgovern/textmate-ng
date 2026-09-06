// Definitions for SoftwareUpdateConstants.h. Moved verbatim from
// SoftwareUpdate.mm; see the header for why they live apart from it.
//
// This translation unit stays ObjC++ permanently. It exists precisely because
// Swift cannot export a global (rule 19) — porting it would delete the symbols
// that Preferences and the application link against.
#import "SoftwareUpdateConstants.h"

NSString* const kUserDefaultsLastSoftwareUpdateCheckKey                        = @"SoftwareUpdateLastPoll";
NSString* const kUserDefaultsSoftwareUpdateSuspendUntilKey                     = @"SoftwareUpdateSuspendUntil";
NSString* const kUserDefaultsDisableSoftwareUpdateKey                          = @"SoftwareUpdateDisablePolling";
NSString* const kUserDefaultsAskBeforeUpdatingKey                              = @"SoftwareUpdateAskBeforeUpdating";
NSString* const kUserDefaultsSoftwareUpdateChannelKey                          = @"SoftwareUpdateChannel";
NSString* const kUserDefaultsSoftwareUpdateDisableReadOnlyFileSystemWarningKey = @"SoftwareUpdateDisableReadOnlyFileSystemWarningKey";

NSString* const kSoftwareUpdateChannelRelease                                  = @"release";
NSString* const kSoftwareUpdateChannelPrerelease                               = @"beta";
NSString* const kSoftwareUpdateChannelCanary                                   = @"nightly";
