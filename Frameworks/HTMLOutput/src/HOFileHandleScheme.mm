#import "HOFileHandleScheme.h"
#import <OakSystem/process.h>
#import <oak/debug.h>

NSString* const kHOFileHandleURLScheme = @"x-txmt-filehandle";

// ==================
// = The job record =
// ==================

@interface HOFileHandleJob ()
@property (nonatomic, readwrite) NSFileHandle* fileHandle;
@property (nonatomic, readwrite) pid_t processIdentifier;
@end

@implementation HOFileHandleJob
@end

@implementation HOFileHandleRegistry
{
	NSMutableDictionary<NSURL*, HOFileHandleJob*>* _jobs;
}

+ (instancetype)sharedInstance
{
	static HOFileHandleRegistry* instance = [self new];
	return instance;
}

- (instancetype)init
{
	if(self = [super init])
		_jobs = [NSMutableDictionary dictionary];
	return self;
}

- (void)registerJobForURL:(NSURL*)aURL fileHandle:(NSFileHandle*)aFileHandle processIdentifier:(pid_t)aProcessIdentifier
{
	if(!aURL || !aFileHandle)
		return;

	HOFileHandleJob* job  = [HOFileHandleJob new];
	job.fileHandle        = aFileHandle;
	job.processIdentifier = aProcessIdentifier;
	_jobs[aURL]           = job;
}

- (HOFileHandleJob*)claimJobForURL:(NSURL*)aURL
{
	HOFileHandleJob* job = aURL ? _jobs[aURL] : nil;
	if(job)
		[_jobs removeObjectForKey:aURL];
	return job;
}

- (void)discardJobForURL:(NSURL*)aURL
{
	if(aURL)
		[_jobs removeObjectForKey:aURL];
}
@end

// ==========================
// = One in-flight URL task =
// ==========================

/*
	WKURLSchemeTask raises an Objective-C exception — not an error return — if any
	of its callbacks run after -stopURLSchemeTask:. Every delivery therefore hops
	to the main queue and re-checks `_stopped` there, which is also the only queue
	that ever writes it. Same guard the NSURLProtocol version used, but per task
	instead of per protocol instance, because one scheme handler serves them all.
*/
@interface HOFileHandleTask : NSObject
- (instancetype)initWithTask:(id <WKURLSchemeTask>)aTask job:(HOFileHandleJob*)aJob completionHandler:(void(^)(void))aCompletionHandler;
- (void)start;
- (void)stop;
@end

@implementation HOFileHandleTask
{
	id <WKURLSchemeTask> _task;
	HOFileHandleJob* _job;
	void(^_completionHandler)(void);
	BOOL _stopped;
}

- (instancetype)initWithTask:(id <WKURLSchemeTask>)aTask job:(HOFileHandleJob*)aJob completionHandler:(void(^)(void))aCompletionHandler
{
	if(self = [super init])
	{
		_task              = aTask;
		_job               = aJob;
		_completionHandler = aCompletionHandler;
	}
	return self;
}

- (void)start
{
	NSURLResponse* response = [[NSURLResponse alloc] initWithURL:_task.request.URL MIMEType:@"text/html" expectedContentLength:-1 textEncodingName:@"utf-8"];
	[_task didReceiveResponse:response];

	int const fd = _job.fileHandle.fileDescriptor;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		ssize_t len = 0;
		char buf[8192];
		__block BOOL keepRunning = YES;

		while(keepRunning && (len = read(fd, buf, sizeof(buf))) > 0)
		{
			NSData* data = [NSData dataWithBytes:buf length:len];
			dispatch_sync(dispatch_get_main_queue(), ^{
				if(keepRunning = !self->_stopped)
					[self->_task didReceiveData:data];
			});
		}

		if(len == -1)
			perror("HTMLOutput: read");

		[self->_job.fileHandle closeFile];

		dispatch_sync(dispatch_get_main_queue(), ^{
			[self finish];
		});
	});
}

- (void)finish
{
	if(!_stopped)
	{
		_stopped = YES; // no further callbacks are legal after didFinish either
		[_task didFinish];
	}

	void(^completionHandler)(void) = _completionHandler;
	_completionHandler = nil;
	if(completionHandler)
		completionHandler();
}

- (void)stop
{
	_stopped           = YES;
	_completionHandler = nil;

	if(pid_t pid = _job.processIdentifier)
		oak::kill_process_group_in_background(pid);
}
@end

// ==================
// = Scheme handler =
// ==================

@implementation HOFileHandleSchemeHandler
{
	NSMapTable<id <WKURLSchemeTask>, HOFileHandleTask*>* _tasks;
}

- (instancetype)init
{
	if(self = [super init])
		_tasks = [NSMapTable strongToStrongObjectsMapTable];
	return self;
}

- (void)webView:(WKWebView*)webView startURLSchemeTask:(id <WKURLSchemeTask>)urlSchemeTask
{
	NSURL* url = urlSchemeTask.request.URL;
	HOFileHandleJob* job = [HOFileHandleRegistry.sharedInstance claimJobForURL:url];
	if(!job)
	{
		// The job URL is unique per run and claimed once, so this is a reload of a
		// command whose output stream is already gone. The NSURLProtocol version
		// answered the same way.
		os_log_error(OS_LOG_DEFAULT, "No command output for ‘%{public}@’", url);
		[urlSchemeTask didReceiveResponse:[[NSHTTPURLResponse alloc] initWithURL:url statusCode:404 HTTPVersion:@"HTTP/1.1" headerFields:nil]];
		[urlSchemeTask didFinish];
		return;
	}

	__weak HOFileHandleSchemeHandler* weakSelf = self;
	HOFileHandleTask* task = [[HOFileHandleTask alloc] initWithTask:urlSchemeTask job:job completionHandler:^{
		[weakSelf forgetTask:urlSchemeTask];
	}];

	[_tasks setObject:task forKey:urlSchemeTask];
	[task start];
}

- (void)webView:(WKWebView*)webView stopURLSchemeTask:(id <WKURLSchemeTask>)urlSchemeTask
{
	HOFileHandleTask* task = [_tasks objectForKey:urlSchemeTask];
	[_tasks removeObjectForKey:urlSchemeTask];
	[task stop];
}

- (void)forgetTask:(id <WKURLSchemeTask>)urlSchemeTask
{
	[_tasks removeObjectForKey:urlSchemeTask];
}
@end
