#import "CWWire.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>

// A cap, so a peer cannot make either side allocate without bound by claiming a
// huge length. A commit request carries argv and the environment; the largest
// plausible one is tens of kilobytes.
static uint32_t const kCWMaxMessageBytes = 4 * 1024 * 1024;

NSString* CWSocketPathForApplicationPID (pid_t pid)
{
	// In the same place, and with the same shape, as the socket `mate` uses —
	// one convention rather than two. The uid is in the name because /tmp is
	// shared between users; the mode on the socket is what actually keeps them
	// out, but a name collision would be its own failure.
	return [NSString stringWithFormat:@"/tmp/textmate-commit-%d-%d.sock", getuid(), pid];
}

// Both loops below exist because a socket write or read may be partial, and a
// plist that arrives in two pieces is a plist that fails to parse. Neither is
// hypothetical for an environment dictionary of a few kilobytes.
static BOOL CWWriteAll (int fd, void const* bytes, size_t length)
{
	uint8_t const* p = (uint8_t const*)bytes;
	while(length)
	{
		ssize_t n = write(fd, p, length);
		if(n > 0)
		{
			p      += n;
			length -= n;
		}
		else if(n == -1 && errno == EINTR)
		{
			continue;
		}
		else
		{
			return NO;
		}
	}
	return YES;
}

static BOOL CWReadAll (int fd, void* bytes, size_t length)
{
	uint8_t* p = (uint8_t*)bytes;
	while(length)
	{
		ssize_t n = read(fd, p, length);
		if(n > 0)
		{
			p      += n;
			length -= n;
		}
		else if(n == 0)
		{
			return NO;   // peer closed
		}
		else if(errno == EINTR)
		{
			continue;
		}
		else
		{
			return NO;
		}
	}
	return YES;
}

BOOL CWWritePlist (int fd, NSDictionary* plist)
{
	NSError* error = nil;
	NSData* data = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
	if(!data || data.length > kCWMaxMessageBytes)
		return NO;

	uint32_t length = OSSwapHostToBigInt32((uint32_t)data.length);
	if(!CWWriteAll(fd, &length, sizeof(length)))
		return NO;
	return CWWriteAll(fd, data.bytes, data.length);
}

NSDictionary* CWReadPlist (int fd)
{
	uint32_t length = 0;
	if(!CWReadAll(fd, &length, sizeof(length)))
		return nil;

	length = OSSwapBigToHostInt32(length);
	if(length == 0 || length > kCWMaxMessageBytes)
		return nil;

	NSMutableData* data = [NSMutableData dataWithLength:length];
	if(!data || !CWReadAll(fd, data.mutableBytes, length))
		return nil;

	// Only a dictionary of plist types is ever sent, and only a dictionary is
	// accepted — the format is immutable and unarchiving it cannot construct
	// arbitrary classes, which is the part Distributed Objects could not promise.
	id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nullptr error:nullptr];
	return [plist isKindOfClass:NSDictionary.class] ? plist : nil;
}
