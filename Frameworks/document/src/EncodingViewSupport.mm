#import "EncodingViewSupport.h"
#import <OakFoundation/NSString Additions.h>
#import <text/transcode.h>
#import <oak/oak.h>
#import <ns/ns.h>

template <typename _InputIter>
size_t newline_size (_InputIter first, _InputIter const& last)
{
	for(auto str : { "\r\n", "\n", "\r" })
	{
		if(oak::has_prefix(first, last, str, str + strlen(str)))
			return strlen(str);
	}
	return 0;
}

static void append (NSMutableAttributedString* dst, char const* first, char const* last, NSDictionary* styles)
{
	NSString* str = [NSString stringWithUTF8String:first length:last - first] ?: @"�";
	[dst appendAttributedString:[[NSAttributedString alloc] initWithString:str attributes:styles]];
}

static NSAttributedString* convert_and_highlight (char const* first, char const* last, std::string const& encodeFrom = "UTF-8", std::string const& encodeTo = "UTF-8", bool* success = nullptr)
{
	std::set<ptrdiff_t> offsets;
	auto lastPos = first;
	for(auto it = first; it != last; ++it)
	{
		if(*it > 0x7F)
		{
			if(++lastPos != it)
				offsets.insert(std::distance(first, it));
			lastPos = it;
		}
	}

	text::transcode_t transcode(encodeFrom, encodeTo);
	if(!transcode)
		return nil;

	std::string dst;

	std::set<size_t> decodedOffsets;
	size_t from = 0;
	for(size_t to : offsets)
	{
		transcode(first + from, first + to, back_inserter(dst));
		decodedOffsets.insert(dst.size());
		from = to;
	}
	transcode(transcode(first + from, last, back_inserter(dst)));

	if(success)
		*success = transcode.invalid_count() == 0;

	NSMutableAttributedString* output = [[NSMutableAttributedString alloc] init];

	NSDictionary* regularStyle = @{
		NSFontAttributeName:            [NSFont userFixedPitchFontOfSize:0],
		NSForegroundColorAttributeName: [NSColor grayColor],
	};
	NSDictionary* lineHighlightStyle = @{
		NSFontAttributeName:            [NSFont userFixedPitchFontOfSize:0],
		NSForegroundColorAttributeName: [NSColor grayColor],
		NSBackgroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.9 alpha:1],
	};
	NSDictionary* characterHighlightStyle = @{
		NSFontAttributeName:            [NSFont userFixedPitchFontOfSize:0],
		NSBackgroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.9 alpha:1],
	};

	size_t bol = 0;
	auto offset = decodedOffsets.begin();
	for(size_t eol = 0; eol < dst.size(); ++eol)
	{
		static std::string const newlines[] = { "\r\n", "\n", "\r" };

		auto it = std::find_if(std::begin(newlines), std::end(newlines), [&](std::string const& str){ return oak::has_prefix(dst.begin() + eol, dst.end(), str.begin(), str.end()); });
		if(it == std::end(newlines))
			continue;

		size_t crlf = it->size();
		if(offset != decodedOffsets.end() && *offset < eol)
		{
			while(offset != decodedOffsets.end() && *offset < eol)
			{
				if(*offset < bol)
				{
					++offset;
					continue;
				}

				append(output, dst.data() + bol, dst.data() + *offset, lineHighlightStyle);

				bol = *offset;
				while(bol != dst.size() && dst[bol] > 0x7F)
					++bol;

				append(output, dst.data() + *offset, dst.data() + bol, characterHighlightStyle);

				++offset;
			}
			append(output, dst.data() + bol, dst.data() + eol + crlf, lineHighlightStyle);
		}
		else
		{
			append(output, dst.data() + bol, dst.data() + eol + crlf, regularStyle);
		}

		bol = eol + crlf;
		eol += crlf - 1;
	}

	if(bol < dst.size())
		append(output, dst.data() + bol, dst.data() + dst.size(), regularStyle);

	return output;
}

@implementation EncodingViewSupport
+ (NSAttributedString*)previewForData:(NSData*)data length:(NSUInteger)length encoding:(NSString*)encodeFrom couldConvert:(BOOL*)couldConvert
{
	bool success = true;
	char const* bytes = (char const*)data.bytes;
	NSAttributedString* res = convert_and_highlight(bytes, bytes + MIN(data.length, length), to_s(encodeFrom), "UTF-8", &success);
	if(couldConvert)
		*couldConvert = success;
	return res;
}
@end
