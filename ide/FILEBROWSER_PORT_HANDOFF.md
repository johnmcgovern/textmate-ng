# FileBrowser port — handoff

_Written 2026-08-15, rewritten at the end of the session that finished the C++
extraction — the controller now has no C++ boundary left to move, only the
translation itself. This is the starting point for a fresh session; the
per-commit detail and the reasoning behind each decision live in
`ide/FILEBROWSER_PORT_PLAN.md`, and the 22 cross-framework rules that predate
this work are at the end of `ide/FIND_PORT_HANDOFF.md`. Read those two first.
Everything below was measured, not assumed._

## State you are starting from

- `master`, HEAD `6266b9a8`, tree clean. **Not pushed** — the three extraction
  commits are local.
- **636 tests across 36 bundles, green.** Re-measure, never increment — that
  figure has been wrong in these docs before (rule 10). FileBrowser has **10** test
  files (`Frameworks/FileBrowser/tests/t_*.mm`); the framework had **zero** before
  this port began.
- **Nothing is unverified.** `53a7b1e6`'s outstanding visual check was done at
  the start of this session and passed in full — list populates, `.git` hidden,
  Show Invisible Files reveals it and hiding restores it, SCM badges, Finder tag
  dot, live reload, SCM Status, Computer, rename-selects-basename, back
  navigation. Screen capture works on this machine again; the failure recorded
  in the previous handoff was transient.
- The **first thing settled** was the survey's open question: `FileBrowserViewController`
  **is** constructible in a test process. So this framework's coverage can use
  instances.

### What is already Swift

The entire view layer, the whole `FileItem*` model family, and the disk
operations:

`OFBHeaderView`, `OFBActionsView`, `FileBrowserOutlineView`, `OFBFinderTagsChooser`,
`FileItemTableCellView`, `FileBrowserView`, `FileItem` (base),
`FileItemMountedVolumes`, `FileItemSCMStatus`, `FileItemObserver`,
`FileBrowserDiskOperations` (a Swift extension on the still-ObjC++ controller).

### What is still ObjC++ (and why)

- **The one port left:** `FileBrowserViewController.mm` (2280 after all four
  extractions, the big one), plus its `FileBrowserViewControllerSupport.{h,mm}`
  (121 lines of .mm), which is ObjC++ **permanently** — that is the point of it.
- **ObjC++ by design (do not "finish" these without reason):**
  - `FSEventsManager.mm`, `SCMManager.mm` — model managers whose C++ boundaries
    were already made Swift-importable (`FSEventStream`, `SCMManagerCxx`). A Swift
    translation is *optional*; they work as-is behind C++-free headers.
  - The `*Support` / `*Cxx` / globals files that hold C++ or exported globals on
    purpose: `FSEventStream.mm`, `SCMManagerCxx.h`, `FileItemLocations.mm`,
    `FileItemSCMStatusSupport.mm`, `FileItemObserverSupport.mm`,
    `FileBrowserDiskOperationsSupport.mm`, `FileBrowserOutlineViewKeyBindings.mm`,
    `FileBrowserNotifications.mm` (the notification-name `extern` consts — rule 19).

## Build, test, run

```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 RUBYOPT="-EUTF-8"
export PATH="$HOME/.gem/ruby/2.6.0/bin:$PATH"
ruby ide/extract_specs.rb > ide/gen/specs.json && ruby ide/seed_xcodeproj.rb   # re-seed after adding/removing files
xcodebuild test -project TextMate.xcodeproj -scheme AllTests -configuration Debug            # full suite
xcodebuild test -project TextMate.xcodeproj -scheme AllTests -configuration Debug -only-testing:FileBrowserTests   # just this framework
xcodebuild -project TextMate.xcodeproj -target TextMate -configuration Release build         # the app
open -a "$PWD/build/Release/TextMate-NG.app" <some-git-repo>                                  # run it
```

Re-seeding is needed when a source file is **added or removed** (a `.mm`→`.swift`
swap counts) **and every time a test file's contents change** — see rule 29.
Editing an existing `src/` file does not need it.

