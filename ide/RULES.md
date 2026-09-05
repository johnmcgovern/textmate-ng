# The numbered rules — all 61, in one place

Earned across every port in this project — Find, DocumentWindowController,
OakAppKit, FileBrowser, OakFilterList. They live here, in one file, so a survey reads the whole
list rather than a third of it: rules 1–22 and 23–49 used to sit in two separate
handoffs while the documentation map pointed at one and called it "22 of them", so
a session that followed the map read a third of the list believing it had read all
of it.

**The numbering is stable and referenced by number throughout the handoffs**
("rule 18", "rules 15–21", "rule 49") — never renumber. Append the next rule at the
end. The port-by-port narrative that earned each rule stays in its own handoff
(`FIND_PORT_HANDOFF.md`, `FILEBROWSER_PORT_HANDOFF.md`); only the rule statements
were consolidated here, verbatim, on 2026-08-18. Rules 50–51 were added on
2026-08-20 from the OakFilterList port and are stated in full below, that handoff
being NEXT_SESSION_HANDOFF.md. Rules 52–56 followed from OakRolloverButton,
OakEncodingPopUpButton, OakOpenWithMenu, OakDocumentView and FavoriteChooser;
rules 57–59 were added on 2026-09-02 from the AppController pin and extractions,
rule 60 from the menu conversion the same day, and rule 61 from the free-function
probe that followed it.

(The count in the title has been wrong before — it said "51" while there were 56.
If you add a rule, fix it, and remember rule 10 applies to this file too.)

---

## Rules 1–22 — Find, DocumentWindowController, OakAppKit

1. **`@objc dynamic`** for anything ObjC observes. Grep for `bind:`,
   `addObserver:forKeyPath:`, `keyPathsForValuesAffecting`, `setValue:forKey:`.
2. **Spell out `@objc override init()`** when an ObjC caller uses `+new`/`-init`.
   Swift stops inheriting `-init` once another initializer exists.
3. **`&+`/`&-`** wherever the ObjC++ relied on `NSUInteger` wraparound.
4. **Annotate accessors, not the property**, for `getter=` — `@objc(isFoo) get`
   plus `@objc(setFoo:) set`.
5. **A C++ enum in a public header is an NS_OPTIONS decision**, not a port.
   Pin it with a `static_assert` *and* a test.
6. **Move C++ verbatim**, assembled from `git show`, never retyped; assert the
   old text is a substring of the new file.
7. **`const` at namespace scope has internal linkage in C++** — an exported
   constant needs its `extern` declaration in scope at the definition.
8. **Run the app.** `displayPath`, the excerpt builder and `lineSpan` have no
   test coverage and never will; they only execute in the running app.
9. **A negative grep result is not a finding.** When a survey answers "nothing
   found", check the pattern against a line you know should match before
   reporting it. `no C++ in any of its eight public headers` was published from a
   pattern that could not have matched `Find.h` — `#import <…>` rather than
   `#include <…>`, `text::` rather than `std::`.
10. **Measure, never subtract.** Both the suite total and Find's line count have
   been reported wrong in this project by arithmetic rather than by
   measurement — the suite twice in one session, and Find's remaining ObjC++
   twice more, each time because a ported file's C++ half was subtracted without
   adding back the support file it moved into. Re-run the command.
11. **Split a public header that declares both the class and its types.** A
   bridging header cannot import the declaration of a class Swift defines, so
   anything else in that header goes with it. Export both halves and cross-import
   them with a **quoted** include — the angle form cannot resolve a framework's
   own farm dir from inside that framework.
12. **Read the builder, not the DSL.** `MBMenuItem`'s defaults are not the
   obvious ones: a nil title yields a *separator*, `modifierFlags` defaults to
   Command, and a non-nil `.delegate` alone creates a submenu. Hand-rolling a
   menu from the call site alone gets the item count wrong.
13. **The last shipped build is an A/B oracle.** Before calling a behaviour
   difference a port defect, drive the previous release through the identical
   sequence. Check that the control run actually performed the action first —
   a control that silently did nothing agrees with any hypothesis.
14. **`@preconcurrency` on the conformance, not `nonisolated` on the method,**
   when a `@MainActor` class adopts a plain ObjC protocol whose delivery is
   main-thread by contract. State *why* it is main-thread — `OakObserveUserDefaults`
   registers with `queue: NSOperationQueue.mainQueue`, and that is checkable.

The next four are from DocumentWindowController (2026-08-12). The first three are
things a `grep` for `std::` in method signatures cannot find, and the fourth is
the one that actually shipped a broken feature.

15. **Survey block parameters, not just method parameters.** C++ in a *block*
   signature makes the whole method uncallable from Swift, not just the block —
   `-loadModalForWindow:completionHandler:` and `-saveModalForWindow:…` hand their
   block an `oak::uuid_t const&`, and that alone put the document-open path and
   all three save paths behind shims. Grep for `(^)` in any header the port
   touches, then read each block's parameter list.
16. **ObjC variadic methods cannot be called from Swift at all.** `-addButtons:`
   and `+tmAlertWithMessageText:informativeText:buttons:` have no C++ in them and
   no survey looking for C++ will find them. Grep for `, ...)` in the headers.
   **Confirmed by measurement 2026-09-04** (unlike rule 28's neighbouring claim,
   which was not): `alert.addButtons("A", "B", nil)` fails with *value of type
   'NSAlert' has no member 'addButtons'*.
   **But it is not a blocker, and no sibling API was added.** Both of these are
   loops over `-addButtonWithTitle:`, and six ported files already inline that
   loop — DocumentWindowController, OakHTMLOutputView, HOWebViewDelegateHelper,
   FileBrowserDiskOperations, TMPlugInController and command/runner.mm — each
   with a comment saying why. Adding an array-taking method to OakAppKit would be
   a seventh spelling competing with six working precedents. Write the loop.
17. **"Dropped by the importer" is not uniform, so check the member.** Under
   `SWIFT_OBJC_INTEROP_MODE=objcxx` a `std::map` *return type* is dropped, but a
   `text::range_t const&` *parameter* imports fine. That decides whether a Swift
   class can declare a protocol conformance or has to leave it on the ObjC++
   category: `OakTextViewDelegate` yes, `FindDelegate` no, and both protocols have
   exactly one C++-typed member.
18. **Pin the ObjC selector surface with `-instancesRespondToSelector:`.** Two
   classes of defect are invisible to the compiler *and* to a green suite:
   an action method that was never ported (a greyed-out menu item, because
   `-targetForAction:` looks up by selector), and an `@optional` protocol method
   whose Swift spelling does not match the imported name — that one compiles,
   satisfies nothing, exposes no selector, and the feature silently does nothing.
   `-performDropOfTabItem:fromTabBar:index:toTabBar:index:operation:` was written
   with Swift's `from:`/`to:` and tab drag-and-drop was dead with no warning. A
   test listing the selectors caught it on its first run; `t_be_interop.mm:80`
   already did this for one selector, and it generalises.

