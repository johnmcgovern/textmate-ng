# FileBrowser port — the survey, before any code

_Written 2026-08-13 at the end of the session that shipped alpha.10, so a fresh
session can start on FileBrowser without re-deriving the survey. Everything here
was measured, not assumed; where it says "not established", it means nobody has
checked yet, and you should._

Start by reading **the numbered rules at the end of `ide/FIND_PORT_HANDOFF.md`**.
There are 22 and 8 of them were earned by something that compiled, passed its
tests, and was still wrong. The survey below is that checklist applied once.

## Progress — 2026-08-14 (steps 1 and 2 of "Suggested order" done)

Three commits landed on `master`, suite green at **605** (the re-measured 601
baseline + this framework's first 4 tests), and **verified in the running app**
against a git fixture: SCM badges (deleted/modified/added/untracked), the
`git: <branch>` window title, and live FSEvents reload of a shell-created file
all work. What no test reaches (rule 8) was checked by hand, not assumed.

- `fc92d03f` — **tests stood up, constructibility settled.** The open question
  is answered: **`FileBrowserViewController` IS constructible in a test process**
  (`-init` is light; the view and the C++ cell machinery build lazily in
  `-loadView`). So this framework's coverage can use instances. The commit also
  pins rule 18's selector surface and adds the missing `tests tests/t_*.mm` line
  to `default.rave`. Test file: `tests/t_file_browser_view_controller.mm`.
- `3f6bcc0c` — **FSEventStream extracted.** The `std::shared_ptr<fs_events_t>`
  ivar is gone from `FSEventsManager.mm` (now C++-free); the struct moved verbatim
  into a new ObjC++ `FSEventStream` class the manager holds by pointer. DWScope-
  Context treatment, done. FSEventsManager itself is now Swift-portable.
- `d3619687` — **SCMManager.h is C++-free.** The `std::map` `status` property and
  the rule-15 `scm::status::type` block method moved to a new `SCMManagerCxx.h`
  category (the DWScopeContextCxx split); `FileItemObserver.mm` /
  `FileItemSCMStatus.mm` gained the one Cxx import and are otherwise untouched.
  Note found in passing: **`-addObserverToFileAtURL:usingBlock:` has zero callers
  anywhere** — a later cleanup can just delete it.

- `87048ee9` — **OFBHeaderView ported to Swift: the framework's first `.swift`,
  and the build wiring is now stood up.** Chosen as the trailblazer because it is
  one of the simplest classes (a code-built NSVisualEffectView, no logic), so the
  port risked only the wiring. Verified in the app — the header renders and the
  folder pop-up populates, i.e. the full ObjC++→Swift round trip works. What the
  next leaf inherits, all now proven:
  - `default.rave` has `swift` in both source globs.
  - `src/FileBrowser-Bridging-Header.h` exists (prelude.cc + Cocoa + OakAppKit +
    OakUIConstructionFunctions). Add to it what each new Swift file needs from ObjC.
  - **No module/class-name collision** (no class is named `FileBrowser`), so the
    framework's ObjC++ *could* `#import "FileBrowser-Swift.h"` directly like
    OakAppKit does. This port chose the other arrangement instead — keep each
    ported class's `.h` as a hand-written ObjC declaration (the
    DocumentWindowController.h pattern) — for zero consumer churn and so tests can
    import it. Either works; be consistent and never let the bridging header reach
    a hand-decl `.h`.
  - Gotcha paid: unannotated C globals import to Swift as returning **optional**
    (`OakCreateNSBoxSeparator()` is `NSView?`) — force-unwrap, as
    `SelectGrammarViewController.swift` does.

- `9e58f0a2` — **OFBActionsView ported.** The twin of OFBHeaderView. Two Swift-
  importer facts it paid: a **C++ default argument is not imported**, so
  `OakCreateActionPopUpButton(false)` passes it; a **factory-style class method
  imports as an initializer**, so it is `NSImage(named:inSameBundleAsClass:)`, not
  `imageNamed(_:...)`. Bridging header gained `<OakAppKit/NSImage Additions.h>`.

