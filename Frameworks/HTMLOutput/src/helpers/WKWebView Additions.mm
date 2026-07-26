#import <OakAppKit/OakPasteboard.h>
#import <OakFoundation/OakFoundation.h>
#import <OakFoundation/OakFindProtocol.h>
#import <OakFoundation/NSString Additions.h>
#import <document/OakDocument.h>
#import <document/OakDocumentController.h>
#import <ns/ns.h>

/*
	Find, “Use Selection for Find”, and View Source for the HTML output window.

	All of this used to walk the DOM synchronously through the legacy WebView
	(selectedDOMRange, createNodeIterator, searchFor:direction:caseSensitive:wrap:,
	WebDataSource data). None of it exists on WKWebView: the content lives in
	another process, so the selection and the source are fetched with
	-evaluateJavaScript: and the search is -findString:withConfiguration:.

	The visible consequence is that these actions became asynchronous. They are all
	responder-chain actions whose results land in the UI rather than being returned
	to a caller, so no caller changes — but a find result now arrives a runloop turn
	later than it used to.
*/
@interface WKWebView (OakFindNextPrevious)
- (void)performFindOperation:(id <OakFindServerProtocol>)aFindServer;

- (IBAction)findNext:(id)sender;
- (IBAction)findPrevious:(id)sender;

- (IBAction)copySelectionToFindPboard:(id)sender;
- (IBAction)copySelectionToReplacePboard:(id)sender;
@end

@implementation WKWebView (OakFindNextPrevious)
- (void)withSelection:(void(^)(NSString* selection))handler
{
	[self evaluateJavaScript:@"window.getSelection().toString()" completionHandler:^(id result, NSError* error){
		NSString* str = [result isKindOfClass:[NSString class]] ? result : nil;
		handler(OakIsEmptyString(str) ? nil : str);
	}];
}

- (void)oakFindString:(NSString*)aString forward:(BOOL)forwardFlag caseSensitive:(BOOL)caseSensitiveFlag wrap:(BOOL)wrapFlag completionHandler:(void(^)(BOOL didFind))handler
{
	WKFindConfiguration* config = [[WKFindConfiguration alloc] init];
	config.backwards     = !forwardFlag;
	config.caseSensitive = caseSensitiveFlag;
	config.wraps         = wrapFlag;

	[self findString:aString withConfiguration:config completionHandler:^(WKFindResult* result){
		if(handler)
			handler(result.matchFound);
	}];
}

- (IBAction)copySelectionToFindPboard:(id)sender
{
	[self withSelection:^(NSString* str){
		if(str)
				[OakPasteboard.findPasteboard addEntryWithString:str];
		else	NSBeep();
	}];
}

- (IBAction)copySelectionToReplacePboard:(id)sender
{
	[self withSelection:^(NSString* str){
		if(str)
				[OakPasteboard.replacePasteboard addEntryWithString:str];
		else	NSBeep();
	}];
}

- (void)performFindOperation:(id <OakFindServerProtocol>)aFindServer
{
	switch(aFindServer.findOperation)
	{
		case kFindOperationFind:
		case kFindOperationFindInSelection:
		{
			BOOL backwards  = aFindServer.findOptions & find::backwards;
			BOOL ignoreCase = aFindServer.findOptions & find::ignore_case;
			BOOL wrapAround = aFindServer.findOptions & find::wrap_around;

			[self oakFindString:aFindServer.findString forward:!backwards caseSensitive:!ignoreCase wrap:wrapAround completionHandler:^(BOOL didFind){
				if(!didFind)
				{
					[aFindServer didFind:0 occurrencesOf:aFindServer.findString atPosition:text::pos_t::undefined wrapped:NO];
					return;
				}

				// The old code reported the newly selected text; read it back, since
				// the find itself no longer returns it.
				[self withSelection:^(NSString* str){
					[aFindServer didFind:1 occurrencesOf:str ?: aFindServer.findString atPosition:text::pos_t::undefined wrapped:NO];
				}];
			}];
		}
		break;
	}
}

- (IBAction)findNext:(id)sender
{
	OakPasteboardEntry* entry = [OakPasteboard.findPasteboard current];
	if(OakNotEmptyString(entry.string))
		[self oakFindString:entry.string forward:YES caseSensitive:![NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsFindIgnoreCase] wrap:[NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsFindWrapAround] completionHandler:nil];
}

- (IBAction)findPrevious:(id)sender
{
	OakPasteboardEntry* entry = [OakPasteboard.findPasteboard current];
	if(OakNotEmptyString(entry.string))
		[self oakFindString:entry.string forward:NO caseSensitive:![NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsFindIgnoreCase] wrap:[NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsFindWrapAround] completionHandler:nil];
}

- (void)viewSource:(id)sender
{
	/*
		WebDataSource handed back the bytes as received, so the old implementation
		decoded them itself and had a hard error for unknown encodings. There is no
		equivalent here: outerHTML is the *parsed* document serialised back out, and
		always a string — so the encoding handling goes away, at the cost of showing
		the DOM rather than the literal bytes.
	*/
	[self evaluateJavaScript:@"document.documentElement.outerHTML" completionHandler:^(id result, NSError* error){
		NSString* str = [result isKindOfClass:[NSString class]] ? result : nil;
		if(!str)
		{
			os_log_error(OS_LOG_DEFAULT, "HTMLOutput: cannot read page source: %{public}@", error.localizedDescription);
			NSBeep();
			return;
		}

		NSString* name = OakNotEmptyString(self.title) ? self.title : nil;
		OakDocument* doc = [OakDocument documentWithString:str fileType:@"text.html.basic" customName:name];
		[OakDocumentController.sharedInstance showDocument:doc inProject:nil bringToFront:YES];
	}];
}
@end
