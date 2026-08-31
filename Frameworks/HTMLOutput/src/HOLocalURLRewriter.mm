#import "HOLocalURLRewriter.h"
#import <string>

// Same scheme *and* same host as the job URL (x-txmt-filehandle://job/…), so the
// rewritten sub-resources are same-origin with the page rather than merely
// same-scheme.
static char const* const kFileURLPrefix  = "file://";
static char const* const kLocalURLPrefix = "x-txmt-filehandle://job/__tm_local__";

/*
	Replaces every complete `file://` in `chunk` and returns whatever trailing bytes
	could still turn out to be the start of one. Those are held back and prepended
	to the next chunk — without that, a `file://` straddling a read boundary would
	slip through unrewritten.
*/
static std::string RewriteLocalURLs (std::string const& chunk, std::string& carry)
{
	std::string const data = carry + chunk;
	size_t const fileLen   = strlen(kFileURLPrefix);
	carry.clear();

	std::string out;
	out.reserve(data.size());

	size_t pos = 0;
	while(true)
	{
		size_t hit = data.find(kFileURLPrefix, pos);
		if(hit == std::string::npos)
			break;
		out.append(data, pos, hit - pos);
		out.append(kLocalURLPrefix);
		pos = hit + fileLen;
	}

	// Longest suffix of the remainder that is a proper prefix of "file://".
	std::string const rest = data.substr(pos);
	size_t keep = 0;
	for(size_t k = std::min(fileLen - 1, rest.size()); k > 0; --k)
	{
		if(rest.compare(rest.size() - k, k, kFileURLPrefix, k) == 0)
		{
			keep = k;
			break;
		}
	}

	out.append(rest, 0, rest.size() - keep);
	carry = rest.substr(rest.size() - keep);
	return out;
}

// ==========================================================================
// = The rewriter, as an object that owns its carry                         =
// ==========================================================================
//
// RewriteLocalURLs is the subtle part of this file and it was unreachable: a
// static function taking a `std::string&` cannot be called from a test, and the
// carry it threads through the read loop is exactly what makes it worth testing.
// A URL split across two reads is a bug that only appears under load.
//
// So the carry becomes owned state and the entry point becomes ObjC-clean. NSData
// rather than NSString on purpose: this is a byte stream, and a chunk boundary
// can fall inside a UTF-8 sequence — going through NSString would corrupt exactly
// the case the carry exists to handle.
@implementation HOLocalURLRewriter
{
	std::string _carry;
}

- (NSData*)rewriteChunk:(NSData*)chunk
{
	std::string const rewritten = RewriteLocalURLs(std::string((char const*)chunk.bytes, chunk.length), _carry);
	return [NSData dataWithBytes:rewritten.data() length:rewritten.size()];
}

// Whatever is being held back as a possible partial `file://`. At EOF it was
// never a real one and the caller emits it verbatim.
- (NSData*)carry
{
	return [NSData dataWithBytes:_carry.data() length:_carry.size()];
}
@end
