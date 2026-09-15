#import "OakDocumentWalk.h"
#import "OakDocumentControllerConstants.h"
#import "OakDocument.h"
#import <ns/ns.h>
#import <io/entries.h>
#import <text/ctype.h>
#import <regexp/glob.h>
#import <oak/debug.h>

@implementation OakDocumentWalk
+ (void)enumerateDocumentsAtPaths:(NSArray*)items options:(NSDictionary*)someOptions openDocumentsInDirectory:(OakDocumentWalkOpenDocuments)openDocuments usingBlock:(void(^)(OakDocument* document, BOOL* stop))block
{
	BOOL stop = NO;

	BOOL followDirectoryLinks = [someOptions[kSearchFollowDirectoryLinksKey] boolValue];
	BOOL followFileLinks      = [someOptions[kSearchFollowFileLinksKey] boolValue] || !someOptions[kSearchFollowFileLinksKey];
	BOOL depthFirst           = [someOptions[kSearchDepthFirstSearchKey] boolValue];
	BOOL ignoreOrdering       = [someOptions[kSearchIgnoreOrderingKey] boolValue];

	static std::vector<std::pair<NSString*, size_t>> const map = {
		{ kSearchExcludeDirectoryGlobsKey, path::kPathItemDirectory | path::kPathItemExclude },
		{ kSearchExcludeFileGlobsKey,      path::kPathItemFile      | path::kPathItemExclude },
		{ kSearchExcludeGlobsKey,          path::kPathItemAny       | path::kPathItemExclude },
		{ kSearchDirectoryGlobsKey,        path::kPathItemDirectory                          },
		{ kSearchFileGlobsKey,             path::kPathItemFile                               },
		{ kSearchGlobsKey,                 path::kPathItemAny                                },
	};

	path::glob_list_t globs;
	for(auto const& pair : map)
	{
		for(NSString* glob in someOptions[pair.first])
			globs.add_glob(to_s(glob), pair.second);
	}

	std::set<std::pair<dev_t, ino_t>> didScan;
	std::deque<std::string> dirs;
	std::vector<std::string> links;

	for(NSString* item in items)
	{
		struct stat buf;
		if(lstat([item fileSystemRepresentation], &buf) != -1)
		{
			if(S_ISDIR(buf.st_mode) && didScan.emplace(buf.st_dev, buf.st_ino).second)
				dirs.push_back(to_s(item));
			else if(S_ISLNK(buf.st_mode))
				links.push_back(to_s(item));
			else if(S_ISREG(buf.st_mode) && didScan.emplace(buf.st_dev, buf.st_ino).second)
			{
				block([OakDocument documentWithPath:item], &stop);
				if(stop)
					break;
			}
		}
		else
		{
			perrorf("OakDocumentController: lstat(\"%s\")", [item fileSystemRepresentation]);
		}
	}

	NSMutableSet<NSUUID*>* didSee = [NSMutableSet set];
	for(std::string const& dir : dirs)
	{
		NSArray* documents = openDocuments(to_ns(dir), ignoreOrdering);
		for(OakDocument* document in documents)
		{
			if([didSee containsObject:document.identifier])
				continue;
			[didSee addObject:document.identifier];

			if(document.path)
			{
				std::string const path = to_s(document.path);
				if(globs.exclude(path, path::kPathItemFile))
					continue;

				struct stat buf;
				if(lstat([document.path fileSystemRepresentation], &buf) == -1)
				{
					perrorf("lstat(\"%s\")", [document.path fileSystemRepresentation]);
					continue;
				}

				if(didScan.emplace(buf.st_dev, buf.st_ino).second == false)
					continue;
			}

			block(document, &stop);
			if(stop)
				return;
		}
	}

	while(stop == NO && !dirs.empty())
	{
		std::string dir = dirs.front();
		dirs.pop_front();

		struct stat buf;
		if(lstat(dir.c_str(), &buf) == -1) // get st_dev so we don’t need to stat each path entry (unless it is a symbolic link)
		{
			perrorf("OakDocumentController: lstat(\"%s\")", dir.c_str());
			continue;
		}

		ASSERT(S_ISDIR(buf.st_mode) || S_ISLNK(buf.st_mode));

		std::vector<std::string> newDirs;
		std::set<std::string, text::less_t> files;
		for(auto const& it : path::entries(dir))
		{
			std::string const& path = path::join(dir, it->d_name);
			if(it->d_type == DT_DIR)
			{
				if(globs.exclude(path, path::kPathItemDirectory))
					continue;

				if(didScan.emplace(buf.st_dev, it->d_ino).second)
					newDirs.push_back(path);
			}
			else if(it->d_type == DT_REG)
			{
				if(globs.exclude(path, path::kPathItemFile))
					continue;

				if(didScan.emplace(buf.st_dev, it->d_ino).second)
					files.emplace(path);
			}
			else if(it->d_type == DT_LNK && (followDirectoryLinks || followFileLinks))
			{
				links.push_back(path); // handle later since link may point to another device plus if link is “local” and will be seen later, we reported the local path rather than this link
			}
		}

		std::sort(newDirs.begin(), newDirs.end(), text::less_t());
		dirs.insert(depthFirst ? dirs.begin() : dirs.end(), newDirs.begin(), newDirs.end());

		if(dirs.empty())
		{
			for(auto const& link : links)
			{
				std::string const path = path::resolve(link);
				if(lstat(path.c_str(), &buf) != -1)
				{
					if(S_ISDIR(buf.st_mode) && followDirectoryLinks && didScan.emplace(buf.st_dev, buf.st_ino).second)
					{
						if(globs.exclude(path, path::kPathItemDirectory))
							continue;
						dirs.push_back(path);
					}
					else if(S_ISREG(buf.st_mode) && followFileLinks)
					{
						if(globs.exclude(path, path::kPathItemFile))
							continue;

						if(didScan.emplace(buf.st_dev, buf.st_ino).second)
							files.emplace(path);
					}
				}
				else
				{
					perrorf("OakDocumentController: path::resolve(\"%s\") → lstat(\"%s\")", link.c_str(), path.c_str());
				}
			}
			links.clear();
		}

		for(auto const& file : files)
		{
			block([OakDocument documentWithPath:to_ns(file)], &stop);
			if(stop)
				break;
		}
	}
}
@end
