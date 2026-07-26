#import "HOFileHandleScheme.h"
#import <OakSystem/process.h>
#import <oak/debug.h>

NSString* const kHOFileHandleURLScheme = @"x-txmt-filehandle";
NSString* const kHOLocalFilePathPrefix = @"/__tm_local__";

// Same scheme *and* same host as the job URL (x-txmt-filehandle://job/…), so the
// rewritten sub-resources are same-origin with the page rather than merely
// same-scheme.
static char const* const kFileURLPrefix  = "file://";
static char const* const kLocalURLPrefix = "x-txmt-filehandle://job/__tm_local__";

static NSString* MimeTypeForPath (NSString* path)
{
	static NSDictionary* const types = @{
		@"css": @"text/css",         @"js":   @"text/javascript", @"json": @"application/json",
		@"png": @"image/png",        @"jpg":  @"image/jpeg",      @"jpeg": @"image/jpeg",
		@"gif": @"image/gif",        @"svg":  @"image/svg+xml",   @"webp": @"image/webp",
		@"html": @"text/html",       @"htm":  @"text/html",       @"txt":  @"text/plain",
		@"woff": @"font/woff",       @"woff2": @"font/woff2",     @"ttf":  @"font/ttf",
	};
	return types[path.pathExtension.lowercaseString] ?: @"application/octet-stream";
}

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
		std::string carry;
		__block BOOL keepRunning = YES;

		while(keepRunning && (len = read(fd, buf, sizeof(buf))) > 0)
		{
			std::string rewritten = RewriteLocalURLs(std::string(buf, len), carry);
			if(rewritten.empty()) // whole chunk held back as a partial match
				continue;

			NSData* data = [NSData dataWithBytes:rewritten.data() length:rewritten.size()];
			dispatch_sync(dispatch_get_main_queue(), ^{
				if(keepRunning = !self->_stopped)
					[self->_task didReceiveData:data];
			});
		}

		if(len == -1)
			perror("HTMLOutput: read");

		// A partial `file://` at EOF was never a real one — emit it verbatim.
		if(keepRunning && !carry.empty())
		{
			NSData* tail = [NSData dataWithBytes:carry.data() length:carry.size()];
			dispatch_sync(dispatch_get_main_queue(), ^{
				if(!self->_stopped)
					[self->_task didReceiveData:tail];
			});
		}

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

	if([url.path hasPrefix:kHOLocalFilePathPrefix])
		return [self serveLocalFileForTask:urlSchemeTask];

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

/*
	Serves a stylesheet/script/image that the page referenced as file:// before the
	stream rewrite. Read synchronously: these are small local assets, and the whole
	point is to answer before the page finishes parsing.

	This does let command output read any file the user can read — which is exactly
	the privilege +[WebView registerURLSchemeAsLocal:] granted the job scheme
	before, so it is not a widening. The content is the user’s own bundle output.
*/
- (void)serveLocalFileForTask:(id <WKURLSchemeTask>)urlSchemeTask
{
	NSURL* url = urlSchemeTask.request.URL;
	NSString* path = [url.path substringFromIndex:kHOLocalFilePathPrefix.length]; // -path is already percent-decoded

	NSError* error;
	NSData* data = path.length ? [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&error] : nil;
	if(!data)
	{
		os_log_error(OS_LOG_DEFAULT, "HTMLOutput: no local resource at ‘%{public}@’", path);
		[urlSchemeTask didReceiveResponse:[[NSHTTPURLResponse alloc] initWithURL:url statusCode:404 HTTPVersion:@"HTTP/1.1" headerFields:nil]];
		[urlSchemeTask didFinish];
		return;
	}

	[urlSchemeTask didReceiveResponse:[[NSURLResponse alloc] initWithURL:url MIMEType:MimeTypeForPath(path) expectedContentLength:data.length textEncodingName:nil]];
	[urlSchemeTask didReceiveData:data];
	[urlSchemeTask didFinish];
}
@end
