#import "Dialog1Wire.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>

static uint32_t const kDialog1MaxMessageBytes = 4 * 1024 * 1024;

NSString* Dialog1SocketPathForServerPID (pid_t pid)
{
	return [NSString stringWithFormat:@"/tmp/textmate-dialog1-%d-%d.sock", getuid(), pid];
}

static BOOL WriteAll (int fd, void const* bytes, size_t length)
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

static BOOL ReadAll (int fd, void* bytes, size_t length)
{
	uint8_t* p = (uint8_t*)bytes;
	while(length)
	{
		ssize_t n = read(fd, p, length);
		if(n > 0)              { p += n; length -= n; }
		else if(n == 0)        return NO;
		else if(errno == EINTR) continue;
		else                   return NO;
	}
	return YES;
}

BOOL Dialog1WriteMessage (int fd, NSDictionary* message)
{
	NSError* error = nil;
	NSData* data = [NSPropertyListSerialization dataWithPropertyList:message format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
	if(!data || data.length > kDialog1MaxMessageBytes)
		return NO;

	uint32_t length = OSSwapHostToBigInt32((uint32_t)data.length);
	if(!WriteAll(fd, &length, sizeof(length)))
		return NO;
	return WriteAll(fd, data.bytes, data.length);
}

NSDictionary* Dialog1ReadMessage (int fd)
{
	uint32_t length = 0;
	if(!ReadAll(fd, &length, sizeof(length)))
		return nil;

	length = OSSwapBigToHostInt32(length);
	if(length == 0 || length > kDialog1MaxMessageBytes)
		return nil;

	NSMutableData* data = [NSMutableData dataWithLength:length];
	if(!data || !ReadAll(fd, data.mutableBytes, length))
		return nil;

	id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nullptr error:nullptr];
	return [plist isKindOfClass:NSDictionary.class] ? plist : nil;
}
