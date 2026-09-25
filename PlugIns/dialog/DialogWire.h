// The wire between tm_dialog2 and the Dialog2 plug-in.
//
// **This replaced Distributed Objects on 2026-09-24.** The plug-in used to
// register `com.macromates.dialog.<pid>` and vend itself as the root object, so
// any process running as the same user could look that name up and send the
// object a request. A request names the files the plug-in should use for the
// command's stdin, stdout and stderr — so a process that was not tm_dialog2
// could name a file of the user's as "stdout" and have the editor overwrite it.
// Proved before the change: a small program that is not tm_dialog2 named a file
// and its contents were replaced. `NSConnection` has been deprecated since 10.13
// for this class of reason.
//
// What the two sides need is one request, client → server: a dictionary of the
// three fifo paths, the working directory, the environment and the arguments.
// The reply is not on this channel at all — the command's output flows back over
// the fifos the request names. So this is a socket the client connects to, writes
// one request to, and closes; the server reads it and dispatches.
//
// The socket lives at a path derived from the plug-in's pid, mode 0600, so
// another user on the machine cannot connect — which the Distributed Objects name
// could not express. Same shape and framing as CommitWindow's CWWire: a 4-byte
// big-endian length, then that many bytes of binary property list. Declared here,
// compiled into both sides, so the framing cannot drift.

#ifndef DIALOG_WIRE_H_
#define DIALOG_WIRE_H_

#import <Foundation/Foundation.h>

// Where the plug-in listens, given the pid it runs under. tm_dialog2 is told the
// exact path in DIALOG_PORT_NAME (set by the plug-in), and uses that; this is the
// single definition of how the path is built.
NSString* DialogSocketPathForServerPID(pid_t pid);

// Write `request` to `fd`, length-prefixed. NO if the peer went away.
BOOL DialogWriteRequest(int fd, NSDictionary* request);

// Read one length-prefixed request from `fd`. nil if the peer closed first or
// sent something that is not a dictionary of property-list types.
NSDictionary* DialogReadRequest(int fd);

#endif /* DIALOG_WIRE_H_ */
