#import "FileItem.h"
#import <OakAppKit/OakFinderTag.h>
#import <OakFoundation/OakFoundation.h>
#import <Preferences/Keys.h>
#import <ns/ns.h>

NSURL* const kURLLocationComputer  = [[NSURL alloc] initWithString:@"computer:///"];
NSURL* const kURLLocationFavorites = [[NSURL alloc] initFileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TextMate/Favorites"] isDirectory:YES];

@interface FileItem ()
@property (nonatomic, readonly) BOOL alwaysShowFileExtension;
@end

static NSMutableDictionary* SchemeToClass;

@implementation FileItem
// Was three separate +load methods (here, FileItemSCMStatus, FileItemMountedVolumes)
// that each self-registered a URL scheme. Swift never runs +load, so to let this
// class family become Swift the registration is explicit and lazy instead. The
// subclasses live in other files with no shared header; NSClassFromString reaches
// them without one, and -ObjC (load-bearing in this project) keeps them linked
// even though nothing references their symbols. Runs once, before the first
// lookup, which is the only reader — so there is no load-order dependency.
+ (void)registerBuiltinClasses
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		[self registerClass:[FileItem class] forURLScheme:@"file"];
		if(Class klass = NSClassFromString(@"SCMStatusFileItem"))
			[self registerClass:klass forURLScheme:@"scm"];
		if(Class klass = NSClassFromString(@"MountedVolumesFileItem"))
			[self registerClass:klass forURLScheme:@"computer"];
	});
}

+ (void)registerClass:(Class)klass forURLScheme:(NSString*)urlScheme
{
	if(!SchemeToClass)
		SchemeToClass = [NSMutableDictionary dictionary];
	SchemeToClass[urlScheme] = klass;
}

+ (Class)classForURL:(NSURL*)url
{
	[self registerBuiltinClasses];
	return SchemeToClass[url.scheme];
}

+ (instancetype)fileItemWithURL:(NSURL*)url
{
	return [[[self classForURL:url] alloc] initWithURL:url];
}

- (instancetype)initWithURL:(NSURL*)url
{
	if(self = [super init])
	{
		self.URL = url;

		[self updateFileProperties];
	}
	return self;
}

- (BOOL)canRename
{
	NSNumber* flag;
	return _URL.isFileURL && !self.isMissing && (![_URL getResourceValue:&flag forKey:NSURLIsVolumeKey error:nil] || !flag.boolValue);
}

- (void)updateFileProperties
{
	if(!_URL.isFileURL)
		return;

	NSNumber* flag;

	self.hidden          = [_URL getResourceValue:&flag forKey:NSURLIsHiddenKey error:nil] && flag.boolValue;
	self.hiddenExtension = [_URL getResourceValue:&flag forKey:NSURLHasHiddenExtensionKey error:nil] && flag.boolValue;
	self.symbolicLink    = [_URL getResourceValue:&flag forKey:NSURLIsSymbolicLinkKey error:nil] && flag.boolValue;
	self.package         = !_symbolicLink && [_URL getResourceValue:&flag forKey:NSURLIsPackageKey error:nil] && flag.boolValue;
	self.linkToDirectory = _symbolicLink && [self.resolvedURL getResourceValue:&flag forKey:NSURLIsDirectoryKey error:nil] && flag.boolValue;
	self.linkToPackage   = _symbolicLink && [self.resolvedURL getResourceValue:&flag forKey:NSURLIsPackageKey error:nil] && flag.boolValue;
	self.finderTags      = [OakFinderTagManager finderTagsForURL:self.URL];
	self.missing         = _missing && ![NSFileManager.defaultManager fileExistsAtPath:_URL.path];
}

- (NSString*)description
{
	return [NSString stringWithFormat:@"<%@: %@>", self.class, _URL];
}

- (NSURL*)previewItemURL
{
	return self.isMissing ? nil : self.resolvedURL.filePathURL;
}

- (NSString*)previewItemTitle
{
	return self.localizedName;
}

// =======================
// = Computed Properties =
// =======================

- (BOOL)alwaysShowFileExtension
{
	return [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsShowFileExtensionsKey];
}

- (BOOL)isDirectory
{
	return _URL.hasDirectoryPath;
}

- (NSString*)displayName
{
	return [self.localizedName stringByAppendingString:_disambiguationSuffix ?: @""];
}

- (NSString*)localizedName
{
	if(!_localizedName)
	{
		NSString* name;
		if(_URL.isFileURL)
		{
			NSError* error;
			if([_URL getResourceValue:&name forKey:NSURLLocalizedNameKey error:&error])
			{
				if(_hiddenExtension && self.alwaysShowFileExtension && OakNotEmptyString(_URL.pathExtension))
					name = [name stringByAppendingPathExtension:_URL.pathExtension];
			}
			else
			{
				os_log_error(OS_LOG_DEFAULT, "No NSURLLocalizedNameKey for %{public}@: %{public}@", _URL, error);
			}
		}
		_localizedName = name ?: _URL.lastPathComponent;
	}
	return _localizedName ?: _URL.lastPathComponent;
}

- (NSURL*)resolvedURL
{
	NSURL* url = _URL;
	if(_symbolicLink)
	{
		// For /{etc,tmp,var} we get /{etc,tmp,var}/ insteawd of /private/{etc,tmp,var}/
		url = [url URLByResolvingSymlinksInPath];

		NSNumber* flag;
		if([url getResourceValue:&flag forKey:NSURLIsSymbolicLinkKey error:nil] && flag.boolValue)
		{
			NSError* error;
			if(NSString* path = [NSFileManager.defaultManager destinationOfSymbolicLinkAtPath:_URL.path error:&error])
				url = [[_URL URLByDeletingLastPathComponent] URLByAppendingPathComponent:path];
		}
	}
	return url;
}

- (NSURL*)parentURL
{
	if(_URL.isFileURL)
	{
		NSNumber* flag;
		NSURL* parentURL;

		if([_URL getResourceValue:&flag forKey:NSURLIsVolumeKey error:nil] && flag.boolValue)
			return kURLLocationComputer;
		else if([_URL getResourceValue:&parentURL forKey:NSURLParentDirectoryURLKey error:nil] && parentURL)
			return parentURL;
	}
	return nil;
}

- (BOOL)isApplication
{
	NSNumber* flag;
	return _URL.isFileURL && [_URL getResourceValue:&flag forKey:NSURLIsApplicationKey error:nil] && flag.boolValue;
}

// ===========================================
// = Setters that invalidate other propertes =
// ===========================================

+ (NSSet*)keyPathsForValuesAffectingDisplayName
{
	return [NSSet setWithObjects:@"localizedName", @"disambiguationSuffix", nil];
}

+ (NSSet*)keyPathsForValuesAffectingLocalizedName
{
	return [NSSet setWithObjects:@"URL", @"hiddenExtension", nil];
}

- (void)setURL:(NSURL*)newURL
{
	if(_URL != newURL && ![_URL isEqual:newURL])
	{
		_URL           = newURL;
		_localizedName = nil;

		for(FileItem* child in _children)
		{
			if(child.URL.isFileURL && _URL.isFileURL)
				child.URL = [_URL URLByAppendingPathComponent:child.URL.lastPathComponent isDirectory:child.URL.hasDirectoryPath];
		}
	}

	_fileReferenceURL = _URL.fileReferenceURL;
}

- (void)setHiddenExtension:(BOOL)flag
{
	if(_hiddenExtension != flag)
	{
		_hiddenExtension = flag;
		_localizedName   = nil;
	}
}
@end
