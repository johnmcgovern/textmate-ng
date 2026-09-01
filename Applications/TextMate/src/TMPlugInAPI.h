// The plug-in API: the two protocols a third-party .tmplugin compiles against.
//
// Split out of TMPlugInController.h when the controller became Swift. The class
// declaration there is now a hand declaration of a Swift class (rule 23) and so
// must stay out of the bridging header (rule 43) — but the Swift file needs
// these protocols, because TMPlugInController conforms to the first one and
// plug-ins are handed the controller as `id <TMPlugInController>`. This half is
// what the bridging header takes.
//
// TMPlugInController.h includes this, so a plug-in importing that header still
// sees exactly what it always did.
//
// The protocol carries NS_SWIFT_NAME because its ObjC name is also the class's:
// Swift would resolve `TMPlugInController` to the class and reject the
// conformance as multiple inheritance. The ObjC name is untouched, so plug-ins
// still write `id <TMPlugInController>`.
#import <Foundation/Foundation.h>

NS_SWIFT_NAME(TMPlugInControllerProtocol)
@protocol TMPlugInController
- (CGFloat)version;
@end

@protocol TMPlugIn
@optional
- (id)initWithPlugInController:(id <TMPlugInController>)aController;
@end
