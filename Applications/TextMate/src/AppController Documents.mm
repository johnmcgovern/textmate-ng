#import "AppController.h"
#import "TxMtURLSupport.h"
#import <DocumentWindow/DocumentWindowController.h>
#import "ODBEditorSuite.h"
#import <Preferences/Keys.h>
#import <OakAppKit/NSSavePanel Additions.h>
#import <OakFoundation/NSString Additions.h>
#import <document/OakDocument.h>
#import <document/OakDocumentController.h>

@implementation AppController (Documents)
- (void)newDocument:(id)sender
{
	[[DocumentWindowController new] showWindow:self];
}

- (void)newFileBrowser:(id)sender
{
	NSString* urlString = [NSUserDefaults.standardUserDefaults stringForKey:kUserDefaultsInitialFileBrowserURLKey];
	NSURL* url          = urlString ? [NSURL URLWithString:urlString] : nil;

	DocumentWindowController* controller = [DocumentWindowController new];
	controller.defaultProjectPath = [url isFileURL] ? [url path] : NSHomeDirectory();
	controller.fileBrowserVisible = YES;
	[controller showWindow:self];
}

- (void)openDocument:(id)sender
{
	NSOpenPanel* openPanel = [NSOpenPanel openPanel];
	openPanel.allowsMultipleSelection         = YES;
	openPanel.canChooseDirectories            = YES;
	openPanel.canChooseFiles                  = YES;
	openPanel.treatsFilePackagesAsDirectories = YES;
	openPanel.title                           = [NSString stringWithFormat:@"%@: Open", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"] ?: [[NSProcessInfo processInfo] processName]];

	[openPanel setShowsHiddenFilesCheckBox:YES];
	if([openPanel runModal] == NSModalResponseOK)
	{
		NSMutableArray* filenames = [NSMutableArray array];
		for(NSURL* url in [openPanel URLs])
			[filenames addObject:[[url filePathURL] path]];

		OakOpenDocuments(filenames);
	}
}

- (BOOL)application:(NSApplication*)theApplication openFile:(NSString*)aPath
{
	if(!DidHandleODBEditorEvent([[NSAppleEventManager.sharedAppleEventManager currentAppleEvent] aeDesc]))
		OakOpenDocuments(@[ aPath ]);
	return YES;
}

- (void)application:(NSApplication*)sender openFiles:(NSArray*)filenames
{
	if(!DidHandleODBEditorEvent([[NSAppleEventManager.sharedAppleEventManager currentAppleEvent] aeDesc]))
		OakOpenDocuments(filenames);
	[sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (BOOL)applicationOpenUntitledFile:(NSApplication*)theApplication
{
	if([NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsShowFavoritesInsteadOfUntitledKey])
			[self openFavorites:self];
	else	[self newDocument:self];
	return YES;
}

- (void)handleTxMtURL:(NSURL*)aURL
{
	if([[aURL host] isEqualToString:@"open"])
	{
		NSDictionary<NSString*, NSString*>* parameters = [TxMtURLSupport parametersFromQuery:[aURL query]];

		NSString* url     = parameters[@"url"];
		NSString* uuid    = parameters[@"uuid"];
		NSString* project = parameters[@"project"];

		// nil exactly when there was no line parameter, which is the
		// `range == text::range_t::undefined` the three branches below used to test.
		NSString* selection = [TxMtURLSupport selectionStringForLine:parameters[@"line"] column:parameters[@"column"]];

		NSUUID* projectUUID = project ? [[NSUUID alloc] initWithUUIDString:project] : nil;
		if(url)
		{
			// nil for a url that matches no file:// prefix — the NULL_STR the
			// original carried into path::is_directory and path::exists, which both
			// answer NO for it, and then into the alert, which showed “(null)”.
			// Deliberately not guarded here, so that path is unchanged.
			NSString* path = [TxMtURLSupport pathForFileURLString:url];

			if([TxMtURLSupport pathIsDirectory:path])
			{
				[OakDocumentController.sharedInstance showFileBrowserAtPath:path];
			}
			else if([TxMtURLSupport pathExists:path])
			{
				OakDocument* doc = [OakDocumentController.sharedInstance documentWithPath:path];
				doc.recentTrackingDisabled = YES;
				if(selection)
					doc.selection = selection;
				[OakDocumentController.sharedInstance showDocument:doc inProject:projectUUID bringToFront:YES];
			}
			else
			{
				NSAlert* alert        = [[NSAlert alloc] init];
				alert.messageText     = @"File Does not Exist";
				alert.informativeText = [NSString stringWithFormat:@"The item “%@” does not exist.", path];
				[alert addButtonWithTitle:@"Continue"];
				[alert runModal];
			}
		}
		else if(uuid)
		{
			if(OakDocument* doc = [OakDocumentController.sharedInstance findDocumentWithIdentifier:[[NSUUID alloc] initWithUUIDString:uuid]])
			{
				doc.recentTrackingDisabled = YES;
				if(selection)
					doc.selection = selection;
				[OakDocumentController.sharedInstance showDocument:doc inProject:projectUUID bringToFront:YES];
			}
			else
			{
				NSAlert* alert        = [[NSAlert alloc] init];
				alert.messageText     = @"File Does not Exist";
				alert.informativeText = [NSString stringWithFormat:@"No document found for UUID %@.", uuid];
				[alert addButtonWithTitle:@"Continue"];
				[alert runModal];
			}
		}
		else if(selection)
		{
			for(NSWindow* win in [NSApp orderedWindows])
			{
				BOOL foundTextView = [[win firstResponder] tryToPerform:@selector(setSelectionString:) with:selection];
				if(!foundTextView)
				{
					NSMutableArray* allViews = [[[win contentView] subviews] mutableCopy];
					for(NSUInteger i = 0; i < [allViews count]; ++i)
						[allViews addObjectsFromArray:[[allViews objectAtIndex:i] subviews]];

					for(NSView* view in allViews)
					{
						if([view respondsToSelector:@selector(setSelectionString:)])
						{
							[view performSelector:@selector(setSelectionString:) withObject:selection];
							[win makeFirstResponder:view];
							foundTextView = YES;
							break;
						}
					}
				}

				if(foundTextView)
				{
					[win makeKeyAndOrderFront:self];
					break;
				}
			}
		}
		else
		{
			NSAlert* alert        = [[NSAlert alloc] init];
			alert.messageText     = @"Missing Parameter";
			alert.informativeText = [NSString stringWithFormat:@"You need to provide either a (file) url or line parameter. The URL given was: ‘%@’.", aURL];
			[alert addButtonWithTitle:@"Continue"];
			[alert runModal];
		}
	}
	else
	{
		NSAlert* alert        = [[NSAlert alloc] init];
		alert.messageText     = @"Unknown URL Scheme";
		alert.informativeText = [NSString stringWithFormat:@"This version of TextMate does not support “%@” in its URL scheme.", [aURL host]];
		[alert addButtonWithTitle:@"Continue"];
		[alert runModal];
	}
}

- (BOOL)applicationShouldHandleReopen:(NSApplication*)theApplication hasVisibleWindows:(BOOL)flag
{
	BOOL disableUntitledAtReactivationPrefs = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsDisableNewDocumentAtReactivationKey];
	BOOL showFavoritesInsteadPrefs          = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsShowFavoritesInsteadOfUntitledKey];
	return flag || !disableUntitledAtReactivationPrefs || showFavoritesInsteadPrefs;
}

// ===========================
// = Application Termination =
// ===========================

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender
{
	return [DocumentWindowController applicationShouldTerminate:sender];
}
@end
