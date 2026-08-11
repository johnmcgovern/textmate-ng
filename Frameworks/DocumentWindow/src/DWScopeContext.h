// The SCM and scope-attribute state of a project window, in a form that crosses
// the ObjC boundary.
//
// This exists so DocumentWindowController can become Swift. That class held
// seven C++ ivars — two of them `scm::info_ptr`, which is a std::shared_ptr with
// a live callback that fires on version-control changes — and a Swift @objc
// class cannot hold those. It is not a value to convert at a boundary the way
// text::range_t was in Find; it is C++ state whose lifetime is tied to the
// object.
//
// That is the `bundles::item_ptr` blocker recurring, and the answer is the one
// TMBundleModel already established: an ObjC-shaped model layer, so the problem
// is solved once rather than argued about per framework. This header is
// deliberately free of C++ so a Swift bridging header can import it;
// DWScopeContextCxx.h carries the C++ accessors for the ObjC++ shims that still
// need std::map.
//
// SCOPE, following TMBundleItem's discipline: only what DocumentWindowController
// actually touches. Deliberately absent are scm::info_t's status(), root_path()
// and tracks_directories() — the file browser has its own path to those, and
// they arrive here if and when a consumer needs them.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWScopeContext : NSObject

// Fired on the main thread whenever the SCM variables change — either because a
// path was set or because the repository moved underneath. The window title is
// the only thing that reacts today.
//
// Weakly held expectations: this block is retained, so a controller assigning it
// must capture itself weakly.
@property (nonatomic, copy, nullable) void (^variablesDidChange)(void);

// ==========================================
// = Paths in, attributes and variables out =
// ==========================================

// Setting the project path starts (or stops) watching that directory's
// repository and recomputes the project's custom scope attributes. Idempotent:
// setting the same path again does nothing.
@property (nonatomic, copy, nullable) NSString* projectPath;

// The document path and its file type travel together because the settings
// lookup that produces the custom attributes needs both. `fileType` may be nil
// for a window with no selected document, which suppresses that lookup exactly
// as the ObjC++ did.
//
// Unlike -setProjectPath: this is *not* fully idempotent, and deliberately so:
// it also re-runs when the attribute list is empty, which is how a window that
// starts with no document picks them up once it has one.
- (void)setDocumentPath:(nullable NSString*)documentPath fileType:(nullable NSString*)fileType;

// The async directory walk that produces attr.scm.git, attr.project.ninja and
// the rest by looking for marker files from the document up to the project root.
// Results land on the main thread, and are discarded if either path changed
// while it ran.
- (void)updateExternalAttributesForDocumentPath:(nullable NSString*)documentPath;

// ==========================================
// = What consumers read                    =
// ==========================================

// **The rule that was written out five times in the ObjC++**: the document's SCM
// variables if it has any, otherwise the project's. Encapsulating it is most of
// the point of this class.
@property (nonatomic, readonly) NSDictionary<NSString*, NSString*>* effectiveSCMVariables;

// attr.scm.git and friends, from the directory walk above.
@property (nonatomic, readonly) NSArray<NSString*>* externalScopeAttributes;

// The space-joined attribute string OakTextView asks its delegate for: the SCM
// name and branch, the document's status, and the three attribute lists merged
// and de-duplicated. `scmStatusAttribute` is the `attr.scm.status.…` fragment
// the caller derives from the selected document, or nil when it has none —
// converting scm::status::type to a string is TMSCMStatus's job, not this
// class's.
- (NSString*)scopeAttributesWithSCMStatusAttribute:(nullable NSString*)scmStatusAttribute;

// TM_SCM_NAME for the command environment: taken from the SCM variables when
// there are any, and otherwise recovered from an `attr.scm.<name>` external
// attribute. Empty when neither yields one.
@property (nonatomic, readonly) NSDictionary<NSString*, NSString*>* scmNameVariables;

@end

NS_ASSUME_NONNULL_END