- `c151b20b` — **FileBrowserOutlineView ported: the first leaf with real
  structure.** Three things beyond the code-built views, each likely to recur:
  - **Rule 11 header split.** Its header declared both the class and the
    `FileBrowserOutlineViewDelegate` protocol; the protocol moved to its own
    header (bridging-header-importable), re-exported from the class's hand-decl
    header so consumers are unchanged.
  - **Nominal vs structural delegates.** The ObjC++ forwarded via
    `-respondsToSelector:`; Swift's `as? Protocol` is nominal, so the delegate
    (FileBrowserViewController) had to *declare* `<FileBrowserOutlineViewDelegate>`
    (it already implemented all five methods). **Watch for this on every ported
    view whose ObjC++ delegate never declared conformance.**
  - **C++ in a method body** (the `performKeyEquivalent:` key table) → moved
    verbatim (rule 6) to an ObjC++ helper returning the matched SEL; the Swift
    override keeps the send/super control flow. Two more API renames surfaced:
    `rectOfRow` → `rect(ofRow:)`, `makeKeyWindow()` → `makeKey()`.

- `14fcec1a` — **OFBFinderTagsChooser ported** (241 lines, the biggest leaf, but
  no C++). Its private `OFBFinderTagImage : NSImage` was a subclass whose only
  method was a factory returning a plain `NSImage`, so it collapsed to a private
  drawing func. Bridging header gained `OakFinderTag.h` + `OakRolloverButton.h`;
  the latter's `extern NSNotificationName` globals are **referenced** from Swift
  (allowed — rule 19 forbids exporting, not calling) with the importer's
  suffix-strip: `.OakRolloverButtonMouseDidEnter` / `…DidLeave`. Verified in the
  app: swatches draw in the action menu, hover draws the + and updates the caption.

- `9c888b52` — **FileItemTableCellView ported: the first bindings-heavy leaf.**
  Rule 1 in practice: the row's bindings observe key paths rooted at
  `fileReference` (`fileReference.icon`, `fileReference.closable`) and the view
  sets that property from `-observeValue`, so `fileReference` is **`@objc
  dynamic`** — without it the Swift write skips the KVO swizzle and the icon/close
  button never update. Everything else hung off `objectValue` (a FileItem, still
  ObjC) so needed nothing. The `FileItem (FileItemWrapper)` category
  (`editingAndDisplayName` + its dependent keys) stayed ObjC++ as
  `FileItemEditingName` — it belongs to FileItem and the binding needs FileItem
  itself to publish the key; it folds in when FileItem ports. Two facts paid:
  OakCreateLabel/OakCreateCloseButton **C++ default args aren't imported** (pass
  them all), and a **@MainActor class can't touch its state from a nonisolated
  `deinit`** under Swift 6 → binding teardown runs in `MainActor.assumeIsolated`
  (an NSView always deallocs on the main thread). Verified in the app: icons +
  SCM badges render, a Finder tag draws its dot, and rename selects the basename.

- `2a8d36fb` — **Prep: FileItem +load registration replaced with explicit
  registration.** The `FileItem*` family is a URL-scheme→class registry
  (`file`→FileItem, `computer`→MountedVolumesFileItem, `scm`→SCMStatusFileItem),
  and each class registered itself from `+load` — which Swift never runs. So the
  registry is now `+[FileItem registerBuiltinClasses]` (dispatch_once, from
  `+classForURL:`, using NSClassFromString so no shared header is needed; `-ObjC`
  keeps the classes linked). Still ObjC++; verified all three schemes in the app.
  This unblocks porting the family — but see the two further blockers below,
  found while surveying, before starting.

