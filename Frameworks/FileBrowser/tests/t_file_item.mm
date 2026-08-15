#import "../src/FileItem.h"

// FileItem is implemented in Swift behind a hand-written ObjC header, and it is
// the base of the ObjC++ subclasses (SCMStatusFileItem, MountedVolumesFileItem)
// resolved through the scheme registry. This pins:
//
//   * the registry: +classForURL: returns FileItem for "file" (the +load-free
//     registration actually runs), and +fileItemWithURL: builds one;
//   * the derived facts a real file URL produces — displayName, isDirectory;
//   * the KVO surface the row cell binds to (displayName / localizedName /
//     canRename / finderTags / editingAndDisplayName), which is invisible to the
//     compiler and to a green suite otherwise.

void setup ()
{
	NSApplicationLoad();
}

void test_file_item_registry_resolves_the_file_scheme ()
{
	OAK_ASSERT([FileItem classForURL:[NSURL fileURLWithPath:@"/tmp"]] == [FileItem class]);

	FileItem* item = [FileItem fileItemWithURL:[NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES]];
	OAK_ASSERT(item != nil);
	OAK_ASSERT([item isKindOfClass:[FileItem class]]);
}

void test_file_item_derives_properties_from_a_directory_url ()
{
	FileItem* item = [FileItem fileItemWithURL:[NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES]];
	OAK_ASSERT(item.isDirectory);
	OAK_ASSERT(item.displayName.length != 0);
	OAK_ASSERT([item.displayName isEqualToString:item.localizedName]); // no disambiguation suffix set

	// The volume root is the one directory that is not renamable; a plain folder
	// inside it is. Pins that canRename evaluates the volume check without trapping.
	FileItem* volume = [FileItem fileItemWithURL:[NSURL fileURLWithPath:@"/" isDirectory:YES]];
	OAK_ASSERT(volume.canRename == NO);
}

void test_file_item_keeps_its_kvo_surface ()
{
	SEL const selectors[] = {
		@selector(displayName), @selector(localizedName), @selector(setLocalizedName:),
		@selector(disambiguationSuffix), @selector(setDisambiguationSuffix:),
		@selector(toolTip), @selector(setToolTip:),
		@selector(canRename), @selector(finderTags), @selector(setFinderTags:),
		@selector(editingAndDisplayName),
		@selector(children), @selector(arrangedChildren),
		@selector(updateFileProperties),
	};

	for(SEL selector : selectors)
		OAK_ASSERT([FileItem instancesRespondToSelector:selector]);
}
