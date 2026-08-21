#import <TMBundleModel/TMScopeContext.h>

// Everything in BundleItemChooser that touches C++, extracted ahead of porting the panel
// to Swift. That is most of the file: the row model, the item gathering, and the ranking.
//
// The gathering is the reason this boundary is large rather than surgical. It reads the
// bundle index (bundles::query over a scope::context_t), the settings index
// (settings_info_for_path), the main menu, and the key-binding plists, and it builds every
// row from those — none of which Swift can reach. It stays here whole.
//
// `scope` crosses as a TMScopeContext, the existing C++-free box around scope::context_t
// (rule 17). Note its +currentScope falls back to the *empty* scope while this panel wants
// the *wildcard* — see the caller in AppController.mm, and t_bundle_item_chooser.mm.

// The searchable field, matching the panel's Search menu.
extern NSUInteger const kBundleItemTitleField;
extern NSUInteger const kBundleItemKeyEquivalentField;
extern NSUInteger const kBundleItemTabTriggerField;
extern NSUInteger const kBundleItemSemanticClassField;
extern NSUInteger const kBundleItemScopeSelectorField;

// A bitmask of where rows come from, matching the panel's three scope-bar sources.
extern NSUInteger const kSearchSourceActionItems;
extern NSUInteger const kSearchSourceSettingsItems;
extern NSUInteger const kSearchSourceGrammarItems;
extern NSUInteger const kSearchSourceThemeItems;
extern NSUInteger const kSearchSourceDragCommandItems;
extern NSUInteger const kSearchSourceMenuItems;
extern NSUInteger const kSearchSourceKeyBindingItems;

// One row. Stays ObjC because it is what the table binds to and what the cell view reads
// by key; its properties are already C++-free, so only the ranking had to move behind a
// class method.
@interface ActionItem : NSObject
@property (nonatomic, getter = isMatched) BOOL matched;
@property (nonatomic, readonly) double rank;

@property (nonatomic) NSImage* icon;
@property (nonatomic) NSAttributedString* name;
@property (nonatomic) NSAttributedString* path;
@property (nonatomic) NSString* keyEquivalent;
@property (nonatomic) NSString* tabTrigger;

@property (nonatomic) NSString* itemName;
@property (nonatomic) NSString* location;

@property (nonatomic) NSString* uuid; // Bundle item
@property (nonatomic) NSString* file; // Settings or key binding item
@property (nonatomic) NSString* line; // Line in settings file

@property (nonatomic) NSMenuItem* menuItem;
@property (nonatomic) SEL action;
@property (nonatomic) NSString* value; // Settings items and settings files
@property (nonatomic) NSString* scopeSelector;
@property (nonatomic) NSString* semanticClass;
@property (nonatomic) BOOL eclipsed; // Settings or key binding item
@end

@interface BundleItemChooserSupport : NSObject
// Every candidate row for a scope, before filtering. Expensive — the panel caches it and
// drops the cache when any of these inputs changes.
+ (NSArray<ActionItem*>*)unfilteredItemsForScope:(TMScopeContext*)scopeContext
                                    hasSelection:(BOOL)hasSelection
                                    searchSource:(NSUInteger)searchSource
                                 searchAllScopes:(BOOL)searchAllScopes
                                    documentPath:(NSString*)documentPath
                               documentDirectory:(NSString*)documentDirectory;

// Ranks `items` against the filter and returns the matched ones in display order. A batch
// call for the reason FileChooserItem's is: the original ranked concurrently with one
// normalised filter, and a per-item entry point would redo that work per row per keystroke.
+ (NSArray<ActionItem*>*)rankedItems:(NSArray<ActionItem*>*)items
                        filterString:(NSString*)filterString
                     bundleItemField:(NSUInteger)bundleItemField
                        searchSource:(NSUInteger)searchSource
                            bindings:(NSArray<NSString*>*)bindings;

// Whether the item can be opened (its bundle item is not a settings item), and the
// identifier -accept: learns an abbreviation against. Both reach bundles:: or the menu
// item, so neither can live in the controller.
// The row's 32pt icon. Bundle items are looked up by uuid to get their kind (which picks
// a BundleEditor image), menu items and settings files get their own, and a settings file
// inside the app bundle shows the app icon — all of it bundles:: or path:: work.
+ (NSImage*)iconForItem:(ActionItem*)item;

+ (BOOL)canAcceptItem:(ActionItem*)item;
+ (NSString*)abbreviationIdentifierForItem:(ActionItem*)item;
@end
