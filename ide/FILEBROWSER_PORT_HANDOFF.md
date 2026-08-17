# FileBrowser port — handoff

_Written 2026-08-15, rewritten 2026-08-16 at the end of the session that took
the controller from 2280 lines to 1410 by peeling eight sections into Swift
extensions across seven commits — which is **every section that can be
peeled**; see "Why nothing else can peel" below. The C++ extraction was
finished the session before. **Both preparatory phases are over: the only work
left in this framework is the flip**, and it has its own section below._

_Re-measured and de-staled 2026-08-17 against `11c5e1da` — every count and line
number below was checked against the tree on that date, not carried forward.
The per-commit detail and the reasoning behind each decision live in
`ide/FILEBROWSER_PORT_PLAN.md`, and the 22 cross-framework rules that predate
this work are at the end of `ide/FIND_PORT_HANDOFF.md`. Read those two first._

## State you are starting from

- `master`, tree clean. The peel ends at **`61ebc55f`**; anything after it is
  documentation, so cite that rather than a HEAD hash a doc commit will stale.
- **Nothing is pushed, and it is not just this work.** The remote is
  `GH-johnmcgovern` (there is no `origin` — a `git log origin/master..master`
  silently reports nothing and reads as "all pushed"). `master` was **51 commits
  ahead** of `GH-johnmcgovern/master` at `11c5e1da`, and that reaches back well
  before this port. The number grows with every commit including doc ones, so
  read it off `git branch -vv` rather than from this line, and do not push
  without asking.
- **645 tests across 36 bundles, green**, of which FileBrowser's bundle is
  **44**. Measured at `d680bbe5`, not carried forward: this line said 643 until
  the count was actually run, which is rule 10 happening again in the same
  document that states it. Re-measure, never increment:
  ```bash
  grep -c "^Test Case .*' passed" <log>   # after a full `xcodebuild test`, and do not `tail` the log away
  ```
  FileBrowser has **10** test files (`Frameworks/FileBrowser/tests/t_*.mm`); the
  framework had **zero** before this port began.
