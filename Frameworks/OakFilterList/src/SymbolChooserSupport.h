@class OakDocument;

// Extracted from SymbolChooser.mm ahead of porting that class to Swift. Everything the
// panel does that touches C++ lives here, behind an API with none in it:
//
//   - the symbol walk itself, which Swift cannot reach at all — -[OakDocument
//     enumerateSymbolsUsingBlock:] hands its block a `text::pos_t const&`, and a C++ type
//     in a *block* parameter makes the whole method uncallable from Swift (rule 15);
//   - the filter ranking (oak::normalize_filter / oak::rank into a std::multimap);
//   - CreateAttributedStringWithMarkedUpRanges, over the ranked ranges (rule 19);
//   - matching a caret position against the symbol list, which compares text::pos_t
//     through a text::selection_t parse.
//
// SymbolChooserItem stays an ObjC class rather than becoming a Swift struct because it is
// what the table view binds to: OakChooser's row builder asks it for "name" by key, and
// -objectForKey: is what makes that work.
@interface SymbolChooserItem : NSObject
@property (nonatomic) NSString* path;
@property (nonatomic) NSString* identifier;
@property (nonatomic) NSString* selectionString;
@property (nonatomic) NSAttributedString* name;
@property (nonatomic) NSString* infoString;
- (id)objectForKey:(id)key;
@end

@interface SymbolChooserSupport : NSObject
// The items for a document, filtered and ranked. An empty or nil filter yields every
// symbol in document order; otherwise the ranked matches, best first. Nil document, no
// items.
+ (NSArray<SymbolChooserItem*>*)itemsForDocument:(OakDocument*)document filterString:(NSString*)filterString;

// The row to select for a caret position: the last item at or before the selection's
// last range. NSNotFound when nothing matches, including for empty input.
+ (NSUInteger)indexOfItemForSelectionString:(NSString*)selectionString inItems:(NSArray<SymbolChooserItem*>*)items;
@end
