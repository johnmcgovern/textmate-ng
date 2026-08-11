#import "DWScopeContextCxx.h"
#import <OakFoundation/NSString Additions.h>
#import <file/path_info.h>
#import <io/entries.h>
#import <io/path.h>
#import <ns/ns.h>
#import <regexp/glob.h>
#import <regexp/regexp.h>
#import <scm/scm.h>
#import <settings/settings.h>
#import <text/format.h>
#import <text/parse.h>

// The C++ half of a project window's scope and SCM state. See DWScopeContext.h
// for why this class exists at all.
//
// Everything below the interface was moved from DocumentWindowController.mm
// rather than retyped — the rule this project earned on FFResultNodeSupport.mm.
// The attribute-rule table especially: it is nineteen marker files whose order
// and grouping decide which `attr.project.*` a window gets, it has no test that
// could catch a transcription slip, and nobody would notice one until a bundle
// command stopped matching.

// The scope attributes derived from marker files found between the document and
// the project root. `group` means "having matched one of these, stop looking for
// others in the same group" — so a repository with both .git and .hg reports one
// SCM, and a project with a Makefile and a build.ninja reports one build system.
// NULL_STR as a group means "no group", i.e. always report it.
namespace
{
	struct attribute_rule_t { std::string attribute; path::glob_t glob; std::string group; };

	static std::vector<attribute_rule_t> const& AttributeRules ()
	{
		static auto const rules = new std::vector<attribute_rule_t>
		{
			{ "attr.scm.svn",         ".svn",           "scm"     },
			{ "attr.scm.hg",          ".hg",            "scm"     },
			{ "attr.scm.git",         ".git",           "scm"     },
			{ "attr.scm.p4",          ".p4config",      "scm"     },
			{ "attr.project.ninja",   "build.ninja",    "build"   },
			{ "attr.project.make",    "Makefile",       "build"   },
			{ "attr.project.xcode",   "*.xcodeproj",    "build"   },
			{ "attr.project.rake",    "Rakefile",       "build"   },
			{ "attr.project.ant",     "build.xml",      "build"   },
			{ "attr.project.cmake",   "CMakeLists.txt", "build"   },
			{ "attr.project.maven",   "pom.xml",        "build"   },
			{ "attr.project.scons",   "SConstruct",     "build"   },
			{ "attr.project.lein",    "project.clj",    "build"   },
			{ "attr.project.cargo",   "Cargo.toml",     "build"   },
			{ "attr.project.swift",   "Package.swift",  "build"   },
			{ "attr.project.vagrant", "Vagrantfile",    NULL_STR  },
			{ "attr.project.jekyll",  "_config.yml",    NULL_STR  },
			{ "attr.project.rave",    "default.rave",   NULL_STR  },
			{ "attr.test.rspec",      ".rspec",         "test"    },
		};
		return *rules;
	}

	static NSDictionary<NSString*, NSString*>* ToDictionary (std::map<std::string, std::string> const& map)
	{
		NSMutableDictionary* res = [NSMutableDictionary dictionary];
		for(auto const& pair : map)
			res[to_ns(pair.first)] = to_ns(pair.second);
		return [res copy];
	}
}

@implementation DWScopeContext
{
	scm::info_ptr                      _projectSCMInfo;
	std::map<std::string, std::string> _projectSCMVariables;
	std::vector<std::string>           _projectScopeAttributes;  // kSettingsScopeAttributesKey
	std::vector<std::string>           _externalScopeAttributes; // attr.scm.git, attr.project.ninja

	scm::info_ptr                      _documentSCMInfo;
	std::map<std::string, std::string> _documentSCMVariables;
	std::vector<std::string>           _documentScopeAttributes; // attr.os-version, attr.untitled / attr.rev-path + kSettingsScopeAttributesKey

	NSString*                          _documentPath;
}

// The shared_ptrs must be released while this object is still alive; a Swift
// owner cannot do it, which is a large part of why this class exists.
- (void)dealloc
{
	if(_projectSCMInfo)
		_projectSCMInfo->pop_callback();
	if(_documentSCMInfo)
		_documentSCMInfo->pop_callback();
}

// ==========================================
// = Paths in                               =
// ==========================================

- (void)setProjectPath:(NSString*)newProjectPath
{
	if(_projectPath == newProjectPath || [_projectPath isEqualToString:newProjectPath])
		return;

	_projectPath = newProjectPath;

	if(_projectSCMInfo)
		_projectSCMInfo->pop_callback();

	if(_projectSCMInfo = scm::info(to_s(_projectPath)))
	{
		__weak DWScopeContext* weakSelf = self;
		_projectSCMInfo->push_callback(^(scm::info_t const& info){
			[weakSelf setProjectSCMVariables:info.scm_variables()];
		});
	}
	else
	{
		[self setProjectSCMVariables:std::map<std::string, std::string>()];
	}

	_projectScopeAttributes.clear();

	// Note the lookup passes the attribute list it is about to replace, which is
	// empty at this point — carried over as-is, because a settings file could in
	// principle select on it and changing that is a behaviour question.
	std::string const customAttributes = settings_for_path(NULL_STR, text::join(_projectScopeAttributes, " "), to_s(_projectPath)).get(kSettingsScopeAttributesKey, NULL_STR);
	if(customAttributes != NULL_STR)
		_projectScopeAttributes.push_back(customAttributes);
}

