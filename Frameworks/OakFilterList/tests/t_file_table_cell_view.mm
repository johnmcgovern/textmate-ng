#import "../src/OakFileTableCellView.h"

// Written against the ObjC++ OakFileTableCellView, before its Swift port (rule 18). The
// file/bundle choosers show it for each row; its contract is that -initWithCloseButton:
// wires an icon + two labels bound to objectValue.icon / .name / .folder, and that
// -setBackgroundStyle: swaps the matched-text colouring in and out on selection. Those
// bindings and the restyle are reachable without a live chooser, so they are judged here;
// the private folderTextField and the accessibility-children override are only observable
// through a running window and are left to the app.

void setup ()
{
	NSApplicationLoad();
}

void test_file_table_cell_view_is_constructible ()
{
	OakFileTableCellView* view = [[OakFileTableCellView alloc] initWithCloseButton:[NSButton new]];
	OAK_ASSERT(view != nil);
	OAK_ASSERT([view isKindOfClass:NSTableCellView.class]);
	OAK_ASSERT(view.imageView != nil);
	OAK_ASSERT(view.textField != nil);
}

void test_file_table_cell_view_binds_object_value ()
{
	OakFileTableCellView* view = [[OakFileTableCellView alloc] initWithCloseButton:[NSButton new]];
	NSImage* icon = [NSImage new];
	view.objectValue = @{ @"name": @"foo.txt", @"folder": @"~/bar", @"icon": icon };

	OAK_ASSERT([view.textField.stringValue isEqualToString:@"foo.txt"]);
	OAK_ASSERT(view.imageView.image == icon);
}

void test_file_table_cell_view_background_style_round_trips ()
{
	OakFileTableCellView* view = [[OakFileTableCellView alloc] initWithCloseButton:[NSButton new]];
	view.objectValue = @{ @"name": @"foo.txt", @"folder": @"~/bar" };

	view.backgroundStyle = NSBackgroundStyleEmphasized; // matched-text colouring in — must not throw
	view.backgroundStyle = NSBackgroundStyleNormal;     // and back to the plain name
	OAK_ASSERT([view.textField.stringValue isEqualToString:@"foo.txt"]);
}
