#include <string>
#include <vector>
#include <utility>

// Extracted from OakChooser.mm ahead of porting OakChooser to Swift. Builds the
// name/folder attributed strings the choosers display, highlighting the character
// ranges a C++ ranker matched. Because it takes std::string and
// std::vector<std::pair<size_t, size_t>> it can't be a Swift function (rule 19), so it
// stays ObjC++ and the three choosers — SymbolChooser, FileChooser, BundleItemChooser,
// all still ObjC++ — call it directly. Declared here rather than in OakChooser.h, which
// becomes the Swift class's hand-declaration. Consumers include it after their prelude,
// which supplies <Cocoa/Cocoa.h> for NSLineBreakMode / NSMutableAttributedString.
NSMutableAttributedString* CreateAttributedStringWithMarkedUpRanges (std::string const& in, std::vector< std::pair<size_t, size_t> > const& ranges, NSLineBreakMode lineBreakMode = NSLineBreakByTruncatingMiddle);