**Run the app, every time (rule 8, and it earned its keep again).** The
FileItemObserver port compiled, passed all 617 tests, and showed an **empty
directory** in the running browser because of a weak/strong ownership flip no test
reached (rule 27 below). Open a git repo with modified/deleted/untracked/staged
files and a Finder tag, and check: the list populates, SCM badges and tag dots
draw, a shell-created file live-reloads, the SCM button shows Uncommitted/Untracked,
Computer shows the host + volumes, and rename selects the basename.

## The last port, specifically

**It has been surveyed and its prep is done** — the full measured checklist is
in `ide/FILEBROWSER_PORT_PLAN.md` under "FileBrowserViewController — the
survey". Four commits landed off the back of it, each judged by the suite on its
own:

- `00a42e07` — `FileBrowserTypes.h` split out (FBOperation + FileBrowserDelegate).
- `8c98956d` — **`+initialize` is gone**, replaced by `+registerDefaults`
  (dispatch_once from the top of `-init`). That was the last structural blocker;
  a Swift class cannot provide `+initialize`.
- `908a82da` — the KVO surface pinned by binding a real NSButton and NSMenuItem,
  so a missing `@objc dynamic` fails a test instead of silently dead bindings.
- `53a7b1e6` — the first C++ extraction (see below), and the only commit in this
  port not verified in the running app.

**The C++ extraction is done. What is left is the translation.** The survey
found the C++ spread across the file rather than pooled in one fragment, so it
came out a cluster at a time while everything was still ObjC++ and the existing
suite judged each move — step 2 of this plan's original order, the shape that
made FSEventsManager and SCMManager tractable. Four commits did it:

- `53a7b1e6` — the settings/glob pair (exclude/include filter, `is_binary`).
- `b4fb22e7` — the action menu. Emptied `-updateMenu:` of C++ entirely.
- `b3ba8abf` — the remaining two `bundles::` uses (new-file extension, command
  runner). After this the controller had no `bundles::` and no settings read.
- `6266b9a8` — `path::device` ×2 and `to_s(NSEvent*)`.

**Re-measure before trusting anything below** (rule 10), and note the grep in
the previous handoff was too narrow — it misses `new`/`delete`:

```bash
grep -n 'std::\|[a-z_]\+::[a-z_]\|\bnew \|delete \[\]' Frameworks/FileBrowser/src/FileBrowserViewController.mm
```

As of `6266b9a8` (2280 lines) every remaining hit is one of two kinds, and
**neither is extraction work**:

| where | what | why it stays |
| --- | --- | --- |
| `-variables` (~1207–1218) | `std::map` return, `path::escape`, `text::join` | Pinned from outside (`DocumentWindowSupport.mm`). Belongs on an ObjC++ category on the Swift class, exactly like `DocumentWindowController`'s four C++-typed selectors. |
| ~34/68, ~820, ~1113, ~1192, ~1498 | `new NSInteger[]`/`delete[]`, `std::set<NSInteger>`, `std::clamp` ×2, `std::vector<std::pair<BOOL, FileItem*>>` | Local scratch with no C++ dependency — translates straight to Swift when its method does. Do **not** build a support method for these. |

So the next session starts the translation itself, split by section rather than
in one commit, with an app run after each.

### What the support class now holds, and one thing about it that is permanent

`FileBrowserViewControllerSupport` has seven class methods: the glob predicate,
`isBinaryURL:`, `actionMenuItemsWithAction:`,
`executeBundleCommandWithUUIDString:firstResponder:`,
`pathExtensionForNewFileInDirectoryURL:`, `deviceForPath:`/`deviceForURL:`, and
`eventStringForEvent:`.

**`-executeBundleCommand:` can never be Swift**, and the survey did not catch
this. It is not that `bundles::item_ptr` is awkward to carry (rule 20) — it is
that the *callee* is C++-typed on both sides: `OakCommand`'s
`-initWithBundleCommand:` takes a `bundle_command_t const&` and
`-executeWithInput:variables:outputHandler:` a `std::map`. Wherever the
controller ends up, that call is made from ObjC++. It lives in the support
class now; when the controller becomes Swift it stays there unchanged.

