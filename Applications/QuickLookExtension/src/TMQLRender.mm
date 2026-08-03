#import "TMQLRender.h"
#import <OSAKit/OSAKit.h>
#import <buffer/buffer.h>
#import <bundles/bundles.h>
#import <file/bytes.h>
#import <file/type.h>
#import <file/reader.h>
#import <io/path.h>
#import <cf/cf.h>
#import <ns/ns.h>
#import <oak/misc.h>
#import <oak/log.h>
#import <plist/fs_cache.h>
#import <scope/scope.h>
#import <settings/settings.h>
#import <theme/theme.h>
#import <OakFoundation/NSString Additions.h>

static os_log_t const kLogQuickLook = os_log_create(OAK_LOG_SUBSYSTEM, "quicklook");

// The app's own preference domain, reached through the sandbox with a
// shared-preference temporary exception (see Entitlements.plist).
static NSString* const kTextMateDefaultsSuite = @"com.j23software.TextMate-NG";

// =================
// = Bootstrapping =
// =================

// The app bundle, found from this extension's own. NSBundle.mainBundle inside an
// app extension is the .appex — not the app — so the app is three levels up:
//
//     TextMate-NG.app/Contents/PlugIns/TextMateQL.appex
//
// This is also why bundles::locations() cannot be used as-is below: its last
// entry is oak::application_t::path("Contents/SharedSupport"), which resolves
// against the main bundle and would therefore point inside the .appex.
static NSBundle* app_bundle ()
{
	NSURL* url = NSBundle.mainBundle.bundleURL;
	for(size_t i = 0; i < 3; ++i)
		url = url.URLByDeletingLastPathComponent;
	return [NSBundle bundleWithURL:url];
}

static void initialize ()
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSBundle* appBundle = app_bundle();

		if(NSString* defaultSettings = [appBundle pathForResource:@"Default" ofType:@"tmProperties"])
			settings_t::set_default_settings_path(defaultSettings.fileSystemRepresentation);
		settings_t::set_global_settings_path(path::join(path::home(), "Library/Application Support/TextMate/Global.tmProperties"));

		// Spelled out rather than taken from bundles::locations() — see
		// app_bundle() above for why that default is wrong in an extension. The
		// home-relative entries are the ones that matter: installed bundles live
		// under "Managed", which is what the sandbox's home-relative exception
		// grants.
		std::vector<std::string> const locations = {
			path::join(path::home(), "Library/Application Support/TextMate"),
			path::join(path::home(), "Library/Application Support/TextMate/Pristine Copy"),
			path::join(path::home(), "Library/Application Support/TextMate/Managed"),
			path::join("/", "Library/Application Support/TextMate"),
			path::join("/", "Library/Application Support/TextMate/Pristine Copy"),
			to_s(appBundle.bundlePath) + "/Contents/SharedSupport",
		};
		bundles::set_locations(locations);

		std::vector<std::string> paths;
		for(auto const& location : locations)
			paths.push_back(path::join(location, "Bundles"));

		// The app's index cache, read-only. Nothing here writes it: if it is
		// missing or stale, create_bundle_index() parses the bundles directly —
		// slower, and still correct.
		plist::cache_t cache;
		cache.load_capnp(path::join(path::home(), "Library/Caches/com.j23software.TextMate-NG/BundlesIndex.binary"));

		auto index = create_bundle_index(paths, cache);
		bundles::set_index(index.first, index.second);

		os_log_debug(kLogQuickLook, "[TMQLRender initialize] %{public}zu location(s) indexed", locations.size());
	});
}

// =============
// = Rendering =
// =============

static std::string setup_buffer (NSURL* url, ng::buffer_t& buffer, size_t maxSize)
{
	std::string filePath = to_s(url.filePathURL.path);

	std::string fileContents = NULL_STR;
	if(path::extension(filePath) == ".scpt")
	{
		@autoreleasepool {
			NSDictionary* err = nil;
			if(OSAScript* script = [[OSAScript alloc] initWithContentsOfURL:url error:&err])
			{
				fileContents = [[script source] UTF8String] ?: NULL_STR;
				std::replace(fileContents.begin(), fileContents.end(), '\r', '\n');
			}
		}
	}

	if(fileContents == NULL_STR)
		fileContents = file::read_utf8(filePath, nullptr, maxSize);

	buffer.insert(0, fileContents);

	// Apply appropriate grammar
	std::string fileType = file::type(filePath, std::make_shared<io::bytes_t>(fileContents.data(), fileContents.size(), false));
	if(fileType != NULL_STR)
	{
		for(auto item : bundles::query(bundles::kFieldGrammarScope, fileType, scope::wildcard, bundles::kItemTypeGrammar))
		{
			buffer.set_grammar(item);
			break;
		}
	}

	return fileType;
}

