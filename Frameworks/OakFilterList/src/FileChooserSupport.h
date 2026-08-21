// The rest of FileChooser's C++, extracted ahead of porting the panel to Swift; the row
// model went first, into FileChooserItem. Four unrelated things end up here because they
// have one thing in common — each is a small piece of C++ the controller cannot carry:
// the settings-driven search globs, the scm::info handle (a shared_ptr ivar, rule 20), the
// filter mini-syntax (whose normalisation is oak::normalize_filter), and two path helpers
// whose exact semantics are path::, not NSString's.
//
// This header has no C++ in it, so the Swift bridging header can import it.

// The parsed form of what the user typed. The panel's filter field accepts
// "glob*", "name", "name:selection" and "name@symbol"; the original parsed all four out
// with one regular expression and then compared old against new to decide whether to
// re-filter. Pure logic, and pinned as such in t_file_chooser_support.mm.
@interface FileChooserFilter : NSObject
+ (instancetype)filterWithString:(NSString*)string;

@property (nonatomic, readonly) NSString* globString;      // non-nil only when it contains *
@property (nonatomic, readonly) NSString* filterString;    // normalised (oak::normalize_filter)
@property (nonatomic, readonly) NSString* selectionString; // after ':'
@property (nonatomic, readonly) NSString* symbolString;    // after '@'

// globString ?: filterString ?: @"" — what the original compared to decide whether the
// filter had meaningfully changed.
@property (nonatomic, readonly) NSString* effectiveFilter;
@end

// A live scm::info_ptr for one working copy: created only when there is one, reports the
// paths with uncommitted changes, and forwards status updates to a block. The panel holds
// it as an opaque object and drops it by setting the reference to nil, which is what
// _scmInfo.reset() did.
@interface FileChooserSCMInfo : NSObject
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

// scm::info(path); nil when the path is not in a working copy.
+ (instancetype)infoForPath:(NSString*)path;

// The paths whose status is modified, added, deleted or conflicted.
- (NSArray<NSString*>*)uncommittedPaths;

// scm::info_t::push_callback — invoked when the working copy's status changes. The block is
// held for the lifetime of this object.
- (void)addStatusCallback:(void(^)(void))block;
@end

@interface FileChooserSupport : NSObject
// The OakDocumentController search options for a path: the include/exclude globs the
// settings define for the file chooser, plus symbolic-link following and unordered results.
+ (NSDictionary*)searchOptionsForPath:(NSString*)path;

// path::relative_to — not NSString's path arithmetic, which differs for the cases that
// matter here (a path outside the base, an empty base).
+ (NSString*)path:(NSString*)path relativeTo:(NSString*)base;

// Whether the path has a parent other than itself — path::parent, which stops at "/".
+ (BOOL)pathHasParent:(NSString*)path;
@end
