#import "PWSupport.h"
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakFoundation/NSString Additions.h>
#import <bundles/bundles.h>
#import <io/exec.h>
#import <io/path.h>
#import <ns/ns.h>
#import <regexp/format_string.h>
#import <regexp/regexp.h>
#import <settings/settings.h>
#import <text/format.h>
#import <text/ctype.h>
#import <oak/compat.h>
#import <oak/oak.h>

// ============
// = settings =
// ============

NSString* PWSettingsEncodingKey (void)    { return [NSString stringWithCxxString:kSettingsEncodingKey];    }
NSString* PWSettingsLineEndingsKey (void) { return [NSString stringWithCxxString:kSettingsLineEndingsKey]; }
NSString* PWSettingsFileTypeKey (void)    { return [NSString stringWithCxxString:kSettingsFileTypeKey];    }
NSString* PWSettingsExcludeKey (void)     { return [NSString stringWithCxxString:kSettingsExcludeKey];     }
NSString* PWSettingsIncludeKey (void)     { return [NSString stringWithCxxString:kSettingsIncludeKey];     }
NSString* PWSettingsBinaryKey (void)      { return [NSString stringWithCxxString:kSettingsBinaryKey];      }

NSString* PWSettingsRawGet (NSString* key, NSString* section)
{
	std::string const res = settings_t::raw_get(to_s(key), section ? to_s(section) : "");
	// NULL_STR means "unset". The ObjC++ original returned it verbatim through
	// +stringWithCxxString:, which yields the U+FFFF sentinel *as a string* —
	// converting it to nil here is the one deliberate behavior change in this
	// port, and it is the correct one: a bound text field showed the sentinel
	// glyph instead of an empty field.
	return res == NULL_STR ? nil : [NSString stringWithCxxString:res];
}

void PWSettingsSet (NSString* key, NSString* value, NSString* fileType)
{
	settings_t::set(to_s(key), value ? to_s(value) : "", fileType ? to_s(fileType) : "");
}

// ============
// = grammars =
// ============

NSArray<NSDictionary<NSString*, NSString*>*>* PWGrammarList (void)
{
	std::multimap<std::string, bundles::item_ptr, text::less_t> grammars;
	for(auto const& item : bundles::query(bundles::kFieldAny, NULL_STR, scope::wildcard, bundles::kItemTypeGrammar))
	{
		if(!item->hidden_from_user())
			grammars.emplace(item->name(), item);
	}

	NSMutableArray* res = [NSMutableArray array];
	for(auto const& pair : grammars)
	{
		std::string const& fileType = pair.second->value_for_field(bundles::kFieldGrammarScope);
		if(fileType == NULL_STR)
			continue;
		[res addObject:@{
			@"name":  [NSString stringWithCxxString:pair.first],
			@"scope": [NSString stringWithCxxString:fileType],
		}];
	}
	return res;
}

// ===========
// = general =
// ===========

NSString* PWExpandFormatString (NSString* format, NSDictionary<NSString*, NSString*>* variables)
{
	std::map<std::string, std::string> map;
	for(NSString* key in variables)
		map[to_s(key)] = to_s(variables[key]);
	return [NSString stringWithCxxString:format_string::expand(to_s(format), map)];
}

// Was OakSetupGridViewWithSeparators in PreferencesPane.h/.mm (both of which the
// Swift port replaces). Moved here verbatim apart from the parameter type: the
// original took std::vector<NSUInteger> with a default argument.
NSView* PWSetupGridView (NSGridView* gridView, NSArray<NSNumber*>* separatorRows)
{
	gridView.rowAlignment = NSGridRowAlignmentFirstBaseline;
	gridView.rowSpacing   = 8;

	[gridView rowAtIndex:0].topPadding                                  = 20;
	[gridView rowAtIndex:gridView.numberOfRows-1].bottomPadding         = 20;
	[gridView columnAtIndex:0].xPlacement                               = NSGridCellPlacementTrailing;
	[gridView columnAtIndex:0].leadingPadding                           = 8;
	[gridView columnAtIndex:0].width                                    = 200;
	[gridView columnAtIndex:gridView.numberOfColumns-1].trailingPadding = 8;
	[gridView columnAtIndex:gridView.numberOfColumns-1].width           = 400;

	for(NSUInteger row = 0; row < gridView.numberOfRows; ++row)
		[gridView cellAtColumnIndex:0 rowIndex:row].yPlacement = NSGridCellPlacementNone;

	for(NSNumber* rowNumber in separatorRows)
	{
		NSUInteger const row = rowNumber.unsignedIntegerValue;
		[gridView mergeCellsInHorizontalRange:NSMakeRange(0, gridView.numberOfColumns) verticalRange:NSMakeRange(row, 1)];
		[gridView cellAtColumnIndex:0 rowIndex:row].contentView = OakCreateNSBoxSeparator();
		[gridView cellAtColumnIndex:0 rowIndex:row].xPlacement  = NSGridCellPlacementFill;
		[gridView cellAtColumnIndex:0 rowIndex:row].yPlacement  = NSGridCellPlacementCenter;
		[gridView rowAtIndex:row].topPadding    = 12;
		[gridView rowAtIndex:row].bottomPadding = 12;
		[gridView rowAtIndex:row].rowAlignment  = NSGridRowAlignmentNone;
	}

	[gridView setContentHuggingPriority:NSLayoutPriorityDefaultHigh-2 forOrientation:NSLayoutConstraintOrientationVertical];
	gridView.frame = { .size = gridView.fittingSize };

	return gridView;
}

