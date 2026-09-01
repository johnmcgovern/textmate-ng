// Extracted from TMPlugInController.mm ahead of porting it to Swift. Three
// things in that file touch C++, and none of them is C++ the class actually
// wants — it is the crash reporter, the temp-directory path, and the relauncher:
//
//   - the crash-marker path, path::join(path::temp(), "load_" + identifier);
//   - crash_reporter_info_t around the instantiation, which is an RAII object
//     whose lifetime *is* the call it guards (rule 17 — the boundary has to be
//     the whole scope, not the constructor);
//   - oak::application_t::relaunch().
//
// The rest of the class is NSBundle, NSUserDefaults, NSAlert and four POSIX
// calls, all of which Swift reaches on its own.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TMPlugInSupport : NSObject
// path::join(path::temp(), "load_" + identifier). Written before a plug-in is
// loaded and removed after, so a crash during the load leaves it behind and the
// next launch offers to trash the plug-in.
+ (NSString*)crashMarkerPathForIdentifier:(NSString*)identifier;

// Allocates the plug-in's principal class and initialises it, preferring
// -initWithPlugInController: when the class implements it. The crash reporter
// note naming the plug-in is live for exactly the duration of that call, which
// is the point: an abort inside a plug-in's -init is what it is there to label.
+ (nullable id)instantiatePlugInClass:(nullable Class)cl controller:(id)controller identifier:(NSString*)identifier;

+ (void)relaunchApplication;
@end

NS_ASSUME_NONNULL_END
