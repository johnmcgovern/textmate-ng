#import "DocumentWindowSupport.h"
#import "DWScopeContextCxx.h"
#import <OakTextView/OakTextView.h>
#import <OakAppKit/OakSavePanel.h>
#import <BundleEditor/BundleEditor.h>
#import <OakSystem/application.h>
#import <document/OakDocumentController.h>
#import <bundles/bundles.h>
#import <command/parser.h>
#import <crash/info.h>
#import <file/encoding.h>
#import <io/entries.h>
#import <io/path.h>
#import <regexp/glob.h>
#import <regexp/regexp.h>
#import <settings/settings.h>
#import <text/format.h>
#import <text/utf8.h>
#import <ns/ns.h>
#import <OakFoundation/NSString Additions.h>
#import <SystemConfiguration/SystemConfiguration.h>

// The static half of the guard DWOutputType.h describes. A divergence here is a
// compile error rather than a Filter Through Command that quietly does the wrong
// thing to your document; t_output_type.mm checks the same pairs at runtime,
// because this file only exists as long as the C++ does.
static_assert((NSInteger)output::replace_input     == DWOutputTypeReplaceInput,     "DWOutputType diverged from output::type: replace_input");
static_assert((NSInteger)output::replace_document  == DWOutputTypeReplaceDocument,  "DWOutputType diverged from output::type: replace_document");
static_assert((NSInteger)output::at_caret          == DWOutputTypeAtCaret,          "DWOutputType diverged from output::type: at_caret");
static_assert((NSInteger)output::after_input       == DWOutputTypeAfterInput,       "DWOutputType diverged from output::type: after_input");
static_assert((NSInteger)output::new_window        == DWOutputTypeNewWindow,        "DWOutputType diverged from output::type: new_window");
static_assert((NSInteger)output::tool_tip          == DWOutputTypeToolTip,          "DWOutputType diverged from output::type: tool_tip");
static_assert((NSInteger)output::discard           == DWOutputTypeDiscard,          "DWOutputType diverged from output::type: discard");
static_assert((NSInteger)output::replace_selection == DWOutputTypeReplaceSelection, "DWOutputType diverged from output::type: replace_selection");

BOOL DWFilterDocumentThroughCommand (NSString* command, DWOutputType outputType)
{
	// -targetForAction: walks the responder chain for something that implements
	// the selector, exactly as the ObjC++ did; nothing accepting it is a no-op
	// rather than an error, which is what "no document is frontmost" looks like.
	if(id textView = [NSApp targetForAction:@selector(filterDocumentThroughCommand:input:output:)])
		return [textView filterDocumentThroughCommand:command input:input::selection output:(output::type)outputType];
	return NO;
}

// ============================================================
// = The three APIs whose blocks carry C++                    =
// ============================================================

// oak::uuid_t is falsy when null and its operator NSString* does not exist, so
// this is the one conversion both document shims need. Kept in one place because
// getting it backwards would turn "the command that failed" into "some command
// failed", silently.
static NSString* to_ns_uuid (oak::uuid_t const& uuid)
{
	return uuid ? [NSString stringWithCxxString:uuid] : nil;
}

void DWLoadDocumentModalForWindow (OakDocument* document, NSWindow* window, void(^handler)(OakDocumentIOResult result, NSString* errorMessage, NSString* filterUUID))
{
	[document loadModalForWindow:window completionHandler:^(OakDocumentIOResult result, NSString* errorMessage, oak::uuid_t const& filterUUID){
		handler(result, errorMessage, to_ns_uuid(filterUUID));
	}];
}

void DWSaveDocumentModalForWindow (OakDocument* document, NSWindow* window, void(^handler)(OakDocumentIOResult result, NSString* errorMessage, NSString* filterUUID))
{
	[document saveModalForWindow:window completionHandler:^(OakDocumentIOResult result, NSString* errorMessage, oak::uuid_t const& filterUUID){
		handler(result, errorMessage, to_ns_uuid(filterUUID));
	}];
}

