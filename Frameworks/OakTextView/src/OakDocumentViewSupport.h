// The C++ boundary for OakDocumentView: settings writes, bundle queries, and the
// theme's gutter colours.
//
// Three separate reasons the calls behind this cannot be made from Swift:
//
//   * settings_t::set takes std::string const& (rule 17);
//   * bundles::lookup/query deal in std::shared_ptr<bundles::item_t>, and
//     -[OakTextView performBundleItem:] takes one as a parameter, so even the
//     hand-off cannot be spelled in Swift;
//   * -[OakTextView theme] is a *property* whose type is theme_ptr. Swift cannot
//     read it at all, so every use of the theme has to be answered here.
//
// The bundle query deliberately returns *every* bundle rather than the ones that
// end up in the menu. -showBundleItemSelector:'s "No Bundles Loaded" fallback is
// guarded on the unfiltered list while the menu is built from a filtered one, and
// t_document_view.mm pins the resulting blank-menu bug. Keeping the filter at the
// call site keeps that visible where a fix would belong.
#import <Cocoa/Cocoa.h>

@class OakTextView;

NS_ASSUME_NONNULL_BEGIN

// One bundle's row in the bundle-items pop-up, and the three facts the call site
// needs to decide whether to draw it.
@interface OakBundleMenuEntry : NSObject
@property (nonatomic, readonly) NSString* name;
@property (nonatomic, readonly) NSString* uuidString;
// YES when this bundle supplies a grammar matching the document's file type.
@property (nonatomic, readonly) BOOL selectedGrammar;
@property (nonatomic, readonly) BOOL hiddenFromUser;
@property (nonatomic, readonly) BOOL hasMenu;
@end

// The gutter half of a theme, as AppKit colours. Every member is one CGColorRef
// from theme_t::gutter_styles(), converted once.
@interface OakGutterStyles : NSObject
@property (nonatomic, readonly) NSColor* documentBackground; // theme->background(fileType)
@property (nonatomic, readonly) BOOL isDark;

@property (nonatomic, readonly) NSColor* divider;
@property (nonatomic, readonly) NSColor* foreground;
@property (nonatomic, readonly) NSColor* background;
@property (nonatomic, readonly) NSColor* icons;
@property (nonatomic, readonly) NSColor* iconsHover;
@property (nonatomic, readonly) NSColor* iconsPressed;
@property (nonatomic, readonly) NSColor* selectionForeground;
@property (nonatomic, readonly) NSColor* selectionBackground;
@property (nonatomic, readonly) NSColor* selectionIcons;
@property (nonatomic, readonly) NSColor* selectionIconsHover;
@property (nonatomic, readonly) NSColor* selectionIconsPressed;
@property (nonatomic, readonly) NSColor* selectionBorder;
@end

@interface OakDocumentViewSupport : NSObject

// ===========
// = Settings =
// ===========

// nil means NULL_STR, which is how -changeFont: says "the default font" — the key
// is removed rather than set to the default's name.
+ (void)setFontName:(nullable NSString*)fontName;
+ (void)setFontSize:(CGFloat)fontSize;
+ (void)setTabSize:(NSUInteger)tabSize forFileType:(nullable NSString*)fileType;
+ (void)setSoftTabs:(BOOL)softTabs forFileType:(nullable NSString*)fileType;

// ===========
// = Bundles =
// ===========

// The grammar scope declared by the bundle item with this UUID, or nil if there is
// no such item or it declares none. -validateMenuItem: compares it to the
// document's file type to decide which grammar row is checked.
+ (nullable NSString*)grammarScopeForBundleItemWithUUIDString:(nullable NSString*)uuidString;

// Looks the item up and hands it to the text view. Silently does nothing when the
// UUID names no item, exactly as the `if(item_ptr item = lookup(...))` did.
+ (void)performBundleItemWithUUIDString:(nullable NSString*)uuidString inTextView:(OakTextView*)textView;

// Every bundle in the index, sorted by name with text::less_t — the same
// comparator and the same stability the std::multimap had.
+ (NSArray<OakBundleMenuEntry*>*)bundlesForMenuWithFileType:(nullable NSString*)fileType;

// =========
// = Theme =
// =========

// nil when the text view has no theme, which is the `if(theme_ptr theme = ...)`
// the ObjC++ opened -updateStyle with.
+ (nullable OakGutterStyles*)gutterStylesForTextView:(OakTextView*)textView fileType:(nullable NSString*)fileType;

@end

NS_ASSUME_NONNULL_END
