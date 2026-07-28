// Hand-written ObjC declarations for the classes this framework implements in
// Swift, for use by the framework's own ObjC++ files.
//
// Why not just import the generated BundleEditor-Swift.h? Because under
// SWIFT_OBJC_INTEROP_MODE=objcxx the generated header emits
// `namespace BundleEditor { … }` from the *module* name, and this framework also
// has an ObjC *class* named BundleEditor — clang rejects that as "redefinition
// of 'BundleEditor' as a different kind of symbol". Any framework whose module
// name matches one of its own ObjC class names hits this; the fix is to declare
// what ObjC++ needs by hand, exactly as Preferences.h does for its consumers.
//
// Keep these declarations in step with the Swift definitions — nothing checks
// them at build time; a mismatch is an unrecognized selector at runtime.
@class OakKeyEquivalentView;

// PropertiesViewController.swift — File's Owner of the 8 property xibs.
@interface PropertiesViewController : NSViewController
- (instancetype)initWithName:(NSString*)aName;
@property (nonatomic) NSMutableDictionary* properties;
@property (nonatomic, readonly) CGFloat labelWidth;
@end

// OakRot13Transformer.swift
@interface OakRot13Transformer : NSValueTransformer
+ (void)register;
@end