void DWShowSavePanelForDocument (OakDocument* document, NSString* pathSuggestion, NSString* directorySuggestion, NSWindow* window, void(^handler)(NSString* path, NSString* newlines, NSString* charset))
{
	encoding::type const encoding(to_s(document.diskNewlines), to_s(document.diskEncoding));
	[OakSavePanel showWithPath:pathSuggestion directory:directorySuggestion fowWindow:window encoding:encoding fileType:document.fileType completionHandler:^(NSString* path, encoding::type const& chosen){
		// `path` nil is the cancel case and the caller returns on it, but the
		// encoding strings are handed over regardless rather than being left
		// undefined — to_ns of a NULL_STR string is nil, which is what a caller
		// assigning them straight onto a document wants anyway.
		handler(path, to_ns(chosen.newlines()), to_ns(chosen.charset()));
	}];
}

void DWShowCommandError (NSString* message, NSString* filterUUID, NSWindow* window)
{
	bundles::item_ptr bundleItem = bundles::lookup(to_s(filterUUID));
	std::string commandName = bundleItem ? bundleItem->name() : "(unknown)";

	NSAlert* alert = [[NSAlert alloc] init];
	[alert setAlertStyle:NSAlertStyleCritical];
	[alert setMessageText:[NSString stringWithCxxString:text::format("Failure running “%.*s”.", (int)commandName.size(), commandName.data())]];
	[alert setInformativeText:message ?: @"No output"];
	[alert addButtonWithTitle:@"OK"];
	if(bundleItem)
		[alert addButtonWithTitle:@"Edit Command"];

	[alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse button){
		if(button == NSAlertSecondButtonReturn)
			[BundleEditor.sharedInstance revealBundleItem:bundleItem];
	}];
}

void DWWithCrashReporterInfo (NSString* info, void(^block)(void))
{
	crash_reporter_info_t const crashInfo(to_s(info));
	block();
}

// ============================================================
// = settings_for_path                                        =
// ============================================================

NSString* DWDefaultFileTypeForDocument (OakDocument* document, NSString* projectPath)
{
	std::string const docAttributes = document.path ? "attr.file.unknown-type" : "attr.untitled";
	return to_ns(settings_for_path(to_s(document.virtualPath ?: document.path), docAttributes, to_s(projectPath)).get(kSettingsFileTypeKey, "text.plain"));
}

NSString* DWUserProjectDirectoryForPath (NSString* projectPath)
{
	std::map<std::string, std::string> const map = { { "projectDirectory", to_s(projectPath) } };
	settings_t const settings = settings_for_path(NULL_STR, scope::scope_t(), to_s(projectPath), map);
	std::string const userProjectDirectory = settings.get(kSettingsProjectDirectoryKey, NULL_STR);
	return path::is_absolute(userProjectDirectory) ? [NSString stringWithCxxString:path::normalize(userProjectDirectory)] : nil;
}

BOOL DWShouldSaveOnBlur (OakDocument* document)
{
	settings_t const settings = settings_for_path(to_s(document.virtualPath ?: document.path), to_s(document.fileType), path::parent(to_s(document.path)));
	return settings.get(kSettingsSaveOnBlurKey, false);
}

// ============================================================
// = Paths and strings                                        =
// ============================================================

NSArray<NSString*>* DWExpandBraces (NSString* path)
{
	NSMutableArray<NSString*>* res = [NSMutableArray array];
	for(auto const& expanded : path::expand_braces(to_s(path)))
		[res addObject:to_ns(expanded)];
	return res;
}

BOOL DWIsChildPath (NSString* path, NSString* parent)
{
	return path::is_child(to_s(path), to_s(parent));
}

BOOL DWPathExists (NSString* path)
{
	return path::exists(to_s(path));
}

NSString* DWSessionPath (void)
{
	static NSString* const res = [NSString stringWithCxxString:path::join(oak::application_t::support("Session"), "Info.plist")];
	return res;
}

