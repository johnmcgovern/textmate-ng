// The command environment, boxed so it can cross into Swift.
//
// Rule 20: `std::map<std::string, std::string>` was an *ivar* of
// OakHTMLOutputView, and a Swift class cannot hold one — nor can a category add
// storage to make up for it. So the map moves into an object the Swift side holds
// by reference and reads through an ObjC-clean accessor.
//
// The two C++ methods below are deliberately in this header rather than a
// separate one. The Swift importer parses it under SWIFT_OBJC_INTEROP_MODE=objcxx
// and simply omits members it cannot represent — the same thing that already
// happens to -loadRequest:environment:autoScrolls: in HTMLOutput.h, and
// documented there. Swift sees -valueForVariable: and nothing else.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface HOEnvironment : NSObject

// nil when the variable is unset. The only lookup any caller needs is
// TM_PROJECT_UUID, which txmt:// links carry through.
- (nullable NSString*)valueForVariable:(NSString*)name;

// ObjC++ only.
+ (instancetype)environmentWithCxxMap:(std::map<std::string, std::string> const&)map;
- (std::map<std::string, std::string> const&)cxxMap;

@end

NS_ASSUME_NONNULL_END
