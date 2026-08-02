// The @objc helpers on the Swift CrashReporter that these tests drive.
//
// In its own header because ide/gen_xctest.rb wraps each test file's body in
// `namespace <basename>`, and ObjC declarations may only appear at global
// scope — but every #import is hoisted, so anything reached through one is fine.
//
// Nothing checks these against the Swift at build time; that is exactly what
// the tests importing this are for.
#import <CrashReporter/CrashReporter.h>

// Class methods: none of them touches instance state, and a test cannot
// construct CrashReporter at all — -init installs the UNUserNotificationCenter
// delegate, and +currentNotificationCenter raises in a process that is not a
// bundled app, which the xctest runner is not.
@interface CrashReporter (Testing)
+ (NSArray<NSString*>*)reportsForProcessName:(NSString*)processName notBefore:(NSDate*)cutOff in:(NSString*)directory;
+ (NSData*)dataForURLRequest:(NSMutableURLRequest*)request withFormValues:(NSDictionary<NSString*, NSString*>*)payload;
+ (NSString*)pathForGZipCompressedFileAtPath:(NSString*)path;
@end
