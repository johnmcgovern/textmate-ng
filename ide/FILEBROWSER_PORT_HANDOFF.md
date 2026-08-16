# FileBrowser port — handoff

_Written 2026-08-15, rewritten at the end of the session that finished the view
layer (`FileBrowserView`), ported `FileBrowserDiskOperations`, and did all the
prep for the one file left. This is the starting point for a fresh session; the
per-commit detail and the reasoning behind each decision live in
`ide/FILEBROWSER_PORT_PLAN.md`, and the 22 cross-framework rules that predate
this work are at the end of `ide/FIND_PORT_HANDOFF.md`. Read those two first.
Everything below was measured, not assumed._

## State you are starting from

- `master`, HEAD `53a7b1e6`, tree clean.
- **634 tests across 36 bundles, green.** Re-measure, never increment — that
  figure has been wrong in these docs before (rule 10). FileBrowser has **10** test
  files (`Frameworks/FileBrowser/tests/t_*.mm`); the framework had **zero** before
  this port began.

> **Do this first.** `53a7b1e6` (the settings/glob extraction) is the one commit
> in this whole port that was **not** verified in the running app: screen capture
> and the accessibility API both stopped responding on this machine partway
> through the session, so the visual half of rule 8 could not be done. The suite
> is green and the extracted logic gained direct tests, but nobody has *seen* the
> browser since. Open the app on a git repo and check the list populates, `.git`
> stays hidden, and **View → Show Invisibles** reveals it — that is exactly the
> code path `53a7b1e6` moved. If capture is still broken, look at the screen
> yourself; do not stack more commits on an unverified one.
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

- **The one port left:** `FileBrowserViewController.mm` (2329, the big one).
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

**What is left is the C++ extraction, then the translation.** The survey found
the C++ spread across the file rather than pooled in one fragment, so it comes
out a cluster at a time while everything is still ObjC++ and the existing suite
judges each move — step 2 of this plan's original order, the shape that made
FSEventsManager and SCMManager tractable.

`53a7b1e6` did the first one (the two settings-driven fragments: the exclude/
include glob filter and `is_binary`, now
`FileBrowserViewControllerSupport.{h,mm}`). **Re-measure before trusting this
list** (rule 10) — line numbers move as each extraction lands:

```bash
grep -n 'std::\|[a-z_]\+::[a-z_]' Frameworks/FileBrowser/src/FileBrowserViewController.mm
```

As of `53a7b1e6` (2303 lines), what is left, by the method it lives in:

| where | lines | what |
| --- | --- | --- |
| `-updateMenu:` | 534, 586–587 | `std::map<SEL, std::string>` inactive key-equivalents table, **and** `std::multimap<std::string, bundles::item_ptr, text::less_t>` + `bundles::query` for the action-menu items |
| `-newFile:` | 666–669 | `settings_for_path` for the untitled file type, then `bundles::query` for its grammar extension |
| `-executeBundleCommand:` | 753 | `bundles::lookup` on the sender's represented object |
| `-previewPanel:handleEvent:` | 2179 | `to_s(NSEvent*)` for the key-equivalent string |
| `-outlineView:validateDrop:…` | 2222, 2229 | `path::device` twice — same-device decides copy vs move |
| `-variables` | 1230–1241 | `std::map` return, `path::escape`, `text::join` |
| — | 843, 1136, 1215, 1521 | `std::set<NSInteger>`, `std::clamp` ×2, `std::vector<std::pair<BOOL, FileItem*>>` |

Three notes on that table:

- **`bundles::item_ptr` is the rule-20 blocker**, and it appears in three
  separate methods. It cannot cross into Swift; each use needs an ObjC-shaped
  boundary (return the resolved `NSMenuItem`s / the extension string / run the
  command), not a translated one.
- **The last row is not extraction work** — `std::clamp`, `std::set<NSInteger>`
  and the `std::vector<std::pair<…>>` are local scratch with no C++ dependency,
  so they translate straight to Swift when their method does. Do not build a
  support method for them.
- **`-variables` is the exception that stays.** It is pinned from outside
  (`DocumentWindowSupport.mm:353`), so it belongs on an ObjC++ category on the
  Swift class — exactly like `DocumentWindowController`'s four C++-typed
  selectors — rather than moving into the support class.

Only after that is the translation itself worth starting, split by section
rather than in one commit, with an app run after each.

- **`FileBrowserViewController.mm` (2329).** Its known hazards, updated by what
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
machine mid-session — `screenshot` returned "permission missing or
SCContentFilter failure" and System Events could not see the app's windows,
while the app itself was running fine. If that happens again, rule 8 still
applies: the run cannot be skipped, it just has to be done by a human looking at
the screen. Say so in the commit message when it is not done, as `53a7b1e6`
does, and do not stack work on top of the unverified commit.
