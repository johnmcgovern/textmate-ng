// The wrap-column constants, split out of OakTextView.h (rule 11).
//
// They were three lines at the top of a header whose next line is
// `#import <command/parser.h>` and which goes on to declare `bundles::item_ptr`
// and a std::map-returning method — so anything wanting these constants had to
// take all of that too, and no Swift bridging header can.
//
// The one outside consumer is AppController's Wrap Column menu, which needs
// nothing else from OakTextView.h at all.
//
// OakTextView.h imports this, so no existing consumer changed. Rule 61 settled
// that Swift reads an `extern … const` without trouble; the only question was
// ever whether the declaration could be reached.
#import <Foundation/Foundation.h>

// Tags for the two non-numeric entries of the Wrap Column menu. Deliberately
// outside the range of any real column: -takeWrapColumnFrom: switches on them.
extern int32_t const NSWrapColumnWindowWidth;
extern int32_t const NSWrapColumnAskUser;

extern NSString* const kUserDefaultsWrapColumnPresetsKey;
