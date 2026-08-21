#import "OakChooserMarkup.h"
#import <OakAppKit/NSColor Additions.h>
#import <ns/ns.h>

// Moved verbatim from OakChooser.mm (2026-08-20); see OakChooserMarkup.h for why it lives
// on its own now.
NSMutableAttributedString* CreateAttributedStringWithMarkedUpRanges (std::string const& in, std::vector< std::pair<size_t, size_t> > const& ranges, NSLineBreakMode lineBreakMode)
{
	NSMutableParagraphStyle* paragraphStyle = [[NSMutableParagraphStyle alloc] init];
	[paragraphStyle setLineBreakMode:lineBreakMode];

	NSDictionary* baseAttributes      = @{ NSParagraphStyleAttributeName: paragraphStyle };
	NSDictionary* highlightAttributes = @{
		NSParagraphStyleAttributeName:  paragraphStyle,
		NSBackgroundColorAttributeName: [NSColor tmMatchedTextBackgroundColor],
		NSUnderlineStyleAttributeName:  @(NSUnderlineStyleSingle),
		NSUnderlineColorAttributeName:  [NSColor tmMatchedTextUnderlineColor],
	};

	NSMutableAttributedString* res = [[NSMutableAttributedString alloc] init];

	size_t from = 0;
	for(auto range : ranges)
	{
		[res appendAttributedString:[[NSAttributedString alloc] initWithString:(to_ns(in.substr(from, range.first - from)) ?: @"?") attributes:baseAttributes]];
		[res appendAttributedString:[[NSAttributedString alloc] initWithString:(to_ns(in.substr(range.first, range.second - range.first)) ?: @"?") attributes:highlightAttributes]];
		from = range.second;
	}
	if(from < in.size())
		[res appendAttributedString:[[NSAttributedString alloc] initWithString:(to_ns(in.substr(from)) ?: @"?") attributes:baseAttributes]];

	return res;
}
