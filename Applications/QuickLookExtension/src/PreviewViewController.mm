#import "TMQLRender.h"
#import <Quartz/Quartz.h>
#import <oak/log.h>

static os_log_t const kLogQuickLook = os_log_create(OAK_LOG_SUBSYSTEM, "quicklook");

// A preview of a huge file is still a preview: the old generator capped reads at
// 20 KB and this keeps that, because the cost here is parse time on the QL host's
// clock, not memory.
static size_t const kMaxPreviewSize = 20480;

// ObjC++, deliberately, in a project that is otherwise moving Swift-ward:
// PlugInKit resolves NSExtensionPrincipalClass through the ObjC runtime, and a
// Swift class does not answer to its @objc(…) name there. Measured, not assumed —
// an identical Swift controller was instantiated but never had loadView or
// -preparePreviewOfFileAtURL:completionHandler: called, while the ObjC one is
// driven normally. See PROJECT_PHASES.md, "QuickLook".
@interface PreviewViewController : NSViewController <QLPreviewingController>
@property (nonatomic) NSScrollView* scrollView;
@property (nonatomic) NSTextView* textView;
@end

@implementation PreviewViewController
- (void)loadView
{
	_scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
	_scrollView.hasVerticalScroller   = YES;
	_scrollView.hasHorizontalScroller = YES;
	_scrollView.autohidesScrollers    = YES;

	_textView = [[NSTextView alloc] initWithFrame:_scrollView.bounds];
	_textView.editable            = NO;
	_textView.selectable          = YES;
	_textView.richText            = YES;
	_textView.textContainerInset  = NSMakeSize(8, 8);
	_textView.autoresizingMask    = NSViewWidthSizable;
	// Quick Look sizes the preview itself; the text view must not wrap to a width
	// it does not have yet, or long lines reflow and then never un-reflow.
	_textView.horizontallyResizable = YES;
	_textView.textContainer.widthTracksTextView = NO;
	_textView.textContainer.containerSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);

	_scrollView.documentView = _textView;
	self.view = _scrollView;
}

- (void)preparePreviewOfFileAtURL:(NSURL*)url completionHandler:(void(^)(NSError*))handler
{
	@autoreleasepool {
		NSColor* background = nil;
		NSAttributedString* highlighted = TMQLCreateAttributedString(url, kMaxPreviewSize, &background);

		if(highlighted)
		{
			[_textView.textStorage setAttributedString:highlighted];
			if(background)
			{
				_textView.backgroundColor = background;
				_scrollView.backgroundColor = background;
			}
		}
		else
		{
			// No grammar for this file — show it as plain text rather than
			// nothing, which is what the legacy generator did by handing the
			// data back to the system as public.plain-text.
			os_log_debug(kLogQuickLook, "[PreviewViewController] No highlighting for %{public}@; falling back to plain text", url.path);

			NSString* plain = [[NSString alloc] initWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nullptr];
			if(!plain)
				plain = [[NSString alloc] initWithContentsOfURL:url encoding:NSISOLatin1StringEncoding error:nullptr];

			_textView.font = [NSFont userFixedPitchFontOfSize:0];
			_textView.string = plain ?: @"";
			if(!plain)
			{
				handler([NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{
					NSLocalizedDescriptionKey: @"Unable to read this file as text."
				}]);
				return;
			}
		}

		handler(nil);
	}
}
@end
