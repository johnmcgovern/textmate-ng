#import "HOWebViewDelegateHelper.h"
#import "HOBrowserView.h"
#import <OakAppKit/NSAlert Additions.h>
#import <OakFoundation/NSString Additions.h>
#import <io/path.h>
#import <oak/debug.h>

@implementation HOWebViewDelegateHelper
// ================
// = WKUIDelegate =
// ================

- (void)webView:(WKWebView*)webView runJavaScriptAlertPanelWithMessage:(NSString*)message initiatedByFrame:(WKFrameInfo*)frame completionHandler:(void(^)(void))completionHandler
{
	NSAlert* alert = [NSAlert tmAlertWithMessageText:NSLocalizedString(@"Script Message", @"JavaScript alert title") informativeText:message buttons:NSLocalizedString(@"OK", @"JavaScript alert confirmation"), nil];
	[alert beginSheetModalForWindow:webView.window completionHandler:^(NSModalResponse){
		completionHandler();
	}];
}

- (void)webView:(WKWebView*)webView runJavaScriptConfirmPanelWithMessage:(NSString*)message initiatedByFrame:(WKFrameInfo*)frame completionHandler:(void(^)(BOOL result))completionHandler
{
	NSAlert* alert        = [[NSAlert alloc] init];
	alert.messageText     = NSLocalizedString(@"Script Message", @"JavaScript alert title");
	alert.informativeText = message;
	[alert addButtons:NSLocalizedString(@"OK", @"JavaScript alert confirmation"), NSLocalizedString(@"Cancel", @"JavaScript alert cancel"), nil];

	// A sheet, where the legacy WebUIDelegate ran this one modally: WKWebView
	// cannot block for the answer, so the completion handler carries it back.
	[alert beginSheetModalForWindow:webView.window completionHandler:^(NSModalResponse returnCode){
		completionHandler(returnCode == NSAlertFirstButtonReturn);
	}];
}

- (void)webView:(WKWebView*)webView runOpenPanelWithParameters:(WKOpenPanelParameters*)parameters initiatedByFrame:(WKFrameInfo*)frame completionHandler:(void(^)(NSArray<NSURL*>* URLs))completionHandler
{
	NSOpenPanel* panel = [NSOpenPanel openPanel];
	panel.directoryURL          = [NSURL fileURLWithPath:NSHomeDirectory()];
	panel.allowsMultipleSelection = parameters.allowsMultipleSelection;
	[panel beginSheetModalForWindow:webView.window completionHandler:^(NSModalResponse returnCode){
		completionHandler(returnCode == NSModalResponseOK ? panel.URLs : nil);
	}];
}

- (WKWebView*)webView:(WKWebView*)webView createWebViewWithConfiguration:(WKWebViewConfiguration*)configuration forNavigationAction:(WKNavigationAction*)navigationAction windowFeatures:(WKWindowFeatures*)windowFeatures
{
	NSPoint origin = [webView.window cascadeTopLeftFromPoint:NSMakePoint(NSMinX(webView.window.frame), NSMaxY(webView.window.frame))];
	origin.y -= NSHeight(webView.window.frame);

	// WebKit requires the returned view to be built from the configuration it
	// supplies here — creating our own would sever the script relationship with
	// the opener and raise.
	HOBrowserView* view = [[HOBrowserView alloc] initWithFrame:NSZeroRect configuration:configuration];
	NSWindow* window = [[NSWindow alloc] initWithContentRect:(NSRect){origin, NSMakeSize(750, 800)}
	                                               styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskMiniaturizable)
	                                                 backing:NSBackingStoreBuffered
	                                                   defer:NO];
	[window bind:NSTitleBinding toObject:view.webView withKeyPath:@"title" options:nil];
	[window setContentView:view];

	// WebKit loads navigationAction.request into the new view itself; loading it
	// here as well would double-fetch (and re-run the command for a job URL).

	__attribute__ ((unused)) CFTypeRef dummy = CFBridgingRetain(window);
	[window setReleasedWhenClosed:YES];

	return view.webView;
}

- (void)webViewDidClose:(WKWebView*)webView
{
	if(![webView tryToPerform:@selector(toggleHTMLOutput:) with:self])
		[webView tryToPerform:@selector(performClose:) with:self];
}
@end
