#import "../src/FileItem.h"

// MountedVolumesFileItem is a Swift FileItem subclass reached only through the
// scheme registry. This pins that the "computer" scheme still resolves to it and
// that its localizedName override (the host name) survives — both invisible to
// the compiler since the class is never named directly.

void setup ()
{
	NSApplicationLoad();
}

void test_computer_scheme_resolves_to_mounted_volumes_item ()
{
	Class klass = [FileItem classForURL:[NSURL URLWithString:@"computer:///"]];
	OAK_ASSERT(klass != nil);
	OAK_ASSERT([NSStringFromClass(klass) isEqualToString:@"MountedVolumesFileItem"]);

	FileItem* item = [FileItem fileItemWithURL:[NSURL URLWithString:@"computer:///"]];
	OAK_ASSERT(item != nil);
	OAK_ASSERT([item isKindOfClass:[FileItem class]]);
	OAK_ASSERT([item.localizedName isEqualToString:NSHost.currentHost.localizedName]);
}
