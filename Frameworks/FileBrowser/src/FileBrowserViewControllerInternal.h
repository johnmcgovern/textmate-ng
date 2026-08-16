// The private surface of FileBrowserViewController that a *peeled-off* Swift
// section needs to reach.
//
// The controller keeps its real private state in a class extension inside
// FileBrowserViewController.mm, which Swift cannot see. As sections of the
// class move out into Swift extensions ahead of the port (the shape
// FileBrowserDiskOperations established), each one may need a property that
// lives there. Rather than widen the public header — those properties are not
// API, and nothing outside this framework should reach them — they are
// re-declared here, **readonly**, and this header goes in the bridging header.
//
// Readonly is the point, not an accident: the class extension keeps the
// readwrite declaration, so a peeled section can read this state but cannot
// start writing it from Swift, which would move behaviour rather than move
// code. Redeclaring a class-extension property as readonly in a category is
// accepted by clang with no diagnostic (checked, not assumed).
//
// **This header is temporary.** Every property on it exists because the class
// is still ObjC++; when the class itself becomes Swift, the class extension and
// this file both go away and the properties become ordinary private state
// again. If it is still here after the port, something was missed.
#import "FileBrowserViewController.h"

// **Do not add protocol conformances here.** Re-stating one that the class
// extension already declares is legal ObjC, but it makes the conformance
// *visible to Swift*, and then a peeled section implementing one of the
// protocol's optional methods fails to compile: the imported protocol member
// counts as a previous declaration of that selector
// ("method 'control(_:textShouldEndEditing:)' … conflicts with previous
// declaration"). The data source section only works because its
// NSOutlineViewDataSource conformance stays invisible in the .mm.
//
// Where a peeled section needs Swift to know about a conformance — because it
// assigns `self` to a delegate property — the Swift extension declares that
// conformance itself, as FileBrowserTableCells.swift does for NSTextFieldDelegate.
@interface FileBrowserViewController (Internal)

// Read by the NSOutlineViewDataSource section (-outlineView:isItemExpandable:).
// Both are driven from FileBrowserView and written only by their custom setters
// in the controller, which reload the outline view.
@property (nonatomic, readonly) BOOL canExpandPackages;
@property (nonatomic, readonly) BOOL canExpandSymbolicLinks;

// What the action methods operate on. selectedItems is the selection, or the
// right-clicked row when that row is outside the selection; previewableItems is
// the subset with a preview URL. Both are already readonly on the class
// extension, so this re-declaration costs nothing.
// nonnull, deliberately: both build and return an array unconditionally, and
// without the annotation Swift sees `[FileItem]?` and every call site grows an
// unwrap that means nothing.
@property (nonatomic, readonly, nonnull) NSArray<FileItem*>* selectedItems;
@property (nonatomic, readonly, nonnull) NSArray<FileItem*>* previewableItems;

// -validateMenuItem: reads both: showExcludedItems to title the Show/Hide
// Invisible Files item, and activeUndoManager for the undo/redo titles and
// their enabled state. Both are still ObjC++ below.
@property (nonatomic, readonly) BOOL showExcludedItems;
@property (nonatomic, readonly, nullable) NSUndoManager* activeUndoManager;

// Opens items in the editor — the shared tail of double-click, the Open action
// and the cell's open button. Defined in the .mm with no declaration at all
// (it is called only from below its definition), so it needs one here for the
// table-cell section to reach it. Three of its four callers are still ObjC++.
//
// NS_SWIFT_NAME is not decoration: the importer renames this to `open(_:animate:)`
// on its own (rule 28 — it drops the "Items" and leaves a name that collides
// with every other `open` in scope). Pinning it keeps the Swift call site saying
// what the ObjC selector says.
- (void)openItems:(NSArray<FileItem*>*)items animate:(BOOL)animateFlag NS_SWIFT_NAME(openItems(_:animate:));

// Reached by -validateMenuItem:, which is Swift, while these four are still
// ObjC++ — the reverse of the usual direction. Safe to declare here precisely
// because ObjC still *implements* them: the rule this header must not break is
// declaring something Swift defines.
- (void)undo:(id)sender;
- (void)redo:(id)sender;
- (void)openWithMenuAction:(id)sender;

// **The one readwrite property here, and it is deliberate.** The Quick Look
// section owns this state — the ObjC++ set it in -beginPreviewPanelControl:,
// cleared it in -endPreviewPanelControl: and refreshed it on an arrow key — and
// that section is now Swift. Moving those writes is faithful; the readonly
// convention exists to stop a peeled section *starting* to write state it only
// read, which is not what this is. -previewableItems, which computes the value,
// stays in the .mm as the accessor of a declared property.
@property (nonatomic, nullable) NSArray<FileItem*>* previewItems;

// Expands the first set of URLs and selects the second, once the tree has
// loaded far enough to contain them. Used by the reveal actions.
// Pinned for the same reason as -openItems:animate: — the importer renames this
// to `expand(_:select:)`, which says less than the selector does (rule 28).
- (void)expandURLs:(NSArray<NSURL*>*)expandURLs selectURLs:(NSArray<NSURL*>*)selectURLs NS_SWIFT_NAME(expandURLs(_:selectURLs:));

@end