The next four are from OakAppKit and the gutter bug (2026-08-13). The first three
say what "portable" actually means; the fourth is about debugging what you can
see.

19. **Swift can *call* a global, never *export* one.** Neither a free function nor
   an `extern` constant can come from Swift. A file whose public surface is
   globals — `OakUIConstructionFunctions.h` has 14 functions and 31 consumers,
   `OakRolloverButton.h` has two `extern NSNotificationName const`, `OakView.h`
   four mask constants — cannot become Swift while its callers are ObjC++; it can
   only gain a forwarder `.mm`. Defer those until the consumers are Swift.
   Corollary: a **C++ default argument** hides such a function from any survey,
   because the call sites do not mention the parameter.
20. **Classify portability from the implementation, not the header.** "It has a
   class" is not enough. `OakSyntaxFormatter` looks clean and holds a
   `parse::grammar_ptr` **ivar** — the `bundles::item_ptr` blocker, needing the
   `DWScopeContext` treatment. `NSSavePanel Additions` looks trivial and has a
   `+initialize`, which a Swift extension cannot provide. Grep each candidate for
   C++ member declarations and for `+initialize` before promising it.
21. **Rule 11 cascades.** Before porting a class, grep for its header in other
   *public headers*, not just in `.mm` files. `OakRolloverButton.h` is imported at
   line 1 of `OakUIConstructionFunctions.h`, which the bridging header needs — so
   defining that one class in Swift breaks every use as
   `__ObjC.X` vs `Module.X`, and fixing it means splitting a header 31 files
   import.
22. **When something renders but is invisible, bisect the view out early.**
   Replace the suspect view with a dozen lines that fill themselves red. If that
   is invisible too, the view is innocent and its code is a dead end — stop
   reading it. Then set `backgroundColor`/`borderWidth` directly on the layers:
   pure Core Animation, no `drawRect:`, no backing store. If *that* is invisible,
   the subtree is occluded rather than failing to render, and the answer is a
   front-to-back walk of every layer containing the point. The empty gutter cost
   hours because six increasingly exotic facts about `GutterView` were all true
   and all irrelevant; the occluder was found on the first run of the walk.
   Related discipline: **`drawRect:`'s `aRect` is not clamped to the view's
   bounds** on macOS 26 — clamp it yourself — and **embed a
   `__DATE__`/`__TIME__` build stamp** so "am I running my own code" is a fact.

---

## Rules 23–49 — FileBrowser

23. **Keep a ported class's `.h` as a hand-written ObjC declaration of the Swift
    class.** For a class Swift now defines but ObjC++ still consumes (or subclasses,
    or tests), the `DocumentWindowController.h` arrangement is the default here:
    the `.h` declares the class, consumers `#import` it unchanged, and it is kept
    **out of the Swift bridging header** (importing both spellings is a
    redefinition). Nothing checks the `.h` against the Swift at build time — a
    drift is an unrecognized selector at runtime, which is what the
    `instancesRespondToSelector:` tests (rule 18) guard. FileBrowser has no
    module/class-name collision (no class is named `FileBrowser`), so it *could*
    self-import `FileBrowser-Swift.h` like OakAppKit — the hand-decl is a choice
    for zero consumer churn and testability, not a workaround.

24. **`+load`/`+initialize` registries can't be Swift — convert to explicit,
    lazy registration first, in its own ObjC++ commit.** The `FileItem*` family
    self-registered URL schemes from `+load`, which Swift never runs. Replacing it
    with `+registerBuiltinClasses` (dispatch_once, from the single reader, using
    `NSClassFromString` — safe because `-ObjC` keeps the classes linked) is a
    behaviour-preserving prep step the suite + app validate, and it unblocks the
    whole family. Boundary-then-translation, same as the FSEvents/SCM extractions.

25. **Model files want the `-Cxx`/support-file split, not a hand-decl `.h`.**
    A view class ports whole; a model file usually has one C++ fragment (an scm
    map walk, a `path::` call) surrounded by ObjC. Move that fragment **verbatim**
    (rule 6) into a small ObjC++ `…Support` class with a C++-free signature, put
    its header in the bridging header, and the rest becomes Swift.
    `FileItemSCMStatusSupport` / `FileItemObserverSupport` are the worked examples.

26. **Swift 6: a class that hops off the main thread and back cannot capture
    non-Sendable `self`.** The whole browser is main-thread, so mark such classes
    `@MainActor` (which makes them Sendable), run only the *work* in a **file-scope
    `nonisolated async` function** the `@MainActor` code `await`s, and apply the
    result on the main actor. `DispatchQueue.global{…self…}`, `Task.detached{…self…}`,
    and `Task{} + MainActor.run` all fail the sending checks; the await-a-nonisolated-
    function shape is the one that compiles. `@MainActor` deinit teardown runs
    inside `MainActor.assumeIsolated`; a mutable static that matches an
    unsynchronised ObjC++ original is `nonisolated(unsafe)`.

27. **Preserve ObjC ownership exactly — do not "improve" a weak/strong choice.**
    `URLObserverClient.urlObserver` was strong in the ObjC++ (no `weak`), because
    the shared observer is only weakly held by its registry and the client — held
    by the browser — is its real owner. Making it `weak` in Swift deallocated the
    observer before its async load delivered, and **the directory silently showed
    empty** while every test stayed green. Read the `@property` attributes; a
    missing `weak` is load-bearing.

28. **The objcxx importer renames, and the pattern isn't uniform — let the build
    tell you, then record it.** Seen this session: `getter=isX`/`hasX` needs
    per-accessor `@objc(name)` (rule 4) or consumers using the property name
    break; a factory class method imports as an initializer
    (`+imageNamed:inSameBundleAsClass:` → `NSImage(named:inSameBundleAsClass:)`);
    an `extern NSNotificationName const` drops its `Notification` suffix
    (`…MouseDidEnterNotification` → `.OakRolloverButtonMouseDidEnter`); a **C++
    default argument is not imported** so every arg must be passed
    (`OakCreateActionPopUpButton(false)`) — **WRONG; corrected 2026-09-02 by
    measurement, see rule 61**; and `…AtURL:`/`…ForURL:` selectors trim
    the trailing `URL` inconsistently (`repositoryAtURL:` → `repository(at:)` but
    `addObserverToRepositoryAtURL:usingBlock:` → `addObserverToRepository(at:usingBlock:)`).

