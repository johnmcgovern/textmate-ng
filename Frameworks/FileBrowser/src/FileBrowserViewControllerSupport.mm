#import "FileBrowserViewControllerSupport.h"
#import "FileItem.h"
#import <OakCommand/OakCommand.h>
#import <Preferences/Keys.h>
#import <bundles/bundles.h>
#import <command/parser.h>
#import <io/path.h>
#import <ns/ns.h>
#import <regexp/glob.h>
#import <settings/settings.h>
#import <text/ctype.h>

static bool is_binary (std::string const& path)
{
	if(path == NULL_STR)
		return false;

	settings_t const& settings = settings_for_path(path);
	if(settings.has(kSettingsBinaryKey))
		return path::glob_t(settings.get(kSettingsBinaryKey, "")).does_match(path);

	return false;
}

@implementation FileBrowserViewControllerSupport
+ (NSPredicate*)itemPredicateForDirectoryURL:(NSURL*)directoryURL
{
	NSPredicate* predicate = [NSPredicate predicateWithValue:YES];
	settings_t const settings = settings_for_path(NULL_STR, "", directoryURL.fileSystemRepresentation);
	bool excludeMissingFiles = [directoryURL.scheme isEqual:@"scm"] ? false : settings.get(kSettingsExcludeSCMDeletedKey, false);

	path::glob_list_t globs;
	globs.add_exclude_glob(settings.get(kSettingsExcludeDirectoriesInBrowserKey), path::kPathItemDirectory);
	globs.add_exclude_glob(settings.get(kSettingsExcludeDirectoriesKey),          path::kPathItemDirectory);
	globs.add_exclude_glob(settings.get(kSettingsExcludeFilesInBrowserKey),       path::kPathItemFile);
	globs.add_exclude_glob(settings.get(kSettingsExcludeFilesKey),                path::kPathItemFile);
	globs.add_exclude_glob(settings.get(kSettingsExcludeInBrowserKey),            path::kPathItemAny);
	globs.add_exclude_glob(settings.get(kSettingsExcludeKey),                     path::kPathItemAny);

	globs.add_include_glob(settings.get(kSettingsIncludeDirectoriesInBrowserKey), path::kPathItemDirectory);
	globs.add_include_glob(settings.get(kSettingsIncludeDirectoriesKey),          path::kPathItemDirectory);
	globs.add_include_glob(settings.get(kSettingsIncludeFilesInBrowserKey),       path::kPathItemFile);
	globs.add_include_glob(settings.get(kSettingsIncludeFilesKey),                path::kPathItemFile);
	globs.add_include_glob(settings.get(kSettingsIncludeInBrowserKey),            path::kPathItemAny);
	globs.add_include_glob(settings.get(kSettingsIncludeKey, "*"),                path::kPathItemAny);

	predicate = [NSPredicate predicateWithBlock:^BOOL(FileItem* item, NSDictionary* bindings){
		if(item.hidden && ![item.URL.lastPathComponent hasPrefix:@"."])
			return NO;

		if(excludeMissingFiles && item.isMissing)
			return NO;

		char const* path = item.URL.fileSystemRepresentation;
		size_t itemType  = item.isDirectory ? path::kPathItemDirectory : path::kPathItemFile;
		return item.hidden ? globs.include(path, itemType) : !globs.exclude(path, itemType);
	}];
	return predicate;
}

+ (BOOL)isBinaryURL:(NSURL*)url
{
	return is_binary(url.fileSystemRepresentation);
}

+ (NSArray<NSMenuItem*>*)actionMenuItemsWithAction:(SEL)action
{
	std::multimap<std::string, bundles::item_ptr, text::less_t> sorted;
	for(auto const& item : bundles::query(bundles::kFieldSemanticClass, "callback.file-browser.action-menu"))
		sorted.emplace(item->name(), item);

	NSMutableArray<NSMenuItem*>* res = [NSMutableArray array];
	for(auto pair : sorted)
	{
		NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:to_ns(pair.first) action:action keyEquivalent:@""];
		item.representedObject = to_ns(pair.second->uuid());
		[res addObject:item];
	}
	return res;
}

+ (void)executeBundleCommandWithUUIDString:(NSString*)uuidString firstResponder:(NSResponder*)firstResponder
{
	if(bundles::item_ptr item = bundles::lookup(to_s(uuidString)))
	{
		// TODO For commands that have ‘input = document’ we should provide the document
		OakCommand* command = [[OakCommand alloc] initWithBundleCommand:parse_command(item)];
		command.firstResponder = firstResponder;
		[command executeWithInput:nil variables:item->bundle_variables() outputHandler:nil];
	}
}

+ (NSString*)pathExtensionForNewFileInDirectoryURL:(NSURL*)directoryURL
{
	NSString* pathExtension;

	std::string fileType = settings_for_path(NULL_STR, "attr.untitled", directoryURL.fileSystemRepresentation).get(kSettingsFileTypeKey, "text.plain");
	for(auto item : bundles::query(bundles::kFieldGrammarScope, fileType))
	{
		if(NSString* ext = to_ns(item->value_for_field(bundles::kFieldGrammarExtension)))
			pathExtension = ext;
	}

	return pathExtension;
}
@end