- (void)setDocumentPath:(NSString*)newDocumentPath fileType:(NSString*)fileType
{
	// The `|| empty` half is load-bearing: a window that opens with no document
	// has no attributes, and this is how it picks them up when one arrives.
	BOOL const pathChanged = _documentPath != newDocumentPath && ![_documentPath isEqualToString:newDocumentPath];
	if(!pathChanged && !_documentScopeAttributes.empty())
		return;

	_documentPath            = newDocumentPath;
	_documentScopeAttributes = text::split(file::path_attributes(to_s(_documentPath)), " ");

	std::string const docDirectory = _documentPath ? path::parent(to_s(_documentPath)) : to_s(_projectPath);

	if(fileType)
	{
		std::string const customAttributes = settings_for_path(to_s(_documentPath), to_s(fileType) + " " + text::join(_documentScopeAttributes, " "), docDirectory).get(kSettingsScopeAttributesKey, NULL_STR);
		if(customAttributes != NULL_STR)
			_documentScopeAttributes.push_back(customAttributes);
	}

	[self setDocumentSCMVariables:std::map<std::string, std::string>()];

	if(_documentSCMInfo)
		_documentSCMInfo->pop_callback();

	if(_documentSCMInfo = scm::info(docDirectory))
	{
		__weak DWScopeContext* weakSelf = self;
		_documentSCMInfo->push_callback(^(scm::info_t const& info){
			[weakSelf setDocumentSCMVariables:info.scm_variables()];
		});
	}
}

- (void)updateExternalAttributesForDocumentPath:(NSString*)documentPath
{
	_externalScopeAttributes.clear();
	if(!documentPath && !_projectPath)
		return;

	std::string const projectDir  = to_s(_projectPath ?: NSHomeDirectory());
	std::string const documentStr = documentPath ? to_s(documentPath) : path::join(projectDir, "dummy");

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{

		std::vector<std::string> res;
		std::set<std::string> groups;
		std::string dir = documentStr;
		do {

			dir = path::parent(dir);
			auto entries = path::entries(dir);

			for(auto rule : AttributeRules())
			{
				if(groups.find(rule.group) != groups.end())
					continue;

				for(auto entry : entries)
				{
					if(rule.glob.does_match(entry->d_name))
					{
						res.push_back(rule.attribute);
						if(rule.group != NULL_STR)
						{
							groups.insert(rule.group);
							break;
						}
					}
				}
			}

		} while(path::is_child(dir, projectDir) && dir != projectDir);

		dispatch_async(dispatch_get_main_queue(), ^{
			// Discard the result if either path moved while the walk ran — the
			// window may be showing something else entirely by now.
			std::string const currentProjectDir = to_s(self->_projectPath ?: NSHomeDirectory());
			std::string const currentDocument   = documentPath ? to_s(documentPath) : path::join(currentProjectDir, "dummy");
			if(projectDir == currentProjectDir && documentStr == currentDocument)
				self->_externalScopeAttributes = res;
		});

	});
}

// ==========================================
// = SCM variables                          =
// ==========================================

- (void)setProjectSCMVariables:(std::map<std::string, std::string> const&)newVariables
{
	if(_projectSCMVariables != newVariables)
	{
		_projectSCMVariables = newVariables;
		if(_variablesDidChange)
			_variablesDidChange();
	}
}

- (void)setDocumentSCMVariables:(std::map<std::string, std::string> const&)newVariables
{
	if(_documentSCMVariables != newVariables)
	{
		_documentSCMVariables = newVariables;
		if(_variablesDidChange)
			_variablesDidChange();
	}
}

// The rule the ObjC++ wrote out five times, in one place.
- (std::map<std::string, std::string> const&)effectiveSCMVariablesMap
{
	return _documentSCMVariables.empty() ? _projectSCMVariables : _documentSCMVariables;
}

- (NSDictionary<NSString*, NSString*>*)effectiveSCMVariables
{
	return ToDictionary(self.effectiveSCMVariablesMap);
}

- (NSArray<NSString*>*)externalScopeAttributes
{
	NSMutableArray* res = [NSMutableArray array];
	for(auto const& attr : _externalScopeAttributes)
		[res addObject:to_ns(attr)];
	return [res copy];
}

// ==========================================
// = What consumers read                    =
// ==========================================

- (NSString*)scopeAttributesWithSCMStatusAttribute:(NSString*)scmStatusAttribute
{
	std::set<std::string> attributes;

	auto const& vars = self.effectiveSCMVariablesMap;
	auto scmName = vars.find("TM_SCM_NAME");
	if(scmName != vars.end())
		attributes.insert("attr.scm." + scmName->second);
	auto branch = vars.find("TM_SCM_BRANCH");
	if(branch != vars.end())
		attributes.insert("attr.scm.branch." + branch->second);

	if(scmStatusAttribute)
		attributes.insert(to_s(scmStatusAttribute));

	attributes.insert(_documentScopeAttributes.begin(), _documentScopeAttributes.end());
	attributes.insert(_projectScopeAttributes.begin(), _projectScopeAttributes.end());
	attributes.insert(_externalScopeAttributes.begin(), _externalScopeAttributes.end());

	return [NSString stringWithCxxString:text::join(attributes, " ")];
}

- (NSDictionary<NSString*, NSString*>*)scmNameVariables
{
	std::map<std::string, std::string> res;

	auto const& scmVars = self.effectiveSCMVariablesMap;
	if(!scmVars.empty())
	{
		auto scmName = scmVars.find("TM_SCM_NAME");
		if(scmName != scmVars.end())
			res["TM_SCM_NAME"] = scmName->second;
	}
	else
	{
		// No repository at the document, but a marker file upstream still names
		// one — this is what makes TM_SCM_NAME available in a checkout whose
		// working copy metadata is not where the document is.
		for(auto const& attr : _externalScopeAttributes)
		{
			if(regexp::match_t const& m = regexp::search("^attr.scm.(?'TM_SCM_NAME'\\w+)$", attr))
			{
				res.insert(m.captures().begin(), m.captures().end());
				break;
			}
		}
	}

	return ToDictionary(res);
}
@end
