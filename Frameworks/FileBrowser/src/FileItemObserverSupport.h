// The one C++ fragment of the file-system observer, kept in ObjC++ so the rest
// of FileItemObserver can be Swift.
//
// When the SCM status of a watched directory changes, this reports the files in
// that directory that git now considers deleted — walking SCMRepository's status
// (a std::map<std::string, scm::status::type> reached through SCMStatus.rawStatus (SCMSupportCxx.h)),
// matching scm::status::deleted, and keeping only entries whose parent is the
// directory. Real C++ (rule 6); the Swift FileSystemObserver calls it. The
// signature is C++-free, so the bridging header can import this.
#import <Foundation/Foundation.h>

// SCMRepository is Swift-defined (SCMManager.swift); a forward declaration keeps
// this header bridging-header-safe (importing the hand-written SCMManager.h would
// collide with FileBrowser-Swift.h). The .mm imports SCMManager.h for the full type.
@class SCMRepository;

@interface FileItemObserverSupport : NSObject
+ (NSArray<NSURL*>*)deletedURLsInRepository:(SCMRepository*)repository forDirectoryURL:(NSURL*)url;
@end
