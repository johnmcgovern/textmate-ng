// The two notification names OakRolloverButton posts when the pointer crosses it.
//
// They stayed in ObjC because Swift cannot export an `extern` constant (rule 19),
// and they are in a header of their own because OakAppKit's *own* Swift needs
// them while OakRolloverButton.h — the hand declaration of a class that is now
// defined in Swift (rule 23) — must stay out of this framework's bridging header
// (rule 43). Same split, and the same reason, as OakPasteboardConstants.h.
//
// Swift drops the `Notification` suffix on import (rule 28), so these are spelled
// `.OakRolloverButtonMouseDidEnter` / `.OakRolloverButtonMouseDidLeave` there.
extern NSNotificationName const OakRolloverButtonMouseDidEnterNotification;
extern NSNotificationName const OakRolloverButtonMouseDidLeaveNotification;
