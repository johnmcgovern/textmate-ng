#ifndef OAK_LOG_H_JCP4Q2
#define OAK_LOG_H_JCP4Q2

#include <os/log.h>

// One logging subsystem for the whole app, so that
//
//     /usr/bin/log show --predicate 'subsystem == "com.j23software.TextMate"'
//     /usr/bin/log stream --predicate 'subsystem == "com.j23software.TextMate"'
//
// finds everything the app emits, and a category narrows it to one area. Declare
// a file-static logger per area next to the code that uses it:
//
//     static os_log_t const kLogCommitWindow = os_log_create(OAK_LOG_SUBSYSTEM, "commit-window");
//
// Adoption is incremental. Most of the tree still calls
// `os_log_error(OS_LOG_DEFAULT, …)`, which works but carries no subsystem, so it
// can only be filtered by process. One older site still invents a subsystem of
// its own ("Pasteboard") that is not reverse-DNS and does not group with
// anything; it should move here when it is touched, as "KEventManager" did in
// its 2026-08-02 Swift port.
//
// The Swift spelling of the same thing, since there is no os_log_create there:
//
//     private let log = Logger(subsystem: "com.j23software.TextMate", category: "kevent-manager")
//
// with one catch — Logger interpolations are **private by default**, so every
// value that was %{public}@ in ObjC needs an explicit `privacy: .public` or the
// log fills with <private>.
//
// NOTE on reading these logs from a zsh prompt: **zsh has a `log` builtin** that
// shadows /usr/bin/log, and it fails with "too many arguments" rather than
// anything that looks like a PATH problem. Always spell it `/usr/bin/log`. An
// afternoon was lost in 2026-07-29 concluding the app "logged nothing" because
// of this, with stderr redirected so the error was invisible.
//
// Levels, since they decide what survives to be read later: `os_log_error` and
// `os_log` (default) are persisted to the log store and show up in `log show`.
// `os_log_info` and `os_log_debug` are memory-only and need `--info` / `--debug`
// on the command line, so they are not useful for after-the-fact diagnosis.
#define OAK_LOG_SUBSYSTEM "com.j23software.TextMate"

#endif /* include guard */
