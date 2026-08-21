// An OakChooser subclass that counts the base's calls into the three overridable hooks.
//
// Defined rather than merely declared, and in a header, because ide/gen_xctest.rb wraps
// each test file's body in `namespace <basename>` and ObjC declarations may only appear
// at global scope — but it hoists every #import to the top (the DWKVORecorder pattern).
//
// This is the load-bearing half of t_chooser.mm: the ObjC++ base calls -updateItems:/
// -updateStatusText:/-updateFilterString: on self, and the four real choosers override
// them. A Swift port that exports those methods @objc but not dynamic would dispatch the
// base's internal calls through the Swift vtable and silently skip these overrides; the
// counters make that failure loud.
#import "../src/OakChooser.h"

@interface OakChooserTestSubclass : OakChooser
@property (nonatomic) NSUInteger updateItemsCalls;
@property (nonatomic) NSUInteger updateStatusTextCalls;
@property (nonatomic) NSUInteger updateFilterStringCalls;
@end

@implementation OakChooserTestSubclass
- (void)updateItems:(id)sender { self.updateItemsCalls++; }
- (void)updateStatusText:(id)sender { self.updateStatusTextCalls++; [super updateStatusText:sender]; }
- (void)updateFilterString:(NSString*)aString { self.updateFilterStringCalls++; [super updateFilterString:aString]; }
@end
