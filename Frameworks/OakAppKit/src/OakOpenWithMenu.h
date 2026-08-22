// Hand-declared (rule 23): both classes are defined in OakOpenWithMenu.swift.
//
// Unchanged from when this was the real header — the surface was always C++-free.
// FileBrowser's bridging header imports it (its Swift holds an
// OakOpenWithMenuDelegate) as does FileBrowserViewControllerCxx.mm, and it must
// not appear in OakAppKit's own bridging header (rule 43). It does not.
//
// The three `getter =` spellings below are the contract rule 4 is about: they are
// what -menuNeedsUpdate: calls, while the property names are what -applications
// sorts on. The Swift keeps both with per-accessor @objc(…).
@interface OakOpenWithApplicationInfo : NSObject
@property (nonatomic, readonly) NSURL* URL;
@property (nonatomic, readonly) NSString* bundleIdentifier;
@property (nonatomic, readonly) NSString* name;
@property (nonatomic, readonly) NSString* version;
@property (nonatomic, readonly) NSString* displayName;

@property (nonatomic, readonly, getter = isDefaultApplication) BOOL defaultApplication;
@property (nonatomic, readonly, getter = hasMultipleVersions)  BOOL multipleVersions;
@property (nonatomic, readonly, getter = hasMultipleCopies)    BOOL multipleCopies;
@end

@interface OakOpenWithMenuDelegate : NSObject <NSMenuDelegate>
- (instancetype)initWithDocumentURLs:(NSArray<NSURL*>*)someDocumentURLs;
- (void)openDocumentURLs:(NSArray<NSURL*>*)documentURLs withApplicationURL:(NSURL*)applicationURL;
@property (nonatomic, readonly) NSArray<NSURL*>* documentURLs;
@property (nonatomic, readonly) NSArray<OakOpenWithApplicationInfo*>* applications;
@end