- **`FileBrowserViewController.mm` (2280).** Its known hazards, updated by what
  the DiskOperations port and the survey measured:
  - **The rule-21 cascade is real but smaller than the survey thought, and its
    structural half is now done.** Three of the fears are settled facts rather
    than risks: a `@class FileItem` forward declaration unifies with the Swift
    FileItem instead of colliding, the C++-typed `-variables` is dropped by the
    importer, and every type the Swift needs out of that header has been split
    into exported companions — `FileBrowserTypes.h` (FBOperation +
    FileBrowserDelegate), `FileBrowserNotifications.h` (the notification consts),
    `FileBrowserDiskOperations.h` (the category declaration). So when **Swift
    defines the class**, the bridging header change is deleting its one
    `#import "FileBrowserViewController.h"` line. `DocumentWindow`'s bridging
    header keeps importing `<FileBrowser/FileBrowserViewController.h>` — it does
    not define the class, and that hand-decl is what keeps its *Swift* compiling
    (see the survey's cross-module note).
  - **DiskOperations is already a Swift extension on this class**, so when the
    controller becomes Swift the extension needs nothing except that its
    `@objc(...)` selector spellings stay — and `FileBrowserDiskOperations.h` can
    then be deleted outright, since ObjC++ will no longer be calling in.
  - **`-presentError:` lives in `FileBrowserDiskOperationsSupport.mm`** only
    because a Swift *extension* cannot override an inherited method (rule 31).
    Once Swift defines the class itself, that override can move into the class
    body and the support category disappears; the `path::` half stays.
  - **`- (std::map<std::string,std::string>)variables` is pinned from outside**
    (`DocumentWindowSupport.mm:356`). It cannot change shape — it belongs on an
    ObjC++ category on the Swift class, exactly like `DocumentWindowController`'s
    four C++-typed selectors. The selector-surface test already lists it.
  - It is a `<QLPreviewPanelDataSource>` and holds the history/undo state; survey
    its bindings (`grep 'bind:\|addObserver:.*forKeyPath:\|keyPathsForValuesAffecting'`)
    before porting and make every observed property `@objc dynamic` (rule 1).

## Rules earned this session (continuing FIND_PORT_HANDOFF's list at 23)

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
    (`OakCreateActionPopUpButton(false)`); and `…AtURL:`/`…ForURL:` selectors trim
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

## One build gotcha that is not a code error

Ad-hoc CodeSign of **unrelated** test bundles sometimes fails with
`invalid or unsupported format for signature` on a leftover `.cstemp` after many
incremental `xcodebuild test` runs. Clear it and re-run — do not go looking for a
code cause:

```bash
DD=/Users/jmcgovern/Library/Developer/Xcode/DerivedData/TextMate-foaewfrsjpmklbgasgjrtfprpoyn
find "$DD/Build/Products" -name '*.cstemp' -delete
xattr -cr "$DD/Build/Products/Debug"
```

## One environment note, not about the code either

Screen capture (and the accessibility API with it) stopped responding on this
machine mid-session once — `screenshot` returned "permission missing or
SCContentFilter failure" and System Events could not see the app's windows,
while the app itself was running fine. **It was transient**: capture worked
normally the following session with no intervention, which is how `53a7b1e6`'s
outstanding check got done. If it happens again, rule 8 still applies: the run
cannot be skipped, it just has to be done by a human looking at the screen. Say
so in the commit message when it is not done, as `53a7b1e6` did, and do not
stack work on top of the unverified commit.

Two smaller things about driving the app that cost time this session:

- **A synthetic drag needs to be slow and finely stepped.** A press, three
  moves and a release highlights the drop row but the drop does not happen —
  the file stays put and it reads as "validateDrop: rejected it". Eight or so
  moves with a pause before the release completes it. Check the *disk*, not the
  outline view, before believing either result.
- **Quitting can hang on an unsaved untitled document** left over from testing
  New File. `osascript … to quit` blocks on the save sheet with no output; look
  at the screen rather than assuming the app is wedged.