The next two are from `FileBrowserView` (`53638c07`). Neither is about Swift —
both are ways this repo's test harness lies to you.

29. **Editing a test file needs a re-seed.** `seed_xcodeproj.rb` **inlines** every
    `tests/t_*.mm` into `ide/gen/tests/<Bundle>_impl.mm` (with `#line` directives,
    which is why failures still point at your file). Only that generated file is
    in the project, so after editing a test `xcodebuild` finds nothing changed,
    silently re-runs **the previous build's test code**, and reports the same
    failure at the same line — which reads as "my fix did nothing". Re-run
    `extract_specs.rb` + `seed_xcodeproj.rb` after any test edit, not just after
    adding or removing files.

30. **`to_s()` on an `NSString*` does not work in an ObjC++ test bundle** unless
    `ns.h` is in scope, and nothing warns you. `ide/xctest_preamble.h` defines a
    generic `to_s(_T const& container)` that for-in-enumerates its argument; with
    `ns.h`'s `to_s(NSString*)` absent it binds to that template, compiles clean,
    and dies at runtime with
    `-[__NSCFConstantString countByEnumeratingWithState:objects:count:]:
    unrecognized selector` pointing at `xctest_preamble.h`, not at your test.
    `OakAppKit`'s tests get `ns.h` from their PCH; FileBrowser's do not. Compare
    strings with `-isEqualToString:` inside `OAK_ASSERT` instead.

The next three are from `FileBrowserDiskOperations` (`be5453a2`), the first port
here that changes files on disk rather than pixels.

31. **A Swift extension can add methods to an ObjC class, but never override
    one.** Porting a *category* is otherwise straightforward — the class can stay
    ObjC++, `self`'s ObjC properties resolve (including to Swift types the module
    defines), and the bridging header may import the class's header as long as it
    does not also see the declarations of the methods Swift defines (split those
    into their own header first). The exception is an inherited method:
    `-presentError:` overrides NSResponder's, and no Swift extension can express
    that, so it stays a small ObjC++ category. Check for overrides *before*
    planning the split — they decide how much has to stay behind.

32. **An out-parameter that looks like a result is often an input to undo.**
    `-trashItemAtURL:resultingItemURL:` writes back where the item landed, and
    that URL is the *only* record of it — undo moves the item back from there.
    A Swift translation that declares `var resultingURL: NSURL?` and never
    assigns it onward compiles, trashes correctly, passes every test that checks
    the file is gone, and silently makes undo a no-op. Trace where each
    out-parameter's value is read, not just where it is written.

33. **ObjC nil-messaging is behaviour, and Swift's bounds checks are not.**
    `-undoOperation:sourceURLs:…` is called with a **nil** sourceURLs array for
    operations that have no sources; `srcURLs[i]` answered nil for every index,
    and the results were collected with `if(srcURL)`. Translated literally to
    `srcURLs[i]` on a Swift array, that is a trap at the first new-file undo.
    Same family as rule 27: read what the ObjC did with nil, not what it looks
    like it did. Related: use `-[NSURL isEqual:]`, not Swift's `URL ==`, wherever
    the ObjC++ compared URLs — `URL ==` normalises, and these are compared
    against FileItem URLs.

34. **A test file cannot declare an ObjC class.** `seed_xcodeproj.rb` wraps each
    `tests/t_*.mm` body in a **C++ namespace** (hoisting its leading `#import`s
    out), so an `@interface`/`@implementation` in one fails with "Objective-C
    declarations may only appear in global scope" — pointing at your file, via
    the `#line` directives, with nothing in your file to explain it. This bites
    exactly when writing a KVO test, since ObjC KVO needs an observer object. The
    better test anyway is to **bind a real control** the way the app does
    (`t_file_browser_view_controller.mm` binds an NSButton's enabled state to
    `canGoBack`): it exercises the mechanism that has to survive rather than a
    proxy for it.

35. **Extracting the C++ usually makes it testable — take the test while it is
    cheap.** The browser's visibility rule was a private method that only ran
    with a live tree, so nothing covered it; moved out behind a C++-free
    signature it became a pure function of a directory URL, and the branch a port
    is most likely to invert (hidden items go through the *include* globs,
    everything else through *exclude*) got its first test in the same commit.
    Two disciplines that go with it:
    - **Assert the verbatim move, do not eyeball it** (rule 6, made concrete):
      check the moved text is a substring of `git show HEAD:<file>`, and if you
      re-indent afterwards, check that the re-indent changed nothing but leading
      tabs. Both are three lines of script and they turn "I moved it carefully"
      into a fact.
    - **Do not assert values that come from `settings_for_path`.** They are read
      from `.tm_properties` and the bundled defaults, so they differ per machine.
      A first draft of the glob test asserted that a dotfile in `/tmp` passes the
      include globs; it does not on this machine. Assert the logic you moved, not
      the configuration it reads.

The next five are from the three extraction commits (`b4fb22e7`, `b3ba8abf`,
`6266b9a8`). The first two are both ways the survey's "seven C++ clusters"
figure was wrong in each direction.

36. **Before extracting a C++ container, check whether the thing it feeds
    already has an ObjC-shaped API.** The inactive key-equivalents table looked
    like a cluster to move: a `std::map<SEL, std::string>` applied with
    `-setInactiveKeyEquivalentCxxString:`. But OakAppKit grew an NSString
    spelling when BundleMenu was ported, and it is literally
    `…CxxString:to_s(arg)` — the same code path one conversion earlier. So the
    C++ disappeared with an in-place rewrite and no support method. A framework
    this far into a port has consumers that were *already* de-C++'d for someone
    else; grep for an NSString sibling before designing a boundary.

37. **Some C++ cannot be extracted at all, because the callee is C++-typed on
    both sides.** Rule 20 is about types that cannot cross into Swift; this is
    worse and reads the same at a glance. `-executeBundleCommand:` fails not on
    `bundles::item_ptr` but on `OakCommand`, whose own API takes a
    `bundle_command_t const&` and a `std::map`. No boundary makes that method
    Swift — it can only *move*, into ObjC++ that stays ObjC++. Check the
    signatures of what a fragment calls, not just the types it names.

38. **Delete the dead imports as part of the extraction, and expect the build to
    fail on something the file never imported.** Removing `<bundles/bundles.h>`,
    `<settings/settings.h>` and `<regexp/glob.h>` broke the build on `path::` at
    three sites: `<io/path.h>` had been arriving transitively through them for
    years. Same for `text::join`. This is worth doing *before* the translation
    rather than after — a Swift file cannot inherit an include, so every one of
    these would otherwise surface as a mystery at the worst moment. The cleanup
    is also the only proof the extraction was complete: an import that is still
    needed is C++ you did not move.

