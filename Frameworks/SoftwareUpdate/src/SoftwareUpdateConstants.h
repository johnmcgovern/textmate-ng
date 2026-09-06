// The user-defaults keys and channel names, split out of SoftwareUpdate.h and
// SoftwareUpdate.mm (rule 11).
//
// Why they need their own file: SoftwareUpdate.h declares @interface
// SoftwareUpdate, which becomes a Swift class, so that header cannot enter this
// framework's bridging header without colliding with the generated -Swift.h
// (rule 43). But Swift can *call* a global and never *export* one (rule 19), so
// these have to keep being defined by an ObjC++ translation unit and declared
// somewhere the Swift can still see them. That is this file, and
// SoftwareUpdateConstants.mm is the definition.
//
// SoftwareUpdate.h imports this, so no existing consumer changed.
//
// All nine are here, including the two that only this framework reads. They
// already had external linkage as `NSString* const` in the .mm — declaring them
// in a header documents that rather than widening it, and it keeps the ported
// Swift from having to re-spell a defaults key as a literal, which is the kind
// of duplication that silently drifts.
#import <Foundation/Foundation.h>

extern NSString* const kUserDefaultsLastSoftwareUpdateCheckKey;
extern NSString* const kUserDefaultsSoftwareUpdateSuspendUntilKey;
extern NSString* const kUserDefaultsDisableSoftwareUpdateKey;
extern NSString* const kUserDefaultsAskBeforeUpdatingKey;
extern NSString* const kUserDefaultsSoftwareUpdateChannelKey;
extern NSString* const kUserDefaultsSoftwareUpdateDisableReadOnlyFileSystemWarningKey;

extern NSString* const kSoftwareUpdateChannelRelease;
extern NSString* const kSoftwareUpdateChannelPrerelease;
extern NSString* const kSoftwareUpdateChannelCanary;
