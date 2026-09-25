// The wire between the 1.x tm_dialog tool and the 1.x Dialog plug-in.
//
// **This replaced Distributed Objects on 2026-09-24**, the same move the 2.x
// plug-in and the commit window made. The plug-in registered
// `com.macromates.dialog_1.<pid>` and vended itself as the root object, so any
// process running as the user could look that name up and drive it — showing
// dialogs, menus and nib windows, and naming the files those read and write. The
// name (a constant and a pid) was the only barrier.
//
// Unlike the 2.x plug-in, this protocol is a small RPC: the tool calls a method
// and gets a result back (showNib:, showMenuWithOptions:, showAlertForPath:, the
// async token methods, and the version handshake). So this carries a request AND
// a reply, one round trip per call:
//
//   request = { "method": <selector name>, "arguments": [ … ] }
//   reply   = { "result":  <property-list value, or absent for nil> }
//
// nil arguments travel as NSNull and BOOLs as NSNumber. Framing is CWWire's: a
// 4-byte big-endian length, then that many bytes of binary property list.
//
// The socket lives at a path derived from the plug-in's pid, mode 0600, so
// another user cannot connect. The async wait is unchanged and independent of
// this: the tool blocks on a POSIX named semaphore the plug-in posts to.

#ifndef DIALOG1_WIRE_H_
#define DIALOG1_WIRE_H_

#import <Foundation/Foundation.h>

NSString* Dialog1SocketPathForServerPID(pid_t pid);

// Write one length-prefixed dictionary (request or reply). NO if the peer went
// away.
BOOL Dialog1WriteMessage(int fd, NSDictionary* message);

// Read one length-prefixed dictionary. nil if the peer closed first or sent
// something that is not a dictionary of property-list types.
NSDictionary* Dialog1ReadMessage(int fd);

#endif /* DIALOG1_WIRE_H_ */
