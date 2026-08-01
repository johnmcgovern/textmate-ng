#import "FileItemImage.h"
#import "TMFileReference.h"

NSImage* CreateIconImageForURL (NSURL* url, BOOL isModified, BOOL isMissing, BOOL isDirectory, BOOL isSymbolicLink, TMSCMStatus scmStatus)
{
	NSImage* res;

	if(isMissing && (scmStatus == TMSCMStatusNone || scmStatus == TMSCMStatusUnknown))
	{
		res = [NSWorkspace.sharedWorkspace iconForFileType:NSFileTypeForHFSTypeCode(kUnknownFSObjectIcon)];
	}
	else
	{
		TMFileReference* fileReference = [TMFileReference fileReferenceWithURL:url];
		if(scmStatus != TMSCMStatusUnknown)
			fileReference.SCMStatus = scmStatus;
		res = fileReference.image;
	}

	res = [res copy];
	res.size = NSMakeSize(16, 16);

	return isModified ? [NSImage imageWithSize:res.size flipped:NO drawingHandler:^BOOL(NSRect dstRect){
		[res drawInRect:dstRect fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:0.4];
		return YES;
	}] : res;
}