**What is left, in the plan's order:** step 3, the `FileItem*` family, then
`FileBrowserDiskOperations` (530); step 4, `FileBrowserViewController.mm` (2328)
last. (Both of step 3's halves are done as of `53638c07`; only
`FileBrowserDiskOperations` and the controller remain.)

**Before porting `FileItem` itself, two blockers beyond `+load` (now cleared):**
1. **Rule 19 — exported globals.** `FileItem.h` declares
   `extern NSURL* const kURLLocationComputer` / `…Favorites`, defined in
   `FileItem.mm` and used by `FileBrowserViewController.mm`. Swift cannot *export*
   a global, so these must move to a small ObjC++ file (a `FileItemLocations`
   forwarder) that stays ObjC++, before FileItem becomes Swift.
2. **Rule 11 — header split + the bridging-header entanglement.** `FileItem.h` is
   currently pulled into the Swift bridging header (via `FileItemEditingName.h`,
   which is a category on FileItem). Once Swift *defines* FileItem, the bridging
   header must not see `FileItem.h`; anything the Swift needs from it (the globals
   above, `OakFinderTag`) splits out, and `FileItemEditingName` folds into
   `FileItem.swift`. This is the Find.h→FindTypes.h split, one level deeper.

- `c9dd10c7` — **FileItem base class ported to Swift.** Both blockers cleared:
  the kURLLocation* globals moved to `FileItemLocations` (ObjC++, rule 19; Swift
  only reads them), and `FileItem.h` is now a hand-decl kept out of the bridging
  header (rule 11), with the `FileItemWrapper` category folded in as
  `editingAndDisplayName`. Rule 1 throughout (the row cell binds to displayName /
  canRename / toolTip / finderTags), and the seven `getter=is/has` booleans keep
  their exact ObjC spellings via rule 4 because consumers reach them by property
  name (`item.hidden`, `item.missing`). The scheme-registry static is
  `nonisolated(unsafe)` (matching the ObjC++ main-thread-only contract). The two
  ObjC++ subclasses still inherit the Swift class and override -initWithURL: /
  -localizedName / -parentURL. Verified all three schemes in the app.

- `ff399eba` — **FileItemMountedVolumes ported** (the "computer" data source).
  C++-free; the first Swift subclass of the Swift FileItem. `makeObserverForURL:`
  was a fresh @objc class method at this point (see below).

- `2a371fbc` — **FileItemSCMStatus ported** (the "scm" data source), first `-Cxx`
  split of a model file: the scm-map walk (unstaged/untracked URL computation)
  moved verbatim to ObjC++ `FileItemSCMStatusSupport`; SCMStatusFileItem +
  SCMStatusObserver are Swift on the C++-free SCMManager API. Importer names that
  took iterating: `repositoryAtURL:` → `repository(at:)`, but
  `addObserverToRepositoryAtURL:usingBlock:` → `addObserverToRepository(at:usingBlock:)`
  (base kept, only trailing URL dropped), `+unstagedURLsInRepository:` →
  `unstagedURLs(in:)`, and `SCMRepository.URL` reads as `.url`.

- `4c9760ab` — **FileItemObserver ported: the last C++ model file.** The C++
  deleted-files walk moved to `FileItemObserverSupport`; the observer classes are
  Swift. Two bugs it cost, both worth remembering:
  1. **Swift 6 off-main dispatch.** A nonisolated class can't hop to a background
     queue and back while touching non-Sendable `self`. The fix that finally
     worked: mark the observer classes `@MainActor` (the browser is all
     main-thread), run only the directory *enumeration* in a **file-scope
     `nonisolated async` function** the @MainActor code `await`s, and apply the
     result on the main actor — so neither `self` nor a closure is ever sent
     off-actor. `DispatchQueue.global {…}`, `Task.detached {…self…}`, and
     `Task {…} + MainActor.run` all failed the sending checks first.
  2. **A weak/strong ownership flip.** `URLObserverClient.urlObserver` must be
     **strong** (the ObjC++ had no `weak`): the shared URLObserver is only weakly
     held by the registry, so the client — retained by the file browser — is its
     owner. Making it weak deallocated the observer before its async load
     delivered, and **the directory silently showed empty**. The client↔observer
     cycle is broken by `removeFromURLObserver`. This is exactly the kind of
     ObjC-ownership detail a Swift port must preserve, not "improve".
  Also: `makeObserverForURL:` now lives on FileItem (default → FileSystemObserver)
  so the MountedVolumes/SCMStatus overrides are real `override`s.

