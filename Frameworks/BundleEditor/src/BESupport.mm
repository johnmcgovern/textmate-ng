#import "BESupport.h"
#import <TMBundleModel/TMBundleModelCxx.h>
#import <OakFoundation/NSString Additions.h>
#import <command/parser.h>
#import <command/runner.h>       // command::fix_shebang
#import <plist/ascii.h>
#import <regexp/format_string.h>
#import <text/decode.h>
#import <io/environment.h>
#import <settings/settings.h>       // variables_for_path
#import <ns/ns.h>
#import <AddressBook/AddressBook.h>

// The key order a re-serialized item is written in. Alphabetical would reorder
// every key of every item the first time it is saved through the editor, so this
// mirrors how bundle authors actually write them.
static std::vector<std::string> const& PlistKeySortOrder ()
{
	static auto const res = new std::vector<std::string>{ "shellVariables", "disabled", "name", "value", "comment", "match", "begin", "while", "end", "applyEndPatternLast", "captures", "beginCaptures", "whileCaptures", "endCaptures", "contentName", "injections", "patterns", "repository", "include", "increaseIndentPattern", "decreaseIndentPattern", "indentNextLinePattern", "unIndentedLinePattern", "disableIndentCorrections", "indentOnPaste", "indentedSoftWrap", "format", "foldingStartMarker", "foldingStopMarker", "foldingIndentedBlockStart", "foldingIndentedBlockIgnore", "characterClass", "smartTypingPairs", "highlightPairs", "showInSymbolList", "symbolTransformation", "disableDefaultCompletion", "completions", "completionCommand", "spellChecking", "softWrap", "fontName", "fontStyle", "fontSize", "foreground", "background", "bold", "caret", "invisibles", "italic", "misspelled", "selection", "underline" };
	return *res;
}

// plist::convert only produces a dictionary_t, but the values serialized here
// are whole plist values — a macro's `commands` is an array, a theme's
// `settings` a dictionary. Round-tripping through a one-key wrapper reaches the
// generic any_t conversion without duplicating the visitor.
static plist::any_t AnyFromObject (id object)
{
	plist::dictionary_t wrapper = plist::convert((__bridge CFPropertyListRef)@{ @"v": object ?: @"" });
	return wrapper["v"];
}

static id ObjectFromAny (plist::any_t const& any)
{
	return (__bridge_transfer id)plist::create_cf_property_list(any);
}

NSString* BEPlistString (id object)
{
	return [NSString stringWithCxxString:to_s(AnyFromObject(object), plist::kPreferSingleQuotedStrings, PlistKeySortOrder())] ?: @"";
}

id BEObjectFromPlistString (NSString* string)
{
	bool success = false;
	plist::any_t const parsed = plist::parse_ascii(to_s(string), &success);
	return success ? ObjectFromAny(parsed) : nil;
}

// ===================
// = Command popups  =
// ===================

// Deliberately a bounds-checked lookup and not `array[index]`. The enums here
// come from parsing a user-authored plist, and output_format in particular has
// five values while the Bundle Editor's popup offers four — the fifth is only
// ever set at runtime, so this cannot fire today, but "cannot fire today" is
// exactly the shape of the three conversion crashes this project has already
// paid for. index_of falls back to 0 for an unrecognised string; so does this.
static NSString* ValueAt (NSArray<NSString*>* values, size_t index)
{
	return index < values.count ? values[index] : values.firstObject;
}

NSDictionary<NSString*, id>* BECommandPopupValues (TMBundleItem* item)
{
	bundle_command_t const cmd = parse_command(item.cxxItem);

	return @{
		@"beforeRunningCommand": ValueAt(@[ @"nop", @"saveActiveFile", @"saveModifiedFiles" ], cmd.pre_exec),
		@"input":                ValueAt(@[ @"selection", @"document", @"scope", @"line", @"word", @"character", @"none" ], cmd.input),
		@"inputFormat":          ValueAt(@[ @"text", @"xml" ], cmd.input_format),
		@"outputLocation":       ValueAt(@[ @"replaceInput", @"replaceDocument", @"atCaret", @"afterInput", @"newWindow", @"toolTip", @"discard", @"replaceSelection" ], cmd.output),
		@"outputFormat":         ValueAt(@[ @"text", @"snippet", @"html", @"completionList" ], cmd.output_format),
		@"outputCaret":          ValueAt(@[ @"afterOutput", @"selectOutput", @"interpolateByChar", @"interpolateByLine", @"heuristic" ], cmd.output_caret),
		@"autoScrollOutput":     @(cmd.auto_scroll_output),
	};
}

// =====================
// = Item templates    =
// =====================

namespace
{
	struct expand_visitor_t : boost::static_visitor<void>
	{
		expand_visitor_t (std::map<std::string, std::string> const& variables) : _variables(variables) { }

		void operator() (bool value) const                     { }
		void operator() (int32_t value) const                  { }
		void operator() (uint64_t value) const                 { }
		void operator() (oak::date_t const& value) const       { }
		void operator() (std::vector<char> const& value) const { }
		void operator() (std::string& str) const               { str = format_string::expand(str, _variables); }
		void operator() (plist::array_t& array) const          { for(auto& item : array) boost::apply_visitor(*this, item); }
		void operator() (plist::dictionary_t& dict) const      { for(auto& pair : dict)  boost::apply_visitor(*this, pair.second); }

	private:
		std::map<std::string, std::string> const& _variables;
	};
}

NSDictionary* BEExpandVariables (NSDictionary* plist, NSDictionary<NSString*, NSString*>* variables)
{
	std::map<std::string, std::string> cxxVariables;
	for(NSString* key in variables)
		cxxVariables.emplace(to_s(key), to_s(variables[key]));

	plist::dictionary_t expanded = plist::convert((__bridge CFPropertyListRef)(plist ?: @{}));
	expand_visitor_t visitor(cxxVariables);
	visitor(expanded);

	return ObjectFromAny(expanded);
}

NSDictionary<NSString*, NSString*>* BEDefaultTemplateVariables (void)
{
	NSMutableDictionary<NSString*, NSString*>* res = [NSMutableDictionary dictionary];
	for(auto const& pair : variables_for_path(oak::basic_environment()))
	{
		NSString* key   = [NSString stringWithCxxString:pair.first];
		NSString* value = [NSString stringWithCxxString:pair.second];
		if(key && value)
			res[key] = value;
	}

	ABMutableMultiValue* value = [ABAddressBook.sharedAddressBook.me valueForProperty:kABEmailProperty];
	if(NSString* email = [value valueAtIndex:[value indexForIdentifier:value.primaryIdentifier]])
		res[@"TM_ROT13_EMAIL"] = BERot13(email);

	return res;
}

NSString* BEFixShebang (NSString* command)
{
	std::string str = to_s(command);
	command::fix_shebang(&str);
	return [NSString stringWithCxxString:str] ?: @"";
}

NSString* BERot13 (NSString* string)
{
	return [NSString stringWithCxxString:decode::rot13(string.UTF8String ?: "")];
}
