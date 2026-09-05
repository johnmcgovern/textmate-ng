// Hand-declared (rule 23): this class is defined in AppController.swift, with
// its menu and document halves in AppControllerMenus.swift and
// AppControllerDocuments.swift.
//
// It must not appear in TextMate-Bridging-Header.h, where it would collide with
// the generated TextMate-Swift.h (rule 43). Two consumers import it:
// `AppController Commands.mm`, which compiles a category onto the class, and
// the test bundle's TextMateTesting.h.
//
// Deliberately minimal. The old header declared eleven IBActions as well; none
// of them was ever *called* from ObjC — the menu reaches them by selector, and
// the tests assert on them through +instancesRespondToSelector: by name (rule
// 18). Nothing checks a hand declaration against the Swift at build time, so a
// method listed here that no ObjC consumer needs is only somewhere for the two
// to drift apart.
//
// <NSMenuDelegate> is declared because the class assigns itself as the delegate
// of the four dynamic submenus; the Swift adopts NSApplicationDelegate too, but
// no ObjC consumer needs to see that.
@interface AppController : NSObject <NSMenuDelegate>

// Was +initialize; -applicationWillFinishLaunching: calls it now (rule 24), and
// t_app_controller.mm calls it directly to test the migration it performs.
+ (void)setupThemeDefaultsAndObservers;

@end