- `53638c07` — **FileBrowserView ported: the view layer is finished.** The 74-line
  container the survey skipped; every view it builds was already Swift, so the
  bridging header needed nothing. `NSAccessibilityGroup` is not declared on the
  Swift class (Swift-6 main-actor isolation — OakTabBarView settled this: set the
  role at runtime, which is what VoiceOver reads), and the `outlineView` property
  keeps the ObjC++'s `NSOutlineView*` spelling so the hand-decl does not drift.
  Two workflow facts it cost, now rules 29 and 30 in the handoff: **editing a test
  file needs a re-seed** (the seed inlines test sources into
  `ide/gen/tests/<Bundle>_impl.mm`, so xcodebuild re-runs the old test code and
  says nothing), and **`to_s()` on an NSString does not work in an ObjC++ test
  bundle** unless `ns.h` is in scope — `xctest_preamble.h`'s generic
  `to_s(_T const&)` binds instead and enumerates the string as a container.

- `9957b2b7` / `be5453a2` — **FileBrowserDiskOperations ported** (530), in the
  two-commit boundary-then-translation shape. The prep commit moved the
  `(DiskOperations)` category declaration out of `FileBrowserViewController.h`:
  the Swift has to *see* the still-ObjC++ class, so the bridging header imports
  that header, and it must not also see declarations of the methods Swift
  defines. `FBOperation` stays behind, on the bridging header's side.
  **The rule-21 cascade the survey feared does not apply here** — measured, not
  assumed: a Swift extension on the ObjC++ controller compiles, `self.fileItem`
  in it resolves to the *Swift* FileItem (the `@class FileItem` forward
  declaration unifies with it rather than colliding), and the C++-typed
  `-variables` is dropped by the importer (rule 17).
  Two fragments stayed ObjC++ in `FileBrowserDiskOperationsSupport`: the `path::`
  arithmetic, and `-presentError:` — an override of NSResponder's method, which
  **a Swift extension cannot provide** (rule 31). `-addButtons:` needed no shim
  despite rule 16; it is only a loop of `-addButtonWithTitle:`.
  Three translation traps, all caught before the app run: the
  `resultingItemURL:` out-parameter of trash (undo moves the item back *from*
  it — dropping it breaks undo silently), ObjC nil-messaging on the nil
  `sourceURLs` array the new-file/new-folder undo passes, and `-[NSURL isEqual:]`
  rather than Swift's normalising `URL ==`.

**All the `FileItem*` model files, the whole view layer and the disk operations
are now Swift.**

**What actually remains:** `FileBrowserViewController.mm` (2328, last). Also
still ObjC++ by choice:
`FSEventsManager`/`SCMManager` (their C++ boundaries are already clear — a later
Swift translation is optional), and the `*Support`/`*Cxx` files that hold the C++
on purpose (`FSEventStream`, `SCMManager`, `SCMManagerCxx`, `FileItemLocations`,
`FileItemSCMStatusSupport`, `FileItemObserverSupport`,
`FileBrowserDiskOperationsSupport`).

**Build gotcha seen this session:** ad-hoc CodeSign of unrelated test bundles can
fail with `invalid or unsupported format for signature` on a leftover `.cstemp`
after many incremental `xcodebuild test` runs. It is not a code error — clear it
with `find <DerivedData>/Build/Products -name '*.cstemp' -delete` (and
`xattr -cr <…>/Build/Products/Debug`) and re-run.