- **One commit was not verified in the app, and it shipped a crash.** This line
  used to read "nothing is unverified". `61ebc55f` collapsed folders by sending
  -removeObject: to an immutable NSSet (rule 46), and what let it through is
  simple: there was no Release build on this machine newer than that commit. So
  the check is not "did I mean to run the app" — it is **`stat` the binary
  against the commit**:
  ```bash
  stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' build/Release/TextMate-NG.app/Contents/MacOS/TextMate-NG
  git log -1 --format=%ad --date=iso HEAD
  ```
  Everything else was checked in the running app, and where a path could not be
  reached from the tools (a modifier held across a synthetic drag, a drop on the
  Dock's Trash) the commit says so rather than implying coverage.
- **Known, unfixed, and not from the port's own work:** in the SCM data source
  (⇧⌘Y) the two group rows draw their disclosure triangle but no title text —
  they should read "Uncommitted Changes" and "Untracked Items". Ruled out: the
  table-cell peel (the pre-peel ObjC++ had no group-row case either) and
  `SCMStatusFileItem.localizedName`, which returns the right strings. Likely in
  how a group row's cell gets its text through
  `objectValue.editingAndDisplayName`.
- The **first thing settled** was the survey's open question: `FileBrowserViewController`
  **is** constructible in a test process. So this framework's coverage can use
  instances.
- `FileBrowserViewController.mm` is **1410 lines, 75 methods**, down from 2280
  and ~134. Nothing further can leave it before the flip.

### How this port is being done — read this before writing any code

A class cannot be half-translated: its *definition* flips from ObjC++ to Swift
in one commit. But its **methods** can leave a section at a time, as Swift
extensions on the still-ObjC++ class — which is what `FileBrowserDiskOperations`
already was, and what eight more sections did this session. Each peel was its
own commit, judged by the suite *and* an app run before the next one started.

That has already paid for itself twice over: the first peel crashed the test
process on a nil root (rule 33) and the last one put `Optional("committed.txt")`
into the context menu (rule 44). Both were one suspect in a 60-line commit
rather than one of hundreds of new lines in a class-wide flip.

**Three headers, three different jobs. Confusing them is the main way to lose
an hour here:**

| header | who imports it | may declare |
| --- | --- | --- |
| `FileBrowserViewControllerInternal.h` | the **bridging header** | private state and methods **ObjC still implements** — readonly properties, and ObjC++ methods Swift calls. **Never** anything Swift defines, and **never a protocol conformance** (rule 42). |
| `FileBrowserActions.h` | the **.mm only** | methods **Swift defines** that the ObjC++ still names by `@selector`. Never goes in the bridging header (rule 43). |
| `FileBrowserViewControllerSupport.h` | the bridging header | the permanent ObjC++ C++ boundary — unchanged by the peel. |

Both temporary headers disappear at the flip. If either survives it, something
was missed.

### What is already Swift

**Whole classes** — the entire view layer and the whole `FileItem*` model
family:

`OFBHeaderView`, `OFBActionsView`, `FileBrowserOutlineView`, `OFBFinderTagsChooser`,
`FileItemTableCellView`, `FileBrowserView`, `FileItem` (base),
`FileItemMountedVolumes`, `FileItemSCMStatus`, `FileItemObserver`.

**Nine sections of the controller**, as Swift extensions on the class while it
is still ObjC++ — `FileBrowserDiskOperations` from the earlier session, the
other eight from the peel:

`FileBrowserDiskOperations`, `FileBrowserOutlineViewDataSource`,
`FileBrowserTableCells`, `FileBrowserAcceptDrop`, `FileBrowserActions`,
`FileBrowserPasteboard`, `FileBrowserMenuValidation`, `FileBrowserQuickLook`,
`FileBrowserLoading`.

```bash
grep -l 'extension FileBrowserViewController' Frameworks/FileBrowser/src/*.swift   # the check for the second list
```

### What is still ObjC++ (and why)

- **The one port left:** `FileBrowserViewController.mm` (1410), plus its
  `FileBrowserViewControllerSupport.{h,mm}`, which is ObjC++ **permanently** —
  that is the point of it. Two of the controller's own methods are permanent
  ObjC++ too and become a category on the Swift class at the flip:
  `-variables` and `-updateMenu:`.
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

**Surveyed, prepped, peeled, and extracted. What is left is the translation
itself**: `FileBrowserViewController.mm` (1410 lines, 75 methods) becomes
`FileBrowserViewController.swift`, in the one commit that flips the class
definition. **The step-by-step for that commit is under "The flip" below**;
this section and the next are the record of how the file reached this state and
why nothing more can be done to it first.

### The prep, and why each commit happened

The full measured checklist is in `ide/FILEBROWSER_PORT_PLAN.md` under
"FileBrowserViewController — the survey". Four commits landed off the back of
it, each judged by the suite on its own:

- `00a42e07` — `FileBrowserTypes.h` split out (FBOperation + FileBrowserDelegate).
- `8c98956d` — **`+initialize` is gone**, replaced by `+registerDefaults`
  (dispatch_once from the top of `-init`). That was the last structural blocker;
  a Swift class cannot provide `+initialize`.
- `908a82da` — the KVO surface pinned by binding a real NSButton and NSMenuItem,
  so a missing `@objc dynamic` fails a test instead of silently dead bindings.
- `53a7b1e6` — the first C++ extraction (see below), and the only commit in this
  port not verified in the running app.

### The C++ extraction, and the one thing it did not get

The survey found the C++ spread across the file rather than pooled in one
fragment, so it came out a cluster at a time while everything was still ObjC++
and the existing suite judged each move — step 2 of this plan's original order,
the shape that made FSEventsManager and SCMManager tractable. Four commits did
it:

- `53a7b1e6` — the settings/glob pair (exclude/include filter, `is_binary`).
- `b4fb22e7` — the action menu's bundle items. **This commit's message says it
  "emptied `-updateMenu:` of C++ entirely" and that is wrong** — it removed the
  `bundles::` half; the `MBMenu` literal was there the whole time and is
  invisible to the grep that was used to check. See below.
- `b3ba8abf` — the remaining two `bundles::` uses (new-file extension, command
  runner). After this the controller had no `bundles::` and no settings read.
- `6266b9a8` — `path::device` ×2 and `to_s(NSEvent*)`.

**Re-measure before trusting anything below** (rule 10). The grep in the
handoff before this one was too narrow twice over — it misses `new`/`delete`,
and it misses a typedef'd C++ type such as `MBMenu` (see `-updateMenu:` below).
This is the widened form:

```bash
grep -n 'std::\|[a-z_]\+::[a-z_]\|\bnew \|delete \[\]\|MBMenu\|MBCreateMenu' Frameworks/FileBrowser/src/FileBrowserViewController.mm
```

Re-run at `11c5e1da` (1410 lines) it returns eleven hits in four groups. **None
of them is extraction work**, and only the first two survive the flip as ObjC++:

| where | what | what happens to it |
| --- | --- | --- |
| `-variables` (777–788) | `std::map` return, `std::vector`, `path::escape`, `text::join` | **Stays ObjC++.** Pinned from outside (`DocumentWindowSupport.mm:356`), so it cannot change shape. Becomes an ObjC++ category on the Swift class, exactly like `DocumentWindowController`'s four C++-typed selectors. |
| `-updateMenu:` (507–541) | `MBMenu const items = { … }`, `MBCreateMenu` | **Stays ObjC++**, same category. See the paragraph below — this one was missed by the original inventory. |
| `MutableLongestCommonSubsequence` (36, 70) | `new NSInteger[]` / `delete []` | File-scope static C helper. Translates to a Swift array — no C++ dependency, no support method. |
| 683, 762, 1068 | `std::clamp` ×2, `std::vector<std::pair<BOOL, FileItem*>>` | Local scratch inside `-restoreStateWithCoder:`, `-setupViewWithState:` and `-rearrangeChildrenInParent:`. Translates straight to Swift with its method. Do **not** build a support method for these. |

The `std::set<NSInteger>` the earlier inventory listed is already gone — it left
with the action methods in `8cb0d7d5`, and `FileBrowserActions.swift:131` notes
where it was.

## Why nothing else can peel (the record, not a to-do)

The section survey in the plan sorted methods by ivars, overrides and accessors.
**It missed a fourth blocker and so its "84 eligible" is optimistic** — see rule
41. This table is the corrected picture, re-measure it rather than trusting the
numbers:

| section | can move now | blocked | by what |
| --- | --- | --- | --- |
| ~~QuickLook~~ | done | — | `6162472b` |
| ~~Loading/Expanding Items~~ | done | — | `61ebc55f` |
| **Action Menu** (`-updateMenu:`) | — | 2 | **C++** — see below. Not peelable; this row said "eligible" and was wrong. |
| History / Location / `From FileBrowserView` | — | ~19 | **accessors** for declared properties: a Swift extension cannot supply storage or its accessors |
| Public-header actions (`newFile:`, `newFolder:`, `goToURL:`, `reload:`, …) | — | ~20 | **header visibility** (rule 41) |
| `-init`, `-dealloc`, `-loadView`, `-scrollWheel:`, restorable state, `-undoManager`, `-validRequestorForSendType:` | — | 8 | **overrides** (rule 31) |
| `-variables` | — | 1 | C++ signature pinned from `DocumentWindowSupport.mm` |

So: **the peel is finished.** Everything left in the `.mm` is one of five
blocked kinds, none of which can leave before the class definition flips.

**`-updateMenu:` is C++, and the C++ inventory missed it.** Line ~507 is
`MBMenu const items = { … }`, and MenuBuilder declares
`typedef std::vector<MBMenuItem> MBMenu` — a std::vector, built with C++
designated-initialiser aggregate syntax, with `NSMenuItem* __strong* ref`
members. The grep recorded above finds none of it, because neither `MBMenu` nor
`MBCreateMenu` contains `std::` or `::`. **Widen the grep before trusting any
"no C++ left" claim**: a typedef'd C++ type is invisible to it, and so is
`new`/`delete`.

There is no ObjC-shaped MenuBuilder API to use instead, so -updateMenu: joins
-variables and the support class in the permanent-ObjC++ bucket: at the flip it
becomes a category on the Swift class. Extracting just the MBMenu literal so the
other ~40 lines could be Swift was considered and rejected — it buys an
`NSMenuItem**` out-parameter boundary for code that needs an ObjC++ neighbour
either way.

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

## The flip — what the next commit actually has to do

The one remaining port. `FileBrowserViewController.mm` (1410 lines, 75 methods)
becomes `FileBrowserViewController.swift`, minus the two methods that stay
ObjC++. Everything below was settled by the prep; none of it is open.

**The file moves:**

1. **Swift defines the class.** `FileBrowserViewController.h` becomes a
   hand-written ObjC declaration of it (rule 23) and **leaves the bridging
   header** — that one `#import "FileBrowserViewController.h"` line is the only
   bridging-header change, because every type the Swift needs was already split
   into exported companions: `FileBrowserTypes.h` (FBOperation +
   FileBrowserDelegate), `FileBrowserNotifications.h` (the notification consts),
   `FileBrowserDiskOperations.h` (the category declaration).
2. **The two temporary headers are deleted**: `FileBrowserActions.h` and
   `FileBrowserViewControllerInternal.h`. Their contents become ordinary private
   state and methods in the Swift class. **If either survives the flip,
   something was missed.**
3. **`FileBrowserDiskOperations.h` is deleted** too — ObjC++ will no longer be
   calling into the category. The extension itself needs nothing except that its
   `@objc(...)` selector spellings stay.
4. **`-presentError:` moves into the class body** from
   `FileBrowserDiskOperationsSupport.mm`; rule 31 stops applying once Swift
   defines the class. The `path::` half of that support file stays.
5. **`-variables` and `-updateMenu:` become an ObjC++ category on the Swift
   class** — the `DocumentWindowController` arrangement, which already carries
   four C++-typed selectors this way. The selector-surface test already lists
   `-variables`.
6. **Re-seed** (`.mm`→`.swift` is an add plus a remove — rule 29).

**What does not change, and is worth knowing before you go looking:**
`DocumentWindow`'s bridging header keeps importing
`<FileBrowser/FileBrowserViewController.h>`. It does not define the class, and
that hand-decl is what keeps its *Swift* compiling (see the survey's
cross-module note).

**The hazards specific to this class**, as measured rather than feared:

- **The rule-21 cascade is real but smaller than the survey thought, and its
  structural half is already done.** Three of the fears are settled facts: a
  `@class FileItem` forward declaration unifies with the Swift FileItem instead
  of colliding, the C++-typed `-variables` is dropped by the importer, and the
  header split above is finished.
- **It is a `<QLPreviewPanelDataSource>` and holds the history/undo state.**
  Survey its bindings before porting and make every observed property
  `@objc dynamic` (rule 1) — a missed one is a silently dead binding:
  ```bash
  grep -n 'bind:\|addObserver:.*forKeyPath:\|keyPathsForValuesAffecting' Frameworks/FileBrowser/src/FileBrowserViewController.mm
  ```
  `908a82da` already pinned part of this surface with a real NSButton and
  NSMenuItem, so a missing `@objc dynamic` on `canGoBack`/`canGoForward` fails a
  test rather than going quiet.
- **Nine ivars are now properties** (`2b34881a`) and the class extension at
  `FileBrowserViewController.mm:75–126` is the full inventory of private state
  the Swift class has to carry. Copy each one's ownership across unchanged —
  rule 27, and a flip is not the moment to reconsider a weak/strong choice.
- **Two of those properties have hand-written getters that mean something other
  than their storage**, and the flip is where that stops being a hazard.
  `expandedURLs` / `selectedURLs` are declared `NSMutableSet*` and their getters
  return an immutable merge of the ivar with the outline view's current state.
  In Swift the pending sets become plain private storage and the merged pair
  become two computed properties under names of their own — do **not** give the
  stored and computed halves the same name again. Rule 46; it already cost a
  shipped crash once (`d680bbe5`), and the `pendingExpandedURLs` /
  `pendingSelectedURLs` passthroughs that fixed it exist only to be deleted here.
- **Read nullability before translating each line that uses a value** (rule 44).
  This is the failure mode that stays green: the peel produced both a literal
  `Optional("committed.txt")` in a menu title and a force-unwrap trap, with the
  whole suite passing.
- **Eight methods are overrides** (`-init`, `-dealloc`, `-loadView`,
  `-scrollWheel:`, the restorable-state pair, `-undoManager`,
  `-validRequestorForSendType:`). They were blocked from peeling by rule 31 and
  are the part of this file that has had the least prior exposure — they get
  translated for the first time here.

**Verification, and it is not optional.** The suite is the floor, not the check
(rule 8): run the app against a git repo with modified/deleted/untracked/staged
files and a Finder tag, and walk the list in "Build, test, run" above. This is
one large commit with no intermediate judgement available — unlike every peel,
which was one suspect in sixty lines — so the app run is the only thing standing
between a green suite and an empty directory (rule 27).

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
while the app itself was running fine. **It is intermittent, not a one-off**: it
cleared with no intervention, came back mid-session on 2026-08-16, and cleared
again. Do not spend time diagnosing it. When it happens rule 8 still applies —
the run cannot be skipped, it just has to be done by a human looking at the
screen, and `30a3e668` was verified exactly that way. Say so in the commit
message, and do not stack work on top of an unverified commit.

Five smaller things about driving the app, each of which cost time:

- **`open -a` on a running app does not relaunch it.** It activates the existing
  instance, so you verify the *old* binary and conclude your fix did not work.
  Quit first, confirm with `pgrep`, then open. This wasted a full cycle on the
  `Optional(…)` fix, which was already correct.
- **The app cannot quit while a context menu or field editor is open**, and
  `osascript … to quit` reports nothing while it waits. Escape does not always
  dismiss a field editor either; clicking another row commits the edit, which
  for a rename means renaming to whatever is in the field.
- **A second click on an already-selected row starts a rename**, so a
  click-then-⌘C sequence can send the keystroke to a field editor instead of the
  browser. Watch what has focus before sending keys.
- **Some overlay apps intercept clicks** (Grammarly did, on the disclosure
  triangle). Drive the outline view from the keyboard — left/right arrows
  collapse and expand — when a click is refused.

Two more, from the drag work:

- **A synthetic drag needs to be slow and finely stepped.** A press, three
  moves and a release highlights the drop row but the drop does not happen —
  the file stays put and it reads as "validateDrop: rejected it". Eight or so
  moves with a pause before the release completes it. Check the *disk*, not the
  outline view, before believing either result.
- **Quitting can hang on an unsaved untitled document** left over from testing
  New File. `osascript … to quit` blocks on the save sheet with no output; look
  at the screen rather than assuming the app is wedged.
