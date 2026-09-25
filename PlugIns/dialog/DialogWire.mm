#import "DialogWire.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>

// A cap, so a peer cannot make either side allocate without bound by claiming a
// huge length. A request carries argv and the environment; the largest plausible
// one is tens of kilobytes.
static uint32_t const kDialogMaxMessageBytes = 4 * 1024 * 1024;

NSString* DialogSocketPathForServerPID (pid_t pid)
{
	// In the same place and shape as the sockets `mate` and the commit window use
	// — one convention rather than three. The uid is in the name because /tmp is
	// shared between users; the mode on the socket is what keeps them out, but a
	// name collision would be its own failure.
	return [NSString stringWithFormat:@"/tmp/textmate-dialog-%d-%d.sock", getuid(), pid];
}

// Both loops exist because a socket write or read may be partial, and a plist
// that arrives in two pieces is a plist that fails to parse.
static BOOL DialogWriteAll (int fd, void const* bytes, size_t length)
{
	uint8_t const* p = (uint8_t const*)bytes;
	while(length)
	{
		ssize_t n = write(fd, p, length);
		if(n > 0)          { p += n; length -= n; }
		else if(n == -1 && errno == EINTR) continue;
		else               return NO;
	}
	return YES;
}

static BOOL DialogReadAll (int fd, void* bytes, size_t length)
{
	uint8_t* p = (uint8_t*)bytes;
	while(length)
	{
		ssize_t n = read(fd, p, length);
		if(n > 0)              { p += n; length -= n; }
		else if(n == 0)        return NO;   // peer closed
		else if(errno == EINTR) continue;
		else                   return NO;
	}
	return YES;
}

BOOL DialogWriteRequest (int fd, NSDictionary* request)
{
	NSError* error = nil;
	NSData* data = [NSPropertyListSerialization dataWithPropertyList:request format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
	if(!data || data.length > kDialogMaxMessageBytes)
		return NO;

	uint32_t length = OSSwapHostToBigInt32((uint32_t)data.length);
	if(!DialogWriteAll(fd, &length, sizeof(length)))
		return NO;
	return DialogWriteAll(fd, data.bytes, data.length);
}

NSDictionary* DialogReadRequest (int fd)
{
	uint32_t length = 0;
	if(!DialogReadAll(fd, &length, sizeof(length)))
		return nil;

	length = OSSwapBigToHostInt32(length);
	if(length == 0 || length > kDialogMaxMessageBytes)
		return nil;

	NSMutableData* data = [NSMutableData dataWithLength:length];
	if(!data || !DialogReadAll(fd, data.mutableBytes, length))
		return nil;

	// Only a dictionary is ever sent, and only a dictionary is accepted — the
	// format is immutable and unarchiving it cannot construct arbitrary classes,
	// which is the part Distributed Objects could not promise.
	id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nullptr error:nullptr];
	return [plist isKindOfClass:NSDictionary.class] ? plist : nil;
}
