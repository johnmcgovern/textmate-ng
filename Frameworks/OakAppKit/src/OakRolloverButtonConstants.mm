#import "OakRolloverButtonConstants.h"

// Definitions moved verbatim from OakRolloverButton.mm (rule 6). The string
// values are the pin: t_rollover_button.mm asserts them, because Swift renames
// the symbol on import and a port can keep every call site compiling while
// changing the value underneath and silently unsubscribing every observer.
NSNotificationName const OakRolloverButtonMouseDidEnterNotification = @"OakRolloverButtonMouseDidEnterNotification";
NSNotificationName const OakRolloverButtonMouseDidLeaveNotification = @"OakRolloverButtonMouseDidLeaveNotification";
