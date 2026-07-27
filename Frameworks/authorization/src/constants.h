#ifndef AUTH_CONSTANTS_H_7R7B65WN
#define AUTH_CONSTANTS_H_7R7B65WN

// Renamed off com.macromates.* 2026-07-26 with the CFBundleIdentifier move. These
// are not merely cosmetic: they name *system-wide* artifacts — a LaunchDaemon, a
// privileged helper in /Library/PrivilegedHelperTools, a socket in /var/run, and an
// Authorization right. Shipping a public build that still claimed MacroMates' names
// would have TextMate-NG and a real TextMate install overwrite each other's daemon
// and fight over one socket.
//
// Consequence: a machine that already installed the old helper keeps an orphaned
// com.macromates.auth_server daemon + plist. Nothing removes it — worth an
// uninstall note whenever this helper is next touched (it is already due an
// SMAppService rewrite; see NOTARIZATION_HANDOFF.md).
#define kAuthJobName     "com.j23software.auth_server"
#define kAuthToolPath    "/Library/PrivilegedHelperTools/com.j23software.auth_server"
#define kAuthSocketPath  "/var/run/com.j23software.auth_server.sock"
#define kAuthPlistPath   "/Library/LaunchDaemons/com.j23software.auth_server.plist"
#define kAuthRightName   "com.j23software.textmate.openfile"
#define kAuthServerMajor 3
#define kAuthServerMinor 1

#endif /* end of include guard: AUTH_CONSTANTS_H_7R7B65WN */