39. **Check whether a C-looking type is actually C++ before designing around
    it.** `path::device` returns `dev_t`, which looks like it belongs on the far
    side of a boundary but is an `int32_t` from `<sys/types.h>` — it imports
    into Swift as-is. Returning it kept the drop target stat-ed once per drag
    instead of once per dragged item. The boundary that avoids a C++ type is not
    automatically the boundary you want.

40. **A test that cannot fail is worth nothing — prove each new one can.** Both
    disciplines came up in the same commit. The key-equivalent test was
    mutation-checked (swap `NSDownArrowFunctionKey` for its Up counterpart; it
    must fail, and it does). The bundle-items test was probed the same way and
    turned out **vacuous**: no bundle index loads in a test process, so
    `items.count != 0` fails and its per-item loop never runs. That is written
    into the test file rather than quietly left, because the next reader will
    otherwise trust it to cover the menu. Where the suite genuinely cannot
    reach — a drag session, a live `QLPreviewPanel`, a bundle command — say so
    in the commit and check it in the app instead of inventing a test that
    exercises AppKit.

The next five are from the five peel commits (`30a3e668` … `a20346be`) and the
promotion (`2b34881a`). The first three are all one theme: **what a header is
allowed to say depends on who imports it.**

41. **A method declared in the class's own public header cannot be defined in
    Swift while the class is still ObjC++.** `FileBrowserViewController.h` is in
    the bridging header — it must be, since Swift extends the class — so
    defining one of its declared methods in a Swift extension gives that
    selector two declarations and collides. `FileBrowserDiskOperations.h` got
    around this by moving its declarations to a header the bridging header does
    not see; that only works when **no outside consumer needs them**, and
    `newFile:`/`newFolder:`/`goToURL:` and the rest are called by
    `DocumentWindowController.swift` through the public header. So roughly
    twenty methods cannot peel at all and must wait for the flip. Check header
    visibility when planning a section, not just ivars and overrides.

42. **Never declare a protocol conformance in a header the bridging header
    imports.** The obvious way to let a peeled section assign `self` to a
    delegate property is to re-state the conformance in the internal header.
    Legal ObjC, and it breaks the build: once Swift can see *both* the protocol
    and the conformance, the imported protocol member counts as a previous
    declaration of that selector, and the witness fails with "method
    'control(_:textShouldEndEditing:)' … conflicts with previous declaration".
    The data source section only compiles because its `NSOutlineViewDataSource`
    conformance stays invisible in the `.mm`. Let the **Swift extension** declare
    the conformance instead — which then forces the witness `public`, an
    artifact of imported ObjC classes being public in Swift that widens nothing.

43. **The generated `-Swift.h` is not importable in this framework's `.mm`, and
    the previous handoff was wrong to suggest it might be.** It said FileBrowser
    "could self-import `FileBrowser-Swift.h`" because, unlike Find, no class here
    is named after the module. That is not the binding constraint: the generated
    header declares every class the framework's Swift defines, and the `.mm` also
    imports the **hand-written** headers for those same classes (`FileItem.h`,
    `FileBrowserView.h`, `FileBrowserOutlineView.h` — rule 23), so clang rejects
    the duplicate interfaces. Hand-write a category header instead
    (`FileBrowserActions.h`) and import it only from the `.mm`. Worth doing
    rather than tolerating the warnings: without it, every `@selector` in the
    menu construction becomes `-Wundeclared-selector`, which is the
    silently-dead-menu-item failure of rule 18.

44. **Unannotated ObjC types import as implicitly unwrapped optionals, and
    interpolating one prints the wrapper.** `FileItem.localizedName` is
    `String!`, so `"Copy “\(item.localizedName)”"` put the literal text
    `Copy "Optional("committed.txt")"` into the context menu — with the whole
    suite green. The same shape traps instead of printing when the value feeds a
    force-unwrap: `(item ?? fileItem).arrangedChildren` took the test process
    down on the very first peel. **Read the ObjC declaration's nullability
    before translating a line that uses the value**, and prefer annotating the
    header (`nonnull` on `selectedItems`/`previewableItems` removed a
    meaningless unwrap from every call site) over coping at each use.
    Interpolation is the dangerous one, because nothing fails.

45. **Promote ivars to properties as its own prep commit, before the sections
    that need them.** A Swift extension cannot see an ObjC instance variable at
    all, so nine ivars in a `{ … }` block were pinning twenty-two otherwise
    ordinary methods into the `.mm`. Promoting them is mechanical and provably
    faithful: auto-synthesis backs each property with an ivar of exactly the
    name it had, so every `_foo` still resolves and a mismatch is a compile
    error rather than a silent rebinding. Copy the ownership across unchanged
    (rule 27) — a promotion is not the moment to reconsider a weak/strong
    choice. Expect the suite to be **unchanged in both directions**; the app run
    is the only real check, so pick the checks that exercise the promoted
    storage specifically.

This last one is from `d680bbe5`, which fixed a crash the loading peel shipped.

46. **When a peel replaces `_foo` with `self.foo`, check what `-foo` actually
    is.** This is rule 45's other half and the more dangerous one: promoting
    ivars makes them *reachable*, and the reachable thing is not always the thing
    the ivar was. `_expandedURLs` / `_selectedURLs` are the pending expand/select
    sets; `-expandedURLs` / `-selectedURLs` are accessors that merge them with
    what the outline view currently shows and return `[res copy]`. Same name,
    different value, and immutable. The loading peel took the accessors at seven
    sites, so every read answered about the screen instead of the pending set and
    `expandedURLs?.remove(url)` sent -removeObject: to an NSSet — **collapsing any
    folder crashed the app, with the whole suite green.** Three disciplines:
    - **Grep the `.mm` for a hand-written accessor before translating any
      property access.** An ObjC property whose getter is overridden to return a
      different type is legal, and from Swift it is invisible.
    - **Give the ivar its own name rather than sharing one** — here
      `pendingExpandedURLs` — and take the accessor that means something else
      *out* of the header Swift sees. The peel could not have made this mistake
      if the wrong name had not been in scope.
    - **A test for this kind of defect does not fail, it crashes.** Expect the
      "prove it can fail" step (rule 40) to look like `Restarting after
      unexpected exit` rather than an assertion, and read the whole log — an
      ObjC exception surfaces as "C++ exception handling detected but the Swift
      runtime was compiled with exceptions disabled", which names neither the
      selector nor the class.

The last two are from the flip itself (`53923fe4`). Both are about the same
thing from different directions: **once Swift defines the class, Swift's own
view of it becomes the one that counts** — and it does not inherit what ObjC
knew.

