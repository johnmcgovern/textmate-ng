// The two synthetic file-browser locations, as ObjC++ globals.
//
// They were `extern NSURL* const` on FileItem.h, defined in FileItem.mm. Swift
// cannot *export* a global (rule 19), so they move here and stay ObjC++ once
// FileItem itself is Swift. FileItem.h re-imports this so its consumers are
// unchanged, and the Swift bridging header imports it so FileItem.swift can
// *read* kURLLocationComputer (reading a global is allowed; only exporting is not).
#import <Foundation/Foundation.h>

extern NSURL* const kURLLocationComputer;
extern NSURL* const kURLLocationFavorites;