static NSAttributedString* create_attributed_string (ng::buffer_t& buffer, std::string const& themeUUID, std::string const& fontName, size_t fontSize, theme_ptr* themeOut)
{
	if(themeUUID == NULL_STR || fontName == NULL_STR || fontSize == 0)
		return nil;

	bundles::item_ptr themeItem = bundles::lookup(themeUUID);
	if(!themeItem)
		return nil;

	theme_ptr theme = parse_theme(themeItem);
	if(!theme)
		return nil;

	theme = theme->copy_with_font_name_and_size(fontName, fontSize);
	if(themeOut)
		*themeOut = theme;

	// Perform syntax highlighting
	buffer.wait_for_repair();
	std::map<size_t, scope::scope_t> scopes = buffer.scopes(0, buffer.size());

	NSMutableAttributedString* output = (__bridge_transfer NSMutableAttributedString*)CFAttributedStringCreateMutable(kCFAllocatorDefault, buffer.size());
	size_t from = 0;
	for(auto pair = scopes.begin(); pair != scopes.end(); )
	{
		styles_t styles = theme->styles_for_scope(pair->second);

		size_t to = ++pair != scopes.end() ? pair->first : buffer.size();

		[output appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithCxxString:buffer.substr(from, to)] attributes:@{
			NSForegroundColorAttributeName:    [NSColor colorWithCGColor:styles.foreground()],
			NSBackgroundColorAttributeName:    [NSColor colorWithCGColor:styles.background()],
			NSFontAttributeName:               (__bridge NSFont*)styles.font(),
			NSUnderlineStyleAttributeName:     @(styles.underlined() ? NSUnderlineStyleSingle : NSUnderlineStyleNone),
			NSStrikethroughStyleAttributeName: @(styles.strikethrough() ? NSUnderlineStyleSingle : NSUnderlineStyleNone),
		}]];

		from = to;
	}

	return output;
}

// The theme the app would use right now. Its light/dark defaults are *registered*
// in AppController, and a registration domain is private to the process that
// registers it — another process reading the same domain sees nothing there. So
// the two fallbacks are spelled out again here; without them a machine whose
// owner never picked a theme would preview with no highlighting at all.
static std::string current_theme_uuid ()
{
	NSUserDefaults* userDefaults = [[NSUserDefaults alloc] initWithSuiteName:kTextMateDefaultsSuite];

	NSString* appearance = [userDefaults stringForKey:@"themeAppearance"];
	BOOL darkMode = [appearance isEqualToString:@"dark"];
	if(!darkMode && ![appearance isEqualToString:@"light"]) // If it is not ‘light’ then assume ‘auto’
		darkMode = [[NSAppearance.currentAppearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]] isEqualToString:NSAppearanceNameDarkAqua];

	NSString* themeUUID = [userDefaults stringForKey:darkMode ? @"darkModeThemeUUID" : @"universalThemeUUID"];
	return themeUUID ? to_s(themeUUID) : (darkMode ? kTwilightThemeUUID : kMacClassicThemeUUID);
}

NSAttributedString* TMQLCreateAttributedString (NSURL* url, size_t maxSize, NSColor** backgroundOut)
{
	initialize();

	ng::buffer_t buffer;
	std::string const fileType = setup_buffer(url, buffer, maxSize);
	if(fileType == NULL_STR)
	{
		os_log_debug(kLogQuickLook, "[TMQLCreateAttributedString] No file type for %{public}@", url.path);
		return nil;
	}

	settings_t const settings = settings_for_path(to_s(url.filePathURL.path), fileType);
	theme_ptr theme;
	NSFont* font = [NSFont userFixedPitchFontOfSize:0];
	NSAttributedString* res = create_attributed_string(buffer, current_theme_uuid(), settings.get(kSettingsFontNameKey, to_s([font fontName])), settings.get(kSettingsFontSizeKey, [font pointSize]), &theme);

	if(res && backgroundOut)
		*backgroundOut = theme ? [NSColor colorWithCGColor:theme->background(fileType)] : NSColor.textBackgroundColor;

	return res;
}