47. **A Swift dynamic cast cannot see a conformance that only ObjC declared, and
    cannot see through an NSProxy.** Two forms, one root, and they cost most of
    the flip:
    - **`as?`/`as!` to an @objc protocol the class adopts only in an ObjC
      category fails.** Swift reads its own conformance metadata, which a
      category does not write. `(self as AnyObject) as! NSOutlineViewDataSource`
      compiles and dies with "Could not cast value of type
      'NSKVONotifying_FileBrowserViewController'" — note the KVO subclass in the
      message, which is a red herring: it fails for the plain class too.
    - **`as?` to the class itself fails on an NSProxy.**
      `-prepareWithInvocationTarget:` hands back a proxy, and
      `as? FileBrowserViewController` worked for years only because the proxy
      forwards `-isKindOfClass:` to its target and the target was an *imported
      ObjC* class. Against a Swift class the cast reads the proxy's own isa and
      says no.

    The second is far more dangerous than the first, because it is inside an
    `if let`: **nothing throws, nothing logs, the branch is simply skipped**, and
    every undo in the framework quietly stopped being registered while the menu
    item stayed enabled (the window's own undo manager keeps it that way). Three
    disciplines:
    - **When a flip makes a class Swift, grep the whole framework for `as?` and
      `as!` naming that class or a protocol it adopts**, and account for each
      one. This is not a compile-time change and the suite will not find it.
    - **Prefer the API with no proxy in it.**
      `-registerUndoWithTarget:handler:` replaced
      `-prepareWithInvocationTarget:` and the problem stopped existing.
    - **Where the conformance must stay in ObjC, do the assignment in ObjC
      too** — a two-line `+wire…` helper taking `id`. ObjC does no conformance
      check, which is exactly the pre-flip behaviour.

48. **Verbatim is not always possible: check the arithmetic you are moving, because
    Swift bounds-checks what C++ did not.** `MutableLongestCommonSubsequence`
    allocated `width * height` and then indexed `matrix[width*i + j]` with `j`
    running to `rhs.count` — the stride for that loop is `height`. Three items
    against one addresses index 13 of an 8-element array. It had been wrong for
    as long as it had existed and never showed, because the only path that
    reaches it is a rename, where the two lists are usually the same length and
    `width == height` makes the arithmetic accidentally correct. Rule 6 says move
    it verbatim; rule 6 cannot be followed here, because the literal translation
    traps. **When a C fragment indexes a flat buffer, re-derive the stride before
    translating it** — and say in the commit that the behaviour changed, because
    "moved verbatim" would be a false claim.

49. **`final` on an `@objc` class is a promise ObjC cannot keep, and breaking it
    is a crash, not a warning.** This has now shipped twice: `aaf43955`
    (OakTransitionViewController, subclassed by PreferencesViewController — an
    unbounded recursion between `init(nibName:bundle:)` and its own @objc thunk,
    ~58,000 frames, on every Settings open in alpha.10 **and** alpha.11) and
    `dc66d10d` (six preference classes, which KVO subclasses *at run time* — so
    the subclass never appears in any source file you could grep). ObjC has no
    `final`; nothing stops a subclass, and Swift meanwhile compiles initialisers
    and dispatch on the assumption that none exists.
    **Do not put `final` on a class that ObjC can see** — that means anything
    `@objc(Name)` with a hand-written `.h` (rule 23), anything a nib instantiates,
    and anything KVO observes. `final` is only sound where the class is
    Swift-visible only.
    **The sweep is done (`142b0059`, 2026-08-18).** The whole shipped surface was
    audited against "can ObjC reach this, or can KVO subclass it?" and `final`
    dropped from 56 classes across 42 files — every `@objc(Name)`/hand-`.h`,
    nib-instantiated, KVO-observed, or bound-to class. `final` was kept only where
    it is sound: `private final class` (Swift-visible only) and test classes.
    Full suite stayed green (658/0) and the Release app ran clean, so this closed
    the whole class instead of the six preference classes `dc66d10d` patched. The
    standing rule is now the going-forward guard, not a pending task: when you add
    a `final class`, apply the same test before shipping it.

---

## Rules 50–51 — OakFilterList

50. **On a Swift class that ObjC subclasses, every `@objc` member must also be
    `dynamic` — not just the methods you expect to be overridden.** A statically
    compiled ObjC subclass has no Swift vtable. Any base-internal Swift call that
    dispatches through one therefore reads past the ObjC class metadata and jumps
    into data as soon as `self` is a subclass instance. Found porting `OakChooser`
    (`1a97557a`), whose four subclasses are ObjC++: the crash was `EXC_BAD_ACCESS`
    in the `items` setter, and the offending call was not a hook at all but the
    innocuous lazy `itemCountTextField` getter. Marking only the overridable hooks
    `dynamic` is not enough and fails in a way that looks like memory corruption
    rather than a dispatch bug. `dynamic` forces `objc_msgSend` throughout, which
    is *also* what makes a subclass override win when the base calls the method on
    `self` — the two problems have one fix. This is rule 49's sibling: 49 is what
    ObjC subclassing does to `final`, 50 is what it does to dispatch. Pin it the
    way `t_chooser.mm` does — an ObjC subclass in the test bundle that counts the
    base's calls into its own overrides — because nothing else catches it: the
    build is clean and every Swift-only test passes.

51. **`remove(atOffsets:)` is SwiftUI, not the standard library.** Using it on a
    plain `Array` in a framework compiles, then auto-links SwiftUI into the static
    archive and breaks the link of *every* consumer that is not allowed to link
    `SwiftUICore` (`OakChooser` took out `CommitWindowTests`). The error names an
    undefined `RangeReplaceableCollection.remove(atOffsets:)` symbol and points at
    the consumer, not at the file that caused it. Remove by reversed index instead.

---

## Rule 52 — OakRolloverButton

52. **A forward declaration is not a type in Swift.** `@class X;` in a header that
    reaches Swift through a bridging header imports as an *opaque* type: no
    superclass, no inherited members. Not "an NSButton whose extras are missing" —
    `.target` and `.action` are unreachable, and it will not convert to `NSButton`.
    So breaking a rule-21 cycle by replacing an import with a forward declaration
    does not make the dependency go away; it moves the import to every consumer
    that *uses* the value, not merely to those that subclass or extend it. Budget
    for that, and let the build enumerate them: splitting `OakRolloverButton.h` out
    of `OakUIConstructionFunctions.h` (`004c3f37`) built the whole app and then
    failed in exactly one file, `OakFilterList`'s `FileChooser.swift`, with `value
    of type 'OakRolloverButton' has no member 'target'`. The corollary is that the
    split is still the right move: the forward declaration is what lets nine
    bridging headers keep importing the free functions without dragging a Swift
    class's hand declaration back into its own framework's bridging header
    (rule 43).

---

## Rule 53 — OakEncodingPopUpButton

53. **A test that writes `NSUserDefaults` and restores at the end poisons its own
    next run.** `oak_assertion_error` throws, so a failing assertion skips every
    line after it — including the restore — and the value it happened to be
    testing with is now persisted in the test host's domain. The next run reads it
    as ambient state. This cost an hour: a ten-encoding fixture left behind by a
    failed assertion made `t_encoding_pop_up.mm`'s *flat menu* test build a
    hierarchical menu, in a test that never touched the defaults, and the obvious
    reading was that the production code was wrong. Restore from a destructor
    instead — `available_encodings_t` in that file is the pattern — and have each
    test set the state it needs rather than leaning on what it inherits. The same
    applies to any process-global a test mutates: the bundle index, the
    pasteboard, the registration domain.

---

## Rule 54 — OakOpenWithMenu

54. **A search-and-replace that rewrites every call site rewrites the callee too.**
    Extracting a repeated expression into a helper and then replacing that
    expression everywhere turns the helper's own body into `return helperName(x)`.
    It compiles, it type-checks, and it is unbounded recursion. Porting
    `OakOpenWithMenu` this way produced

        private func filePath(of url: URL) -> String { filePath(of: url) }

    which crashed six test processes with `EXC_BAD_ACCESS` in the stack guard
    region. Write the helper *after* the replacement, or exclude its own body, and
    read back what the edit produced rather than the diff summary.

    **The half that matters more: a crashed test process reports zero failures.**
    xctest relaunches, prints `Restarting after unexpected exit, crash, or test
    timeout`, and the bundle's `Executed N tests, with 0 failures` line counts only
    the tests that *ran*. A tail-of-the-log summary therefore looks green. The
    local check is the same one `.github/workflows/build.yml` now gates on, and it
    is two greps:

        grep -c "Restarting after unexpected exit" "$log"
        grep -c "Test Case .* started" "$log"; grep -c "Test Case .* passed" "$log"

    Started ≠ passed means a process died. This is the second time in one session
    that a green-looking summary hid a crash; treat "0 failures" as meaningless
    until the crash counter is also zero.

    **Both greps miss a trap that happens after the last test in a bundle passes**
    (added 2026-09-02). Every test starts and passes, so the counts agree, and
    locally xctest prints no restart banner at all — only the trap itself. A third
    grep is required:

        grep -c "Fatal error:" "$log"

    `OakPasteboard.swift` trapped on a nil `NSApp` at the end of every `FindTests`
    run from the commit that ported it until this was found, and **four
    consecutive local full-suite runs in one session were reported as "0
    crashes"** on the strength of the two greps above. CI caught it only because
    the runner's log *did* carry the restart banner. `.github/workflows/build.yml`
    now gates on this grep too.

55. **A trivially-copyable C++ struct *does* import into Swift; rule 17 is
    narrower than it looks.** `GVLineRecord` is a C++ struct with a constructor,
    returned **by value** from `GutterViewDelegate`. The OakDocumentView port was
    planned around an ObjC++ category to hold the two methods that return it —
    and the category turned out to be unnecessary. Swift declares those methods,
    implements them, calls them, and reads the struct's fields.

    Rule 17 is about C++ types Swift cannot *represent* — `std::string`,
    `std::shared_ptr`, a non-const `std::map&`. A plain aggregate of scalars is
    not one of those, even with a constructor and even returned by value.

    **Do not infer a blocker from the presence of C++ in a signature.** Build a
    one-file probe and let the importer answer — the same discipline rule 28
    already demands for names. The cost of guessing wrong in this direction is a
    boundary file nobody needed, and a file wrongly written off as unportable.

    What *does* still block a port is storage: rule 20. `GutterView` stays
    ObjC++ because its state is C++ ivars, not because of `GVLineRecord`.

56. **A Swift subclass, in another module, of a Swift class seen through a
    hand-declared ObjC header cannot be KVO-swizzled.** Registering any KVO
    observation on such an object traps inside
    `swift_objc_classCopyFixupHandler` during `objc_allocateClassPair` — a
    SIGTRAP, not an exception, so a test process dies rather than failing.

    The shape that hits it: `FavoriteChooser` (Swift, in `Applications/TextMate`)
    subclassing `OakChooser` (Swift, in `OakFilterList`, which the app sees only
    through `OakChooser.h`). The app's compiler believes the superclass is an
    ObjC class; the runtime knows better; KVO's class copy cannot reconcile the
    two.

    **Rule 23's hand declarations stop at the module boundary for subclassing.**
    Using another module's Swift class is fine — that is how `SymbolChooser` and
    `OakChooser` are consumed everywhere. *Subclassing* one and then observing it
    is not.

    Inverting the binding does not help: `-bind:toObject:withKeyPath:` registers
    the observer either way. What works is not subclassing across that boundary —
    put the subclass in the same module as its superclass, or leave it ObjC++.

    `BundleItemChooser` binds its scope bar the same way and is fine, because it
    lives *in* OakFilterList. The difference is the module, not the code.

    **Measured, 2026-09-01.** This started as one crash and an inference; three
    throwaway subclasses in the app target settled it. Each registers a single
    `-addObserver:forKeyPath:` and does nothing else, and all three die with the
    same stack — `swift_objc_classCopyFixupHandler` ← `alloc_class_for_subclass`
    ← `objc_allocateClassPair` ← `_NSKVONotifyingCreateInfoWithOriginalClass`,
    `EXC_BREAKPOINT`:

    | Probe | Shape | Result |
    | --- | --- | --- |
    | A | non-`final`, over `OakChooser` | traps |
    | B | `final`, over `OakChooser` | traps |
    | C | non-`final`, over `OakScopeBarViewController` | traps |

    So neither of the two narrower explanations holds. **It is not `final`** — A
    traps without it, which also means this is *not* the alpha.16 heap-corruption
    bug `dc66d10d` fixed, despite landing in the same runtime handler (that one
    corrupted malloc; this one traps outright). **It is not `OakChooser`** — C
    subclasses a bare `NSViewController` with no windows, no bindings and no
    machinery, and dies identically. The module boundary is the whole cause, and
    `-bind:` was only one way of reaching it.

    **`addObserver:` is the trigger, not the callback.** Nothing was ever set in
    these probes; registering the observation is enough. So the guard is not
    "avoid bindings" — it is that the object must never be observed *at all*,
    by anything, including AppKit doing it behind your back (see
    `-[NSWindow _bindTitleToContentViewController]` in the alpha.16 write-up).

    **The root fix is not one line either.** Letting the app `import OakAppKit`
    and subclass the real Swift class — rather than the hand declaration — was
    tried. It needs `open` on the class, which cascades (`loadView` and the
    `NSMenuItemValidation` conformance must go public), and then the app's Swift
    compile fails to build at all: `google::libc_allocator_with_realloc` has
    different definitions in it and in the `TMText` module shim. Exporting real
    Swift modules to the app is a build-system project, not a refactor.

---

## Rules 57–59 — the AppController pin and extractions (2026-09-02)

All three are about the same failure: **trusting a thing that cannot tell you it
is wrong** — the harness, the oracle, and the app check.

57. **A multi-line string literal cannot live in a test file.**
    `ide/gen_xctest.rb` emits a `#line N "<path>"` directive before *every* line
    when it inlines a test, so a raw string literal reaches the compiler with
    `#line` directives spliced through its middle. The first attempt at the
    AppController menu golden failed with

        expected: #line 122 "…/t_app_controller.mm"

    as the menu's second line, which reads as nonsense until you open the
    generated `_impl.mm`. Put the text in a file under `tests/fixtures/` and read
    it back through `__FILE__` — the `#line` rewriting is precisely what keeps
    `__FILE__` pointing at the source tree, and `network/tests/t_download.cc`
    already does this for its fixtures. Better anyway: a golden becomes a
    reviewable file in a diff instead of hundreds of lines of literal.
    Third member of the rules 29/34 family — the harness rewrites test files, and
    what it does is invisible from the file you are editing.

58. **A pin is only as good as its oracle — verify the oracle first, and check it
    is order-independent.** Two ways `MBDumpMenu` lied while building the
    AppController golden, both found only by reading it:
    - **A nil-vs-nil comparison read as a match.** `item.target == NSApp.delegate`
      is true for *every untargeted item* when `NSApp.delegate` is nil, which it
      is in a test process, so the dump claimed 248 items targeted the delegate.
      A pin built on that would not have noticed a port that really did set
      `.target`. Fixed with a nil guard before trusting it.
    - **The dumper read process-global state, so it was not idempotent.**
      `MBCreateMenu` *assigns* `NSApp.servicesMenu`, `.windowsMenu`, `.helpMenu`
      and the shared font menu for `.systemMenu` items, and `MBDumpMenu` prints
      `.systemMenu = …` by comparing against those globals. Build the menu twice
      and build #2's Services submenu is no longer the one NSApp holds, so it
      dumps as a plain delegate-owned submenu. The tests share one build, which
      is also what the app does.
    Generalise both: before making something a golden, ask what it *reads* that
    the code under test does not own, and prove two runs agree.

59. **A rule-8 check that cannot fail proves nothing — this is rule 40 applied to
    the app run.** Twice in one session an app check was worthless and looked
    fine:
    - "The app launched and reached `-applicationDidFinishLaunching:`" would have
      passed with the theme registration deleted entirely.
    - The first theme probe resolved the *user's own saved* `universalThemeUUID`
      and never touched the registration domain at all — the exact thing the
      change put at risk.
    The fix is the same as for a test: pick the observation that differs between
    working and broken, and say what it would have shown. The run that settled it
    logged the ordering *and* the registration domain, and caught the machine in
    dark mode with no override, so the read demonstrably went through the
    fallback.
    **The technique that made this affordable: instrument, run, revert, do not
    commit.** Three checks this session were probes added to production files,
    read out of `log show`, then reverted before the commit — the settings paths,
    the theme ordering, and a real `txmt://` round trip. State in the commit that
    the probe was reverted, and quote what it printed.
    Two practicalities. `screencapture` and System Events both need permissions
    that may simply not be available, so do not plan a check around a screenshot;
    `/usr/bin/log show --predicate 'process == "…"'` needs the *executable* name,
    which here is `TextMate-NG`, not the target name. And **driving a code path
    that ends in `[NSAlert runModal]` wedges the app** — with accessibility
    unavailable the only way out is to kill it.

---

## Rule 60 — the menu conversion (2026-09-02)

60. **A test file is compiled with ARC off, so ObjC++ copied into one from a
    project file does not mean the same thing.** `ide/seed_xcodeproj.rb` sets
    `CLANG_ENABLE_OBJC_ARC = NO` for the generated test bundles on purpose —
    some tests reach headers ARC rejects, e.g. `settings/src/track_paths.h`
    calls `dispatch_release`. The consequence nobody had hit until now:

        NSMenu* lightMenu;          // nil under ARC. Garbage in a test file.

    `-themesMenuNeedsUpdate:` declares its two submenu locals exactly like that
    and is correct, because `AppController Menus.mm` compiles under ARC. Copied
    verbatim into a test to capture a golden, the same lines **crashed the test
    process with no message at all** — no assertion, no exception, nothing in the
    log but the restart banner.

    Two things follow. **Initialise every ObjC local you move into a test file**,
    even when the original does not. And when a probe copied from working code
    dies, suspect the compilation mode before you suspect the code: the harness
    builds your test differently from the thing it is testing.

    Fourth member of the rules 29/34/57 family — the test harness rewrites and
    recompiles your test file, and none of what it does is visible from the file
    you are editing. It was only caught because rule 54's restart counter is
    checked now; the run reported zero failures.

---

## Rule 61 — the free-function probe (2026-09-02)

61. **C++-linkage free functions and their default arguments DO reach Swift under
    `SWIFT_OBJC_INTEROP_MODE=objcxx`. Two earlier claims in this file were
    inferences, and both were wrong.**

    Measured with a throwaway probe (rule 55), reverted before commit. All of
    these compiled *and linked* into the app from Swift:

    | declaration | header | result |
    | --- | --- | --- |
    | `void RegisterDefaults ()` | `Preferences/Keys.h` | calls, links |
    | `void OakOpenDocuments (NSArray*, BOOL = NO)` | `AppController.h` | calls, links, **and the default applies** |
    | `bool DidHandleODBEditorEvent (AppleEvent const*)` | `ODBEditorSuite.h` | calls, links |
    | `extern NSString* const kUserDefaults…Key` | `Preferences/Keys.h` | reads |

    **The control matters and is the reason to believe it.** A declared-but-
    nonexistent `void RegisterDefaultsThatDoNotExist ()` called the same way
    fails at link with

        Undefined symbols for architecture arm64:
          "RegisterDefaultsThatDoNotExist()", referenced from:

    — note the demangled C++ signature with `()`, which is what says the linker
    really is resolving Swift's calls against C++ mangled symbols rather than the
    whole thing being dead-stripped. A probe that cannot fail proves nothing
    (rule 59); this one was made to fail on purpose first.

    **What this corrects.** Rule 28 says "a C++ default argument is not imported
    so every arg must be passed", citing `OakCreateActionPopUpButton(false)`.
    Tested on that exact function: `OakCreateActionPopUpButton()` with no
    arguments compiles. Either it was never true or the toolchain changed; either
    way do not plan around it. Rule 28 now carries a pointer here.

    **What this does *not* change.** Rule 19 still holds in the direction that
    matters: Swift can **call** a global but can never **export** one, so a file
    whose public surface is free functions still cannot become Swift while its
    callers are ObjC++. And rule 19's corollary — that a default argument hides a
    function from a survey, because the call sites never mention the parameter —
    is about reading code, not importing it, and is untouched.

    **Extended 2026-09-04: namespaces too.** `scm::disable()` and `scm::enable()`
    are called from app Swift as `scm.disable()` / `scm.enable()`, and they link.
    Same control discipline — a declared-but-nonexistent
    `scm::enableThatDoesNotExist()` fails with the demangled namespaced signature.
    So the barrier is never the *linkage*; it is only ever whether the
    declaration can reach a bridging header. `<scm/scm.h>` cannot (std::shared_ptr
    throughout), so that one still gets a two-line forwarder — but by choice,
    to avoid a duplicate declaration nothing checks, not because Swift could not
    call it.

    The practical consequence for the AppController port: `RegisterDefaults()`,
    `OakOpenDocuments()` and `DidHandleODBEditorEvent()` are **not** blockers and
    need no shims. One thing does follow, though: `OakOpenDocuments` is declared
    in `AppController.h` alongside `@interface AppController`, so when that class
    becomes Swift its hand declaration must stay out of the bridging header
    (rule 43) while the free function must go in — which means splitting the
    header first. That is rule 11, and it is now a step in the flip rather than a
    surprise during it.

## Rule 62 — the probe's own flags (2026-09-05)

62. **A probe that does not reproduce the build's own flags manufactures
    findings. `-std` is the one that bites, because libc++ changes what its
    headers include transitively between standards.**

    Re-running the rule-61 header sweep at the start of the flip, I measured ten
    failures among 34 candidates and diagnosed five framework headers as
    blocking: `scope.h` missing `<atomic>`, `bundles/item.h` missing `<mutex>`,
    `authorization.h` missing `<memory>`, and so on. Each diagnosis was
    *correct as stated* — those headers really do use those types without
    including them — and I patched all five.

    They were not blockers. The project sets

        bs["CLANG_CXX_LANGUAGE_STANDARD"] = "c++2a"     # ide/seed_xcodeproj.rb

    and my probe passed `-std=c++2b`. Under C++23 libc++ stopped pulling
    `<atomic>`, `<mutex>` and `<memory>` in through `<string>`, so eight headers
    that parse fine in this project failed in the probe. Re-measured at the
    project's own standard:

        -std=c++2b (mine):     24/34 pass — 10 failures, 5 "blockers"
        -std=c++2a (project):  32/34 pass —  2 failures, 0 blockers

    All five header patches were reverted. They fixed nothing that was broken.

    C++23's `basic_string(nullptr_t) = delete` produced the most convincing false
    positive of the set: `text/types.h:119` `range_t(0)` fails to compile at
    c++2b — *with the prelude too*, which is what made it look like a real latent
    bug rather than a probe artifact. At c++2a the deleted constructor does not
    exist and the call resolves to `pos_t` as intended.

    **What the probe was still worth.** The two genuine failures were both
    `oak/debug.h` needing `<map>`, reached only through `<OakAppKit/OakToolTip.h>`
    — which turned out to be a dead import in the two files that named it
    (rule 38). So the correct change was deleting two `#import` lines, not
    patching five framework headers. The handoff's claim that every header the
    class needs already reaches a bridging header was right; my alarm was not.

    **The rule.** Before believing a probe, print the real target's flags and
    diff them against the probe's. `-std`, `-D`, and the include order all
    change the answer. Rule 55 says probe rather than infer; this says a probe
    is itself a thing to be verified, and the cheapest verification is that its
    failures reproduce in the actual build.

    Related: rule 59 (a probe needs a control that must fail). Mine had three
    controls and two of them failed, which is why I trusted it — but a control
    only proves the probe *discriminates*, never that it discriminates on the
    same axis the real build does.

## Rule 63 — the flip, and a static that owned nothing (2026-09-05)

63. **A test bundle compiles with ARC off, and a ported method still returns +0.
    Caching one in a `static` gives you a pointer you do not own — and it can
    survive the port that exposes it for a long time before it stops.**

    `t_app_controller.mm` caches the 248-item menu, deliberately, because
    MBCreateMenu assigns process-global AppKit menus and a second build dumps
    differently (rule 58):

        static NSMenu* menu = [[AppController new] mainMenu];

    `-mainMenu` returns +0 — autoreleased — under ARC *and* as an `@objc` Swift
    method; the convention is the same either way. This file compiles with ARC
    off (`ide/seed_xcodeproj.rb` sets `CLANG_ENABLE_OBJC_ARC = NO` for test
    bundles), so nothing retains it and the menu dies at the next pool drain.

    It passed for months. After AppController became Swift it was **signal segv**
    — and only when an *earlier* test had already built the menu, because
    build-and-dump inside one test happens before the drain. Running the file
    alone reproduces it; running the one test alone does not. That is the shape
    to recognise: a crash that depends on which other test ran first.

    **What I could not establish.** The pre-flip pair still passes, so the flip
    changed the object's lifetime — but the ownership contract is identical on
    both sides, and I never found what had been keeping the menu alive. Do not
    let that stop you: caching a +0 return in a static is wrong on its own terms,
    and `[[…] retain]` is the fix regardless of which accident preceded it.

    **The application was never at risk**, and that is the thing to check before
    believing a crash like this is cosmetic: `-applicationWillFinishLaunching:`
    assigns the menu to `NSApp.mainMenu`, and NSApplication retains it. Checked,
    not assumed.

    Two smaller things the same flip turned up, both likely to recur:

      * **A mutable global cannot be read from Swift.** `theme`'s UUIDs were
        `extern char const* k…` — pointer mutable — and Swift imports that as
        `var`, then refuses it: "not concurrency-safe because it involves shared
        mutable state". `char const* const` fixes it and was always correct.
      * **`@MainActor` on the ported class is not a new constraint.** AppController
        is instantiated by a nib on the main thread and every API it touches is
        main-thread-only. Saying so is what lets Swift 6 accept `self` being
        passed to `-showWindow:`; the alternative is a scattering of
        `MainActor.assumeIsolated` at each call.

    And one worth copying: adopt `NSApplicationDelegate` explicitly rather than
    relying on `-respondsToSelector:` as the ObjC did. Same methods, but a
    signature that drifts by one colon becomes a compile error instead of a
    delegate callback that is silently never called — which is rule 18's failure
    mode arriving somewhere rule 18's tests do not look.
