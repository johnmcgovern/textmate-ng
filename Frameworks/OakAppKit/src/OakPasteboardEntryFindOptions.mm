#import "OakPasteboardEntryFindOptions.h"

// Moved verbatim from OakPasteboard.mm (rule 6): the same OR of the entry's boolean
// flags and the two find defaults into a find::options_t.

@implementation OakPasteboardEntry (FindOptions)
- (find::options_t)findOptions
{
	return find::options_t(
		([self fullWordMatch]       ? find::full_words         : find::none) |
		([NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsFindIgnoreCase] ? find::ignore_case : find::none) |
		([NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsFindWrapAround] ? find::wrap_around : find::none) |
		([self ignoreWhitespace]    ? find::ignore_whitespace  : find::none) |
		([self regularExpression]   ? find::regular_expression : find::none));
}
@end
