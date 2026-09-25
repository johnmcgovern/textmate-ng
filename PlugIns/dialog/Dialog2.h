// The Dialog2 plug-in's request handler. It listens on a UNIX socket for
// requests from tm_dialog2; see DialogWire.h for why that replaced the
// Distributed Objects service `com.macromates.dialog.<pid>` on 2026-09-24.
@interface Dialog2 : NSObject
- (id)initWithPlugInController:(id)aController;
@end