The five views ported so far share one shape: hand-written ObjC decl `.h` (never
in the bridging header), C++/method-body oddments behind a small ObjC++ helper or
a split header, and an `instancesRespondToSelector:` test. The model files are a
different kind of work — data/logic and a class hierarchy with exported globals
and C++ — so expect the DWScopeContext/`-Cxx` + rule-19 forwarder treatment, not
the tidy hand-decl shape the views used.

Two facts for the next session: the ObjC++ tests compile **ARC-off**, and this
framework's public headers carry **no Foundation import** (they lean on the PCH,
like `FileBrowserNotifications.h`) — match that when adding public headers.


## State you are starting from

- `master` clean and in sync with `GH-johnmcgovern`, **alpha.10 shipped**
  (`cf7f9203`, tag `v2026.7-alpha.10`) and verified from a browser-style
  download.
- **601 tests across 35 bundles, green.** Re-measure, never increment — that
  figure has been wrong in these docs twice.
- `DocumentWindow` and `OakAppKit`'s portable leaves are done. `OakAppKit` still
  has the pasteboard cluster (1850 lines) if you would rather do that instead;
  it is the other reasonable next job.

```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 RUBYOPT="-EUTF-8"
export PATH="$HOME/.gem/ruby/2.6.0/bin:$PATH"
ruby ide/extract_specs.rb > ide/gen/specs.json && ruby ide/seed_xcodeproj.rb
xcodebuild test -project TextMate.xcodeproj -scheme AllTests -configuration Debug
```

## The shape of the framework

**5196 lines**, `src/` plus `src/OFB/`. One monster and a tail:

| file | lines | C++ hits |
| --- | --- | --- |
| `FileBrowserViewController.mm` | **2328** | 39 |
| `FileBrowserDiskOperations.mm` | 530 | 4 |
| `SCMManager.mm` | 374 | 17 |
| `FileItemTableCellView.mm` | 294 | — |
| `OFB/OFBFinderTagsChooser.mm` | 241 | — |
| `FileItem.mm` / `FileItemSCMStatus.mm` | 209 / 209 | — / 12 |
| `FSEventsManager.mm` | 204 | 2 |
| `FileItemObserver.mm` | 198 | 2 |
| the rest (`FileBrowserView`, `FileBrowserOutlineView`, `OFB/*`, …) | < 110 each | 0–6 |

Only three headers are public: `FileBrowserViewController.h` (3 external
consumers), `FileBrowserNotifications.h`, `SCMManager.h`.

## Four things that will bite, found by the checklist

**1. There are no tests. None.** No `Frameworks/FileBrowser/tests/` directory at
all. Every port since Find has written them first and it has paid every time —
most recently by failing against the *unported* original and teaching us
`NSWindowStyleMaskBorderless is 0`. Budget for this: it is the first task, not a
follow-up. Whether `FileBrowserViewController` is even constructible in a test
process **is not established** — Find's controller was, CrashReporter's was not,
DocumentWindow's was asserted before its port. Settle that before planning
anything else.

**2. `SCMManager.h` is the hard one, and it is a *public* header.**

```objc
@property (nonatomic, readonly) std::map<std::string, scm::status::type> status;
- (id)addObserverToFileAtURL:(NSURL*)url usingBlock:(void(^)(scm::status::type))handler;
```

That is a C++-typed property *and* rule 15's C++-in-a-block-signature, which
makes the whole method uncallable from Swift rather than merely awkward. It has
**zero external consumers**, so unlike `DocumentWindowController`'s selectors you
are free to reshape it — the `TMSCMStatus` NS_OPTIONS spelling already exists
(`Frameworks/TMFileReference/src/TMSCMStatus.h`) and is the obvious ObjC-facing
type. Check `t_scm_status.mm:82` first; it documents how that cast is done today.

