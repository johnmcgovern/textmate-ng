// Hand-declared (rule 23): OakRolloverButton is defined in OakRolloverButton.swift.
//
// This is the ObjC face of that Swift class, for the ObjC++ that still builds one
// — OakUIConstructionFunctions' OakCreateCloseButton — and for the bridging
// headers of the frameworks whose Swift uses it (OakTabBarView, FileBrowser,
// OakFilterList). It must NOT appear in OakAppKit's own bridging header, where it
// would collide with the generated OakAppKit-Swift.h (rule 43).
//
// Keep this in step with the Swift. Every property below is @objc dynamic there;
// a name that drifts apart compiles on both sides and fails as an unrecognized
// selector at runtime, which is what t_rollover_button.mm's selector surface is
// for.
#import "OakRolloverButtonConstants.h"

@interface OakRolloverButton : NSButton
// Six slots, two outputs. -image and -alternateImage are derived from these plus
// the pointer and window state; see OakRolloverButton.swift's updateImage for the
// two substitutions that do not read the way these names suggest.
@property (nonatomic) NSImage* regularImage;
@property (nonatomic) NSImage* pressedImage;
@property (nonatomic) NSImage* rolloverImage;
@property (nonatomic) NSImage* inactiveRegularImage;
@property (nonatomic) NSImage* inactivePressedImage;
@property (nonatomic) NSImage* inactiveRolloverImage;
@property (nonatomic) BOOL disableWindowOrderingForFirstMouse;
@end
