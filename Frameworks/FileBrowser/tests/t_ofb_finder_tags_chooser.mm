#import "../src/OFB/OFBFinderTagsChooser.h"

// OFBFinderTagsChooser is implemented in Swift behind a hand-written ObjC
// header. This pins that its factory still constructs a view and that the four
// members FileBrowserViewController reaches — target, action, chosenTag,
// removeChosenTag — survive the port, since a drift there is silent (an
// unrecognized selector at runtime, or a menu item whose click does nothing).
//
// The swatch drawing and the hover/caption behaviour can only be seen in the
// running app; they are verified there.

void setup ()
{
	NSApplicationLoad();
}

void test_ofb_finder_tags_chooser_is_constructible ()
{
	NSMenu* menu = [[NSMenu alloc] init];
	OFBFinderTagsChooser* chooser = [OFBFinderTagsChooser finderTagsChooserWithSelectedTags:@[] andSelectedTagsToRemove:@[] forMenu:menu];
	OAK_ASSERT(chooser != nil);
	OAK_ASSERT([chooser isKindOfClass:NSView.class]);
}

void test_ofb_finder_tags_chooser_keeps_its_surface ()
{
	SEL const selectors[] = {
		@selector(target), @selector(setTarget:),
		@selector(action), @selector(setAction:),
		@selector(chosenTag), @selector(removeChosenTag),
		@selector(didClickFinderTag:),
	};

	for(SEL selector : selectors)
		OAK_ASSERT([OFBFinderTagsChooser instancesRespondToSelector:selector]);
}