**3. `FSEventsManager.mm` holds `std::shared_ptr<fs_events_t> _fsEvents`** — a
C++ *ivar* (rule 20), so it is the `bundles::item_ptr` blocker again and wants
the `DWScopeContext` treatment: an ObjC-shaped model layer extracted *first*, in
its own commit, before any Swift. `DWScopeContext.h` is the worked example.

**4. `- (std::map<std::string, std::string>)variables` is pinned from outside.**
`DocumentWindowSupport.mm:356` calls it. That selector cannot change shape; it
belongs in an ObjC++ category on the Swift class, exactly as
`DocumentWindowController`'s four are.

## Two build-wiring traps, already paid for elsewhere

- **`Frameworks/FileBrowser/default.rave` says `sources src/*.mm src/OFB/*.mm`.**
  No `swift`. Add it before the first `.swift` or the seed will silently ignore
  the file and the ObjC++ will then fail to find `FileBrowser-Swift.h`, which
  reads like a bridging problem and is not one.
- **Rule 21, and it is subtle here.** `FileBrowserViewController.h` imports
  `FileBrowserNotifications.h`, and `DocumentWindow`'s bridging header imports
  `FileBrowserViewController.h`. The cross-framework import is *fine* —
  DocumentWindow does not define the class. The one to watch is FileBrowser's own
  bridging header: it must not reach `FileBrowserViewController.h` once Swift
  defines that class, so anything it needs out of that header (the `FBOperation`
  NS_OPTIONS at line 58, the notification names) wants the `FindTypes.h` split.

## Suggested order

1. **Tests first.** Stand up `Frameworks/FileBrowser/tests/`, and settle
   constructibility with a `test_..._is_constructible` before anything else.
   Then the selector-surface test (rule 18) over `FileBrowserViewController.h`'s
   actions and its delegate protocols.
2. **Extract the C++ model layers in their own commits** — `FSEventsManager`'s
   shared_ptr, and `SCMManager`'s map/block — while everything is still ObjC++,
   so the existing suite judges each one. This is the two-commit shape that made
   `DocumentWindowController` tractable: boundary first, translation second.
   Do not skip it.
3. **Then the leaves** (`FileBrowserView`, `FileBrowserOutlineView`, `OFB/*`,
   `FileItemTableCellView`), then `FileBrowserDiskOperations`, and
   `FileBrowserViewController` last.
4. Build, full suite, **then run the app** and actually click the file browser:
   reveal, new file/folder, rename, delete, the SCM badges, drag and drop. Three
   of the last four ports turned up something no test could reach.

## FileBrowserViewController — the survey (2026-08-15, before any code)

2329 lines, 137 methods, 40 of them actions, 13 private properties, 34 members in
the public header. The checklist applied once, measured. `00a42e07` is the first
prep commit that came out of it.

