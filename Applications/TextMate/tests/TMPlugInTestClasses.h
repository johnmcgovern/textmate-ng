// Two stand-ins for a plug-in's principal class, to pin which initialiser
// +instantiatePlugInClass:controller:identifier: picks.
//
// Defined rather than merely declared, and in a header, for the reason
// OakChooserTestSubclass.h gives: ide/gen_xctest.rb wraps each test file's body
// in `namespace <basename>`, where ObjC declarations may not appear, but hoists
// every #import to the top.
#import "../src/TMPlugInAPI.h"

// The real plug-in shape: takes the controller and keeps it.
@interface TMPlugInTestPlugIn : NSObject <TMPlugIn>
@property (nonatomic, weak) id controller;
@end

@implementation TMPlugInTestPlugIn
- (id)initWithPlugInController:(id <TMPlugInController>)aController
{
	if(self = [super init])
		self.controller = aController;
	return self;
}
@end

// -initWithPlugInController: is @optional, so a plug-in may implement only
// -init. This one must still be instantiated, and must not be handed anything.
@interface TMPlugInTestBarePlugIn : NSObject
@property (nonatomic) BOOL plainInitWasUsed;
@end

@implementation TMPlugInTestBarePlugIn
- (id)init
{
	if(self = [super init])
		self.plainInitWasUsed = YES;
	return self;
}
@end