// ========================
// = `mate` shell support =
// ========================

static bool run_auth_command (AuthorizationRef& auth, std::string const cmd, ...)
{
	if(!auth && AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &auth) != errAuthorizationSuccess)
		return false;

	std::vector<char*> args;

	va_list ap;
	va_start(ap, cmd);
	char* arg = NULL;
	while((arg = va_arg(ap, char*)) && *arg)
		args.push_back(arg);
	va_end(ap);

	args.push_back(NULL);

	bool res = false;
	if(oak::execute_with_privileges(auth, cmd, kAuthorizationFlagDefaults, &args[0], NULL) == errAuthorizationSuccess)
	{
		int status;
		int pid = wait(&status);
		if(pid != -1 && WIFEXITED(status) && WEXITSTATUS(status) == 0)
				res = true;
		else	errno = WEXITSTATUS(status);
	}
	else
	{
		errno = EPERM;
	}
	return res;
}

static bool mk_dir (std::string const& path, AuthorizationRef& auth)
{
	struct stat buf;
	if(stat(path.c_str(), &buf) == 0)
	{
		if(S_ISDIR(buf.st_mode))
			return true;
	}
	else if(path != "/" && mk_dir(path::parent(path), auth))
	{
		if(access(path::parent(path).c_str(), W_OK) == 0)
		{
			if(mkdir(path.c_str(), S_IRWXU|S_IRWXG|S_IRWXO) == 0)
				return true;
			perrorf("TerminalPreferences: mkdir(\"%s\")", path.c_str());
		}
		else
		{
			if(run_auth_command(auth, "/bin/mkdir", path.c_str(), NULL))
				return true;
			perrorf("TerminalPreferences: /bin/mkdir \"%s\"", path.c_str());
		}
	}
	return false;
}

static bool rm_path (std::string const& path, AuthorizationRef& auth)
{
	struct stat buf;
	if(lstat(path.c_str(), &buf) != 0)
		return true;

	if(access(path::parent(path).c_str(), W_OK) == 0)
	{
		if(unlink(path.c_str()) == 0)
			return true;
		perrorf("TerminalPreferences: unlink \"%s\"", path.c_str());
	}
	else
	{
		if(run_auth_command(auth, "/bin/rm", path.c_str(), NULL))
			return true;
		perrorf("TerminalPreferences: /bin/rm \"%s\"", path.c_str());
	}
	return false;
}

static bool cp_requires_admin (std::string const& dst)
{
	return access(dst.c_str(), W_OK) != 0 && (access(dst.c_str(), X_OK) == 0 || access(path::parent(dst).c_str(), W_OK) != 0);
}

static bool cp_path (std::string const& src, std::string const& dst, AuthorizationRef& auth)
{
	if(!cp_requires_admin(dst))
	{
		if(copyfile(src.c_str(), dst.c_str(), NULL, COPYFILE_ALL | COPYFILE_NOFOLLOW_SRC) == 0)
			return true;
		perrorf("TerminalPreferences: copyfile(\"%s\", \"%s\", NULL, COPYFILE_ALL | COPYFILE_NOFOLLOW_SRC)", src.c_str(), dst.c_str());
	}
	else
	{
		if(run_auth_command(auth, "/bin/cp", "-p", src.c_str(), dst.c_str(), NULL))
			return true;
		perrorf("TerminalPreferences: /bin/cp -p \"%s\" \"%s\"", src.c_str(), dst.c_str());
	}
	return false;
}

BOOL PWCopyRequiresAdmin (NSString* path)
{
	return cp_requires_admin(to_s(path)) ? YES : NO;
}

BOOL PWInstallMate (NSString* srcPath, NSString* dstPath)
{
	std::string const src = to_s(srcPath);
	std::string const dst = to_s(dstPath);

	AuthorizationRef auth = NULL;
	if(mk_dir(path::parent(dst), auth))
	{
		struct stat buf;
		if(lstat(dst.c_str(), &buf) == 0 && !S_ISREG(buf.st_mode) && !rm_path(dst, auth))
			return NO;
		return cp_path(src, dst, auth) ? YES : NO;
	}
	return NO;
}

BOOL PWUninstallMate (NSString* path)
{
	std::string const p = to_s(path);
	AuthorizationRef auth = NULL;
	return (access(p.c_str(), F_OK) != 0 || rm_path(p, auth)) ? YES : NO;
}

NSString* PWMateVersion (NSString* matePath)
{
	std::string const res = io::exec(to_s(matePath), "--version", NULL);
	if(regexp::match_t const& m = regexp::search("\\Amate ([\\d.]+)", res))
		return [NSString stringWithCxxString:m[1]];
	return nil;
}
