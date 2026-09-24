//
//  TMDHTMLTips.mm
//
//  Created by Ciarán Walsh on 2007-08-19.
//

#import "TMDHTMLTips.h"
#import <WebKit/WebKit.h>

// **WKWebView since 2026-09-24.** This was the last use of Apple's deprecated
// WebView in the shipped application. What changed, and why each piece looks the
// way it does:
//
// - Fonts. WebPreferences set the standard family and the two default sizes;
//   WKWebView has no equivalent, so the same three values go into the page's
//   stylesheet instead.
// - Measuring. WebView evaluated script synchronously, so the tooltip could size
//   itself in one call. WKWebView's evaluateJavaScript is asynchronous, so the
//   measure-then-show step runs in its completion handler. The view is made large
//   *before* the load, not after, so the page lays out at the width it will be
//   measured at.
// - Transparency. drawsBackground through KVC, as AboutWindowController already
//   does for its WKWebView.
// - JavaScript stays enabled, as it was: tooltips are bundle output and a bundle
//   may rely on it. The window still ignores the mouse, so nothing in a tooltip
//   can be clicked.

/*
"$DIALOG" tooltip --text '‘foobar’'
"$DIALOG" tooltip --html '<h1>‘foobar’</h1>'
*/

@interface TMDHTMLTip () <WKNavigationDelegate>
{
	WKWebView* webView;
	NSString* fontFamily;
	NSInteger fontSize;

	NSDate* didOpenAtDate; // ignore mouse moves for the next second
	NSPoint mousePositionWhenOpened;
}
- (void)setContent:(NSString*)content transparent:(BOOL)transparent;
- (void)runUntilUserActivity:(id)sender;
@end

@implementation TMDHTMLTip
// ==================
// = Setup/teardown =
// ==================
+ (void)showWithContent:(NSString*)content atLocation:(NSPoint)point transparent:(BOOL)transparent
{
	// Deferred a turn. This is called from inside tm_dialog2's Distributed
	// Objects request, and creating a WKWebView starts a WebContent process —
	// which, done from inside that request, never finished: tm_dialog2 waited
	// forever for a reply and no tooltip appeared. The legacy WebView had no
	// second process, so it got away with it. Measured both ways on the same
	// machine: the legacy build returned at once and made its window; this port,
	// before the deferral, hung. Letting the request return first costs nothing
	// the user can see — the tooltip was always shown asynchronously, after load.
	content = [content copy];
	dispatch_async(dispatch_get_main_queue(), ^{
		TMDHTMLTip* tip = [TMDHTMLTip new];
		[tip setFrameTopLeftPoint:point];
		[tip setContent:content transparent:transparent]; // The tooltip will show itself automatically when the HTML is loaded
	});
}

- (id)init;
{
	if(self = [self initWithContentRect:NSMakeRect(0, 0, 1, 1) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO])
	{
		// Since we are relying on `setReleaseWhenClosed:`, we need to ensure that we are over-retained.
		CFBridgingRetain(self);
		[self setReleasedWhenClosed:YES];
		[self setAlphaValue:0.97];
		[self setOpaque:NO];
		[self setBackgroundColor:[NSColor colorWithDeviceRed:1.0 green:0.96 blue:0.76 alpha:1.0]];
		[self setBackgroundColor:[NSColor clearColor]];
		[self setHasShadow:YES];
		[self setLevel:NSStatusWindowLevel];
		[self setHidesOnDeactivate:YES];
		[self setIgnoresMouseEvents:YES];

		NSString* fontName = [NSUserDefaults.standardUserDefaults stringForKey:@"fontName"];
		fontSize = [NSUserDefaults.standardUserDefaults integerForKey:@"fontSize"] ?: 11;
		NSFont* font = (fontName ? [NSFont fontWithName:fontName size:fontSize] : nil) ?: [NSFont userFixedPitchFontOfSize:fontSize];
		fontFamily = [font familyName];

		// A non-persistent store: a tooltip has no business keeping cookies or a
		// cache between showings, which is what WebCacheModelDocumentViewer and
		// usesPageCache=NO were saying for the old view.
		WKWebViewConfiguration* configuration = [WKWebViewConfiguration new];
		configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];

		webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
		[webView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
		webView.navigationDelegate = self;
		[webView setValue:@NO forKey:@"drawsBackground"];

		[self setContentView:webView];
	}
	return self;
}

// ===========
// = Webview =
// ===========
- (NSRect)visibleFrameOfScreenAtTopLeft
{
	NSPoint pos = NSMakePoint([self frame].origin.x, [self frame].origin.y + [self frame].size.height);
	for(NSScreen* candidate in [NSScreen screens])
	{
		if(NSPointInRect(pos, [candidate frame]))
			return [candidate visibleFrame];
	}
	return [[NSScreen mainScreen] visibleFrame];
}

