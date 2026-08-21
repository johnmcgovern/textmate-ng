#import "../src/ui/SearchField.h"

// Written against the ObjC++ OakLinkedSearchField, before the Swift port (rule 18).
// OakChooser makes one with -initWithFrame: and relies on it carrying the private
// OakLinkedSearchFieldCell — the cell exists only to fake a leading and trailing
// space around the filter string for VoiceOver (rdar://16271507). The ObjC++ wires
// that cell in +initialize via +setCellClass:; Swift has no +initialize (rule 20),
// so the port has to re-establish the same cell class through some other mechanism.
// This pins exactly that wiring: the field's class-level cellClass and the cell a
// fresh field actually builds must both be the custom NSSearchFieldCell subclass,
// not the stock one. A port that lost the registration would compile and run with a
// plain search field, silently dropping the accessibility workaround.
//
// The ±1-space translation itself lives in the cell's accessibility overrides and is
// only observable through a live VoiceOver client, so it is left to on-device AX
// testing, not asserted here.

void setup ()
{
	NSApplicationLoad();
}

void test_linked_search_field_is_constructible ()
{
	OakLinkedSearchField* field = [[OakLinkedSearchField alloc] initWithFrame:NSZeroRect];
	OAK_ASSERT(field != nil);
	OAK_ASSERT([field isKindOfClass:NSSearchField.class]);
}

void test_linked_search_field_registers_its_custom_cell ()
{
	Class cellClass = [OakLinkedSearchField cellClass];
	OAK_ASSERT(cellClass != Nil);
	OAK_ASSERT([cellClass isSubclassOfClass:NSSearchFieldCell.class]);
	OAK_ASSERT(cellClass != NSSearchFieldCell.class);

	OakLinkedSearchField* field = [[OakLinkedSearchField alloc] initWithFrame:NSZeroRect];
	OAK_ASSERT([field.cell isMemberOfClass:cellClass]);
}
