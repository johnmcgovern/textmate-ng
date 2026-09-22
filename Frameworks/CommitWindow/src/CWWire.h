// The wire between CommitWindowTool and the application.
//
// **This replaced Distributed Objects on 2026-09-22.** Both sides used to vend
// an object: the application registered `<bundleid>.CommitWindow.<pid>` and set
// itself as the root object, and the tool did the same so the reply had
// somewhere to go. Any process running as the same user could look either name
// up and send messages to the vended object — Distributed Objects dispatches
// whatever selector arrives and deserialises whatever object graph comes with
// it. `NSConnection` has been deprecated since 10.13 for exactly these reasons.
//
// What the two sides actually needed was one request and one reply, both
// plist-serialisable. That is a socket, and the application already runs one for
// `mate`. So: the tool connects, sends a request, blocks reading the reply, and
// exits. Nothing is vended, no selector arrives from outside, and the reply
// channel is the same connection rather than a second service.
//
// The socket lives at a path derived from the application's pid, mode 0600, so
// another user on the machine cannot connect to it — which the Distributed
// Objects name could not express at all. Under Distributed Objects the only
// protection was that the name was hard to guess, and it was not: it was the
// bundle identifier and a pid.
//
// **Framing**: a 4-byte big-endian length, then that many bytes of binary
// property list. Declared here rather than in either side so the two cannot
// drift — a wire format described in two places is a wire format with two
// meanings.

#ifndef CW_WIRE_H_
#define CW_WIRE_H_

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Where the application listens, given the pid it is running under. The tool
// learns that pid from TM_PID, which the application already puts in every
// command's environment — the same value the Distributed Objects name used.
NSString* CWSocketPathForApplicationPID(pid_t pid);

// Write `plist` to `fd`, length-prefixed. NO if the peer went away.
BOOL CWWritePlist(int fd, NSDictionary* plist);

// Read one length-prefixed plist from `fd`. nil if the peer closed first, which
// is how the tool learns the application quit without answering.
NSDictionary* _Nullable CWReadPlist(int fd);

NS_ASSUME_NONNULL_END

#endif /* CW_WIRE_H_ */
