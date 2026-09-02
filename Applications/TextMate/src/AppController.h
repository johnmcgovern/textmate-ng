// OakOpenDocuments lives in its own header now (rule 11) and is imported here,
// so every existing `#import "AppController.h"` is unchanged.
#import "OakOpenDocuments.h"

@interface AppController : NSObject <NSMenuDelegate>
{
	NSMenu* bundlesMenu;
	NSMenu* themesMenu;
	NSMenu* spellingMenu;
	NSMenu* wrapColumnMenu;

	IBOutlet NSPanel* goToLinePanel;
	IBOutlet NSTextField* goToLineTextField;
}

- (IBAction)orderFrontFindPanel:(id)sender;

- (IBAction)orderFrontGoToLinePanel:(id)sender;
- (IBAction)performGoToLine:(id)sender;

- (IBAction)showBundleItemChooser:(id)sender;

- (IBAction)performSoftwareUpdateCheck:(id)sender;
- (IBAction)showPreferences:(id)sender;
- (IBAction)showBundleEditor:(id)sender;

- (IBAction)newDocumentAndActivate:(id)sender;
- (IBAction)openDocumentAndActivate:(id)sender;

- (IBAction)runPageLayout:(id)sender;
- (IBAction)openFavorites:(id)sender;
@end

@interface AppController (Documents)
- (void)newDocument:(id)sender;
- (void)openDocument:(id)sender;
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender;
@end

@interface AppController (BundlesMenu)
// Was +initialize; -applicationWillFinishLaunching: calls it now (rule 24).
+ (void)setupThemeDefaultsAndObservers;
- (BOOL)validateThemeMenuItem:(NSMenuItem*)item;
@end
