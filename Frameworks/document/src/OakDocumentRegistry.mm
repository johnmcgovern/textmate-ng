#import "OakDocumentRegistry.h"
#import "OakDocument Private.h"
#import <plist/uuid.h>
#import <ns/ns.h>
#import <oak/debug.h>

namespace
{
	struct inode_t
	{
		inode_t () { }
		inode_t (dev_t device, ino_t inode, std::string const& path);
		inode_t (std::string const& path);

		operator bool () const { return valid; }
		bool operator== (inode_t const& rhs) const { return valid == rhs.valid && inode == rhs.inode && device == rhs.device; }
		bool operator!= (inode_t const& rhs) const { return valid != rhs.valid || inode != rhs.inode || device != rhs.device; }
		bool operator< (inode_t const& rhs) const;

		dev_t device = 0;
		ino_t inode  = 0;
		bool valid   = false;
	};

	static bool is_inode_valid (ino_t inode, std::string const& path)
	{
		if(inode == 999999999) // Zero-length files on FAT file systems share this magic value
		{
			struct statfs sfsb;
			if(statfs(path.c_str(), &sfsb) == 0)
				return strcasecmp(sfsb.f_fstypename, "msdos") == 0 && strcasecmp(sfsb.f_fstypename, "exfat") == 0;
			perrorf("is_inode_valid: statfs(\"%s\")", path.c_str());
		}
		return true;
	}

	inode_t::inode_t (dev_t device, ino_t inode, std::string const& path) : device(device), inode(inode), valid(true)
	{
		if(!is_inode_valid(inode, path))
		{
			device = 0;
			inode  = 0;
			valid  = false;
		}
	}

	inode_t::inode_t (std::string const& path)
	{
		struct stat buf;
		if(lstat(path.c_str(), &buf) == 0)
		{
			if(is_inode_valid(buf.st_ino, path))
			{
				device = buf.st_dev;
				inode  = buf.st_ino;
				valid  = true;
			}
		}
	}

	bool inode_t::operator< (inode_t const& rhs) const
	{
		return std::make_tuple(valid ? 1 : 0, inode, device) < std::make_tuple(rhs.valid ? 1 : 0, rhs.inode, rhs.device);
	}

	struct record_t
	{
		oak::uuid_t uuid;
		std::string path;
		inode_t inode;
		__weak OakDocument* document;
	};

	typedef std::shared_ptr<record_t> record_ptr;
}

@interface OakDocumentRegistry ()
{
	std::mutex                        _lock;
	std::map<oak::uuid_t, record_ptr> _documents_by_uuid;
	std::map<std::string, record_ptr> _documents_by_path;
	std::map<inode_t, record_ptr>     _documents_by_inode;
}
@end

@implementation OakDocumentRegistry
- (OakDocument*)documentForPath:(NSString*)aPath
{
	std::lock_guard<std::mutex> lock(_lock);
	OakDocument* doc;

	if(aPath)
	{
		auto pathIter = _documents_by_path.find(to_s(aPath));
		if(pathIter != _documents_by_path.end())
			doc = pathIter->second->document;

		if(!doc)
		{
			auto inodeIter = _documents_by_inode.find(inode_t(to_s(aPath)));
			if(inodeIter != _documents_by_inode.end())
				doc = inodeIter->second->document;
		}
	}

	if(!doc)
	{
		doc = [[OakDocument alloc] initWithPath:aPath];
		[self internalAddDocument:doc];
	}
	return doc;
}

- (OakDocument*)documentForIdentifier:(NSUUID*)anUUID
{
	std::lock_guard<std::mutex> lock(_lock);
	auto it = _documents_by_uuid.find(to_s(anUUID));
	if(it != _documents_by_uuid.end())
		return it->second->document;
	return nil;
}

- (void)addDocument:(OakDocument*)aDocument
{
	std::lock_guard<std::mutex> lock(_lock);
	[self internalAddDocument:aDocument];
}

- (void)removeDocument:(OakDocument*)aDocument
{
	std::lock_guard<std::mutex> lock(_lock);
	[self internalRemoveDocument:aDocument];
}

- (void)updateDocument:(OakDocument*)aDocument
{
	std::lock_guard<std::mutex> lock(_lock);
	[self internalRemoveDocument:aDocument];
	[self internalAddDocument:aDocument];
}

- (NSUInteger)firstAvailableUntitledCount
{
	std::lock_guard<std::mutex> lock(_lock);

	std::set<NSUInteger> reserved;
	for(auto const& pair : _documents_by_uuid)
	{
		if(OakDocument* doc = pair.second->document)
		{
			if(!doc.path && !doc.customName)
				reserved.insert(doc.untitledCount);
		}
	}

	NSUInteger available = 1;
	while(reserved.find(available) != reserved.end())
		++available;
	return available;
}

- (NSArray<OakDocument*>*)documents
{
	std::lock_guard<std::mutex> lock(_lock);

	NSMutableArray<OakDocument*>* res = [NSMutableArray array];
	for(auto pair : _documents_by_uuid)
	{
		if(OakDocument* doc = pair.second->document)
			[res addObject:doc];
	}
	return res;
}

// ===================================================
// = Mutex must be locked when calling the following =
// ===================================================

- (void)internalAddDocument:(OakDocument*)doc
{
	auto r = std::make_shared<record_t>();
	r->uuid     = to_s(doc.identifier);
	r->path     = to_s(doc.path);
	r->inode    = inode_t(r->path);
	r->document = doc;

	ASSERT(_documents_by_uuid.find(r->uuid) == _documents_by_uuid.end());
	_documents_by_uuid.emplace(r->uuid, r);

	if(r->path != NULL_STR)
		_documents_by_path[r->path] = r;

	if(r->inode)
		_documents_by_inode[r->inode] = r;
}

- (void)internalRemoveDocument:(OakDocument*)doc
{
	oak::uuid_t const uuid = to_s(doc.identifier);
	auto it = _documents_by_uuid.find(uuid);
	ASSERT(it != _documents_by_uuid.end());
	if(it != _documents_by_uuid.end())
	{
		if(it->second->inode)
		{
			auto inodeIter = _documents_by_inode.find(it->second->inode);
			if(inodeIter != _documents_by_inode.end() && inodeIter->second->uuid == uuid)
				_documents_by_inode.erase(inodeIter);
		}

		if(it->second->path != NULL_STR)
		{
			auto pathIter = _documents_by_path.find(it->second->path);
			if(pathIter != _documents_by_path.end() && pathIter->second->uuid == uuid)
				_documents_by_path.erase(pathIter);
		}

		_documents_by_uuid.erase(it);
	}
}
@end