- (void)setContent:(NSString*)content transparent:(BOOL)transparent
{
	// The page lays out at the viewport's width, so the viewport is made large
	// now — the old view did this just before measuring, which a synchronous
	// layout allowed. Two thirds of the screen, as before.
	NSPoint topLeft = NSMakePoint(NSMinX([self frame]), NSMaxY([self frame]));
	NSRect screenFrame = [self visibleFrameOfScreenAtTopLeft];
	[self setContentSize:NSMakeSize(screenFrame.size.width - screenFrame.size.width / 3.0, screenFrame.size.height)];
	[self setFrameTopLeftPoint:topLeft];

	// The font family is quoted as a CSS string, so a backslash or a quote in its
	// name cannot end the declaration early.
	NSString* family = [[fontFamily stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];

	NSString* fullContent =	@"<html>"
				@"<head>"
				@"  <style type='text/css' media='screen'>"
				@"      body {"
				@"          background: %@;"
				@"          margin: 0;"
				@"          padding: 2px;"
				@"          overflow: hidden;"
				@"          display: table-cell;"
				@"          max-width: 800px;"
				@"          font-family: '%@';"
				@"          font-size: %ldpx;"
				@"      }"
				@"      pre, code, tt, kbd, samp { font-size: %ldpx; }"
				@"      pre { white-space: pre-wrap; }"
				@"  </style>"
				@"</head>"
				@"<body>%@</body>"
				@"</html>";

	fullContent = [NSString stringWithFormat:fullContent, transparent ? @"transparent" : @"#F6EDC3", family, (long)fontSize, (long)fontSize, content];
	[webView loadHTMLString:fullContent baseURL:nil];
}

- (void)sizeToContentWidth:(double)width height:(double)height
{
	// Current tooltip position
	NSPoint pos = NSMakePoint([self frame].origin.x, [self frame].origin.y + [self frame].size.height);
	NSRect screenFrame = [self visibleFrameOfScreenAtTopLeft];

	[webView setFrameSize:NSMakeSize(width, height)];

	NSRect frame      = [self frameRectForContentRect:[webView frame]];
	frame.size.width  = std::min(NSWidth(frame), NSWidth(screenFrame));
	frame.size.height = std::min(NSHeight(frame), NSHeight(screenFrame));
	[self setFrame:frame display:NO];

	pos.x = std::max(NSMinX(screenFrame), std::min(pos.x, NSMaxX(screenFrame)-NSWidth(frame)));
	pos.y = std::min(std::max(NSMinY(screenFrame)+NSHeight(frame), pos.y), NSMaxY(screenFrame));

	[self setFrameTopLeftPoint:pos];
}

- (void)delayedShow:(id)sender
{
	[self orderFront:self];
	[self runUntilUserActivity:self];
}

- (void)webView:(WKWebView*)sender didFinishNavigation:(WKNavigation*)navigation
{
	// One round trip for both numbers. The show itself is deferred a turn, as it
	// always was: runUntilUserActivity: spins its own event loop, and running
	// that from inside WebKit's callback would hold WebKit's stack open for the
	// tooltip's whole lifetime.
	[sender evaluateJavaScript:@"(function(){ var r = document.body.getBoundingClientRect(); return [r.right, r.bottom]; })()" completionHandler:^(id result, NSError* error){
		NSArray* size = [result isKindOfClass:[NSArray class]] ? result : nil;
		double width  = size.count == 2 ? ceil([size[0] doubleValue]) : 0;
		double height = size.count == 2 ? ceil([size[1] doubleValue]) : 0;
		if(error || width < 1 || height < 1)
		{
			NSLog(@"HTML tooltip could not measure its content: %@", error ?: @"empty");
			[self orderOut:self];
			return;
		}
		[self sizeToContentWidth:width height:height];
		[self performSelector:@selector(delayedShow:) withObject:self afterDelay:0];
	}];
}

// ==================
// = Event handling =
// ==================
- (BOOL)shouldCloseForMousePosition:(NSPoint)aPoint
{
	CGFloat ignorePeriod = [NSUserDefaults.standardUserDefaults floatForKey:@"OakToolTipMouseMoveIgnorePeriod"];
	if(-[didOpenAtDate timeIntervalSinceNow] < ignorePeriod)
		return NO;

	if(NSEqualPoints(mousePositionWhenOpened, NSZeroPoint))
	{
		mousePositionWhenOpened = aPoint;
		return NO;
	}

	NSPoint const& p = mousePositionWhenOpened;
	CGFloat deltaX = p.x - aPoint.x;
	CGFloat deltaY = p.y - aPoint.y;
	CGFloat dist = sqrt(deltaX * deltaX + deltaY * deltaY);

	CGFloat moveThreshold = [NSUserDefaults.standardUserDefaults floatForKey:@"OakToolTipMouseDistanceThreshold"];
	return dist > moveThreshold;
}

- (void)runUntilUserActivity:(id)sender
{
	[self setValue:[NSDate date] forKey:@"didOpenAtDate"];
	mousePositionWhenOpened = NSZeroPoint;

	NSWindow* keyWindow = [NSApp keyWindow];
	BOOL didAcceptMouseMovedEvents = [keyWindow acceptsMouseMovedEvents];
	[keyWindow setAcceptsMouseMovedEvents:YES];

	BOOL slowFadeOut = NO;
	while(NSEvent* event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate distantFuture] inMode:NSDefaultRunLoopMode dequeue:YES])
	{
		[NSApp sendEvent:event];

		if([event type] == NSEventTypeLeftMouseDown || [event type] == NSEventTypeRightMouseDown || [event type] == NSEventTypeOtherMouseDown || [event type] == NSEventTypeKeyDown || [event type] == NSEventTypeScrollWheel)
			break;

		if([event type] == NSEventTypeMouseMoved && [self shouldCloseForMousePosition:[NSEvent mouseLocation]])
		{
			slowFadeOut = YES;
			break;
		}

		if(keyWindow != [NSApp keyWindow] || ![NSApp isActive])
			break;
	}

	[keyWindow setAcceptsMouseMovedEvents:didAcceptMouseMovedEvents];


	[self fadeOutSlowly:slowFadeOut];
}

// =============
// = Animation =
// =============
- (void)fadeOutSlowly:(BOOL)slowly
{
	[NSAnimationContext beginGrouping];

	[NSAnimationContext currentContext].duration = slowly ? 0.5 : 0.25;
	[NSAnimationContext currentContext].completionHandler = ^{
		[self orderOut:self];
	};

	[self.animator setAlphaValue:0];

	[NSAnimationContext endGrouping];
}
@end