NSString* DWFindClipboardFilterString (NSString* string, NSString* basePath)
{
	std::string const str = to_s(string);
	if(!regexp::search("\\A.*?(\\.|/).*?:\\d+\\z", str))
		return nil;
	return [string hasPrefix:basePath] ? [NSString stringWithCxxString:path::relative_to(str, to_s(basePath))] : string;
}

// ============================================================
// = Bundles                                                  =
// ============================================================

void DWPerformDidOpenCallbacks (OakTextView* textView)
{
	for(auto const& item : bundles::query(bundles::kFieldSemanticClass, "callback.document.did-open", [textView scopeContext], bundles::kItemTypeMost, oak::uuid_t(), false))
		[textView performBundleItem:item];
}

BOOL DWCanReachBundleServer (void)
{
	char const* host = [[[NSURL URLWithString:@(REST_API)] host] UTF8String];
	if(!host)
		return NO;

	BOOL res = NO;
	if(SCNetworkReachabilityRef ref = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, host))
	{
		SCNetworkReachabilityFlags flags;
		if(SCNetworkReachabilityGetFlags(ref, &flags))
		{
			if(flags & kSCNetworkReachabilityFlagsReachable)
				res = YES;
		}
		CFRelease(ref);
	}
	return res;
}

// ============================================================
// = Go to Related File                                       =
// ============================================================

NSString* DWRelatedFilePath (OakDocument* document, NSArray<OakDocument*>* documents, NSString* projectPath, NSString* scopeAttributes, DWScopeContext* scopeContext)
{
	std::string const documentPath = to_s(document.path);
	std::string const documentDir  = path::parent(documentPath);
	std::string const documentName = path::name(documentPath);
	std::string const documentBase = path::strip_extensions(documentName);

	std::set<std::string> candidates = { documentName };
	for(OakDocument* doc in documents)
	{
		if(documentDir == path::parent(to_s(doc.path)) && documentBase == path::strip_extensions(path::name(to_s(doc.path))))
			candidates.insert(path::name(to_s(doc.path)));
	}

	auto map = document.variables;
	auto const& scm = scopeContext.effectiveSCMVariablesMap;
	map.insert(scm.begin(), scm.end());
	if(projectPath)
		map["projectDirectory"] = to_s(projectPath);

	settings_t const settings = settings_for_path(to_s(document.virtualPath ?: document.path), to_s(document.fileType) + " " + to_s(scopeAttributes), path::parent(documentPath), map);
	std::string const customCandidate = settings.get(kSettingsRelatedFilePathKey, NULL_STR);

	if(customCandidate != NULL_STR && customCandidate != documentPath && ([documents indexOfObjectPassingTest:^BOOL(OakDocument* doc, NSUInteger, BOOL*){ return customCandidate == to_s(doc.path); }] != NSNotFound || path::exists(customCandidate)))
		return [NSString stringWithCxxString:customCandidate];

	for(auto const& entry : path::entries(documentDir))
	{
		std::string const name = entry->d_name;
		if(entry->d_type == DT_REG && documentBase == path::strip_extensions(name) && path::extensions(name) != "")
		{
			std::string const content = path::content(path::join(documentDir, name));
			if(utf8::is_valid(content.data(), content.data() + content.size()))
				candidates.insert(name);
		}
	}

	path::glob_t const excludeGlob(settings.get(kSettingsExcludeKey, ""));
	path::glob_t const binaryGlob(settings.get(kSettingsBinaryKey, ""));

	std::vector<std::string> v;
	for(auto const& name : candidates)
	{
		if(name == documentName || !binaryGlob.does_match(name) && !excludeGlob.does_match(name))
			v.push_back(name);
	}

	if(v.size() == 1)
	{
		if(customCandidate == NULL_STR || customCandidate == documentPath)
			return nil;
		v.push_back(customCandidate);
	}

	std::vector<std::string>::const_iterator it = std::find(v.begin(), v.end(), documentName);
	ASSERT(it != v.end());

	return [NSString stringWithCxxString:path::join(documentDir, v[((it - v.begin()) + 1) % v.size()])];
}