**Cleared — these are *not* problems, checked rather than assumed:**
- **No C++ ivars** (rule 20's `bundles::item_ptr` blocker). The class extension
  holds nine ObjC ivars and three `NSInteger` counters, nothing more. There is no
  DWScopeContext-style extraction to do first.
- **No variadic calls** (rule 16) — no `addButtons:`, no `tmAlertWithMessageText:`.
- **No exported globals defined here** (rule 19); the notification consts already
  live in `FileBrowserNotifications.mm`.
- **No C++ in any block signature this file passes or receives** (rule 15). The
  framework has six `(^)` headers; the only C++ one is `SCMManagerCxx.h`, which
  this file does not call.
- **The class is constructible in a test process**, settled at the start of the
  port, and 19 of its selectors are already pinned by
  `t_file_browser_view_controller.mm`.

**The four things that actually have to be solved:**

1. **`+initialize` — a Swift class cannot provide one (rule 20), and this is now
   the only structural blocker left.** It registers the services-menu send types
   on NSApp and a user default seeded from Finder's `_FXSortFoldersFirst`.
   Rule 24 is the worked precedent (`+load` → `+registerBuiltinClasses`): convert
   it to explicit, lazy registration in **its own ObjC++ commit**, before any
   Swift, so the suite and the app judge the behaviour change on its own. Note it
   runs *before any instance exists*, so a `dispatch_once` from `-init` is the
   shape — and `t_file_browser_view_controller.mm`'s `setup()` already documents
   why it needs `NSApplicationLoad()`.

2. **Rule 1 — five KVO-observed key paths, all reached by `bind:`.**
   `canGoBack` and `canGoForward` (bound to the header's two nav buttons) with
   `+keyPathsForValuesAffecting…` naming **`historyIndex`**, and
   `fileItem.displayName` / `fileReference.image` (bound to the current-location
   menu item's title and image). So `historyIndex`, `fileItem` and `fileReference`
   must be `@objc dynamic`, and the two dependent-key class methods must survive
   the port. Everything else is `valueForKeyPath:` *reads* over FileItem arrays,
   which need nothing.

3. **Seven C++ clusters, spread across the file rather than pooled** — this is the
   real difference from every port so far, where one `…Support` file absorbed the
   C++ (rule 25). Expect several, or an ObjC++ category that keeps the C++-heavy
   methods together:
   - `is_binary` (`path::glob_t` + settings) and the exclude/include
     **`path::glob_list_t`** visibility filter (lines ~1469–1492, the biggest one)
   - **`bundles::` three times**: the action-menu items
     (`std::multimap<std::string, bundles::item_ptr, text::less_t>`), the new-file
     grammar extension lookup, and `bundles::lookup` for running a command
   - `std::map<SEL, std::string>` — the inactive key-equivalents table
   - `-variables` (below), `to_s(NSEvent*)`, `path::device` in the drag handler,
     and three throwaways (`std::clamp`, `std::set<NSInteger>`,
     `std::vector<std::pair<BOOL, FileItem*>>`) that are plain translations.

4. **`- (std::map<std::string,std::string>)variables` is pinned from outside** —
   `DocumentWindowSupport.mm:353` calls it from `DocumentWindowController (Cxx)`.
   Unchanged conclusion: it belongs on an ObjC++ category on the Swift class,
   exactly like `DocumentWindowController`'s four.

**The cross-module fact the earlier survey missed, and the reason the hand-decl
header is load-bearing:** `DocumentWindow`'s *bridging header* imports
`<FileBrowser/FileBrowserViewController.h>`, so **`DocumentWindowController.swift`
is a cross-module Swift consumer** — it declares `@preconcurrency
FileBrowserDelegate` and calls `newFile`, `newFolder`, `reload`, `deselectAll`,
`outlineView`, `directoryURLForNewItems`, `path`, `selectedFileURLs`,
`sessionState` and `setupViewWithState:`. Nothing in this framework is `public`,
so none of it is reachable as a Swift type across modules; keeping
`FileBrowserViewController.h` a hand-written ObjC declaration (rule 23) is what
keeps DocumentWindow compiling untouched. That surface is what the rule-18
selector test has to cover before the port, not just the action methods.

**Prep done (2026-08-15), all three judged by the suite on their own:**
`00a42e07` the FileBrowserTypes.h split, `8c98956d` the `+initialize` →
`+registerDefaults` conversion (verified in the app: with a file selected, the
Services menu is still populated, which is the half no test reaches), and
`908a82da` the KVO surface, pinned by binding a real NSButton and NSMenuItem the
way the app does — a missing `@objc dynamic` now fails a test.

**Order from here:** extract the seven C++ clusters while the file is still
ObjC++, in their own commits (step 2 of this plan's original order — the shape
that made FSEventsManager and SCMManager tractable) → then the translation,
split by section rather than in one commit, with an app run after each.

## One warning that is not about this framework

`OakBackgroundFillView`'s overpaint bug (`6b419366`) made the *gutter* invisible
for the whole life of the fork, and the same helper draws dividers in this
framework. If something here looks blank that should not be, check that before
suspecting your port — and read rule 22, which is the procedure that found it.
