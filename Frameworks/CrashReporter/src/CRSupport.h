// The one thing in CrashReporter that Swift cannot reach (Phase 4).
//
// Not exported — this is for the framework's own Swift, through the bridging
// header.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// gzip `data` to `path`. NO on failure, having logged why.
//
// zlib has no module map on Darwin, so `gzopen` and friends are simply not in
// scope for Swift — the same shape of problem as <CarbonCore/Files.h>'s
// kOnSystemDisk in TMFileReference. Foundation's -compressedDataUsingAlgorithm:
// is NOT a substitute: it produces a raw deflate stream, where the collector is
// handed a `.gz` and expects the gzip container.
BOOL CRWriteGZipFile (NSData* data, NSString* path);

NS_ASSUME_NONNULL_END
