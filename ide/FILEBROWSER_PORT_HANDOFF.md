# FileBrowser port — handoff

_Written 2026-08-15; rewritten 2026-08-16 at the end of the peel; rewritten
again 2026-08-17, when **the flip landed (`53923fe4`) and this port finished**.
FileBrowserViewController is Swift. What remains in this document is the record
of how, the four things the flip could not carry across, and a short list of
work that is genuinely optional — see "What is left" immediately below._

_Every count and line number was measured against the tree at `53923fe4`, not
carried forward. The per-commit detail and the reasoning behind each decision
live in `ide/FILEBROWSER_PORT_PLAN.md`, and all 49 cross-framework rules now live
together in `ide/RULES.md`._

## What is left

**Nothing that blocks anything, and nothing that is owed.** In rough order of
value:

1. **The blank SCM group headers** (noted under "State" below). Not from the
   port, and it survived the flip unchanged, which is one more piece of evidence
   that it is upstream of all of this.
2. `FSEventsManager.mm` / `SCMManager.mm`, which are ObjC++ **by choice** and
   work as-is. Do not "finish" them without a reason.

**Done since:** the delegate conformances moved into Swift (`159cdde4`), which
deleted the `(CxxConformances)` category and both `+wire…` helpers. Fifteen
witnesses were widened from `item: FileItem` to the `Any` the protocols declare.
Two things came out of it worth carrying forward — `FileBrowserOutlineViewDelegate.h`
is now nullability-annotated (rule 44 applied to a protocol, which also removed
an `item as Any` that was boxing an Optional inside an `Any`), and
`-outlineView:child:ofItem:` is declared `-> Any!` because it must still answer
nil and the requirement is non-optional. The suite caught the NSNull() version
of that immediately.

**The flip's app run is finished.** `53923fe4`'s own message says it is not —
that was true when it was written, because the machine locked part-way through.
It was completed afterwards against a Release build of `71bc39ad`, and the five
checks it named all pass: undo through the context menu (the folder leaves the
disk), Quick Look, ⇧⌘Y, ⇧⌘C, and back/forward — the last restoring the tree's
expansion state *and* selection, which is the pending-set path. Read this line
rather than that commit message.

## State you are starting from

- `master`, tree clean. The port ends at **`53923fe4`**, the flip; the peel
  before it ended at `61ebc55f`. Cite those rather than a HEAD hash that the
  next doc commit will stale.
- **Nothing is pushed, and it is not just this work.** The remote is
  `GH-johnmcgovern` (there is no `origin` — a `git log origin/master..master`
  silently reports nothing and reads as "all pushed"). `master` was **51 commits
  ahead** of `GH-johnmcgovern/master` at `11c5e1da`, and that reaches back well
  before this port. The number grows with every commit including doc ones, so
  read it off `git branch -vv` rather than from this line, and do not push
  without asking.
- **646 tests across 36 bundles, green**, of which FileBrowser's bundle is
  **45**. Measured at `53923fe4`, not carried forward: this line said 643 until
  the count was actually run, which is rule 10 happening again in the same
  document that states it. Re-measure, never increment — and **do not anchor the
  grep**, because xcodebuild interleaves log lines from other threads and a
  `^Test Case` pattern silently drops the ones that get a timestamp glued to
  their front (that cost a false "a test disappeared" scare):
  ```bash
  grep -o "Test Case '-\[[^]]*\]' passed" <log> | sort -u | wc -l   # and never `tail` the log away
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
- `FileBrowserViewController.swift` is **1390 lines**, from a 2280-line `.mm`
  by way of a 1410-line one. Its ObjC++ remainder is
  `FileBrowserViewControllerCxx.mm`, **277 lines** for three methods.

### How this port was done — the shape to copy, not to re-run here

A class cannot be half-translated: its *definition* flips from ObjC++ to Swift
in one commit. But its **methods** can leave a section at a time, as Swift
extensions on the still-ObjC++ class. That is what `FileBrowserDiskOperations`
already was, what eight more sections did in the peel, and it is why the flip
itself — 1410 lines in one commit — was tractable at all.

It paid for itself repeatedly, and each time in the same way: a defect arrived
as one suspect in a sixty-line commit rather than one of hundreds of new lines.
The first peel crashed the test process on a nil root (rule 33), a later one put
`Optional("committed.txt")` into the context menu (rule 44), and the last one
shipped a crash on collapsing a folder (rule 46).

**The three headers that made it work are all gone now**, and their jobs are
worth remembering for the next framework:

| header | who imported it | declared |
| --- | --- | --- |
| `FileBrowserViewControllerInternal.h` | the **bridging header** | private state and methods **ObjC still implemented** — readonly properties, and ObjC++ methods Swift called. Never anything Swift defined, and **never a protocol conformance** (rule 42). |
| `FileBrowserActions.h` | the **.mm only** | methods **Swift defined** that the ObjC++ still named by `@selector`. Never the bridging header (rule 43). |
| `FileBrowserDiskOperations.h` | the **.mm only** | the one category Swift implemented before the flip. |

All three were deleted by `53923fe4`, which is the check that the flip was
complete. What the *tests* still needed from them lives in
`tests/FileBrowserSwiftSurface.h`, deliberately scoped to the test bundle so it
cannot drift back into the framework's surface.

### What is already Swift

**Whole classes** — the entire view layer and the whole `FileItem*` model
family:

`OFBHeaderView`, `OFBActionsView`, `FileBrowserOutlineView`, `OFBFinderTagsChooser`,
`FileItemTableCellView`, `FileBrowserView`, `FileItem` (base),
`FileItemMountedVolumes`, `FileItemSCMStatus`, `FileItemObserver`.

**The controller itself** (`FileBrowserViewController.swift`, `53923fe4`), and
**nine extensions on it** — `FileBrowserDiskOperations` from the earlier
session, the other eight from the peel:

`FileBrowserDiskOperations`, `FileBrowserOutlineViewDataSource`,
`FileBrowserTableCells`, `FileBrowserAcceptDrop`, `FileBrowserActions`,
`FileBrowserPasteboard`, `FileBrowserMenuValidation`, `FileBrowserQuickLook`,
`FileBrowserLoading`.

```bash
grep -l 'extension FileBrowserViewController' Frameworks/FileBrowser/src/*.swift   # the check for the second list
```

### What is still ObjC++ (and why)

- **Three methods of the controller, permanently**, now that Swift defines the
  class itself:
  - `-variables` and `-updateMenu:` (with `-menuNeedsUpdate:`, which reaches the
    second) in `FileBrowserViewControllerCxx.mm`, a category on the Swift class.
  - `-presentError:` in `FileBrowserDiskOperationsSupport.mm`. Rule 31 stopped
    applying at the flip and **nullability replaced it**: AppKit declares
    `-presentError:modalForWindow:…`'s window nonnull, the ObjC++ passed
    `self.view.window`, and that is nil whenever the browser is not in a window.
    Swift has nowhere to put the nil.
- `FileBrowserViewControllerSupport.{h,mm}` is ObjC++ **permanently** — that is
  the point of it. Note that two of its methods are not C++ at all:
  `+wireOutlineView:toController:` and `+wireMenu:toDelegate:` exist because a
  Swift dynamic cast cannot see an ObjC-declared conformance (rule 47).
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

Surveyed, prepped, peeled, extracted, and finally flipped. This section and the
next are the record of how `FileBrowserViewController.mm` got from 2280 lines to
the 1410 the flip translated, and why nothing more could be taken out of it
first. **What the flip itself did is under "The flip" below.**

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

There is no ObjC-shaped MenuBuilder API to use instead, so -updateMenu: joined
-variables and the support class in the permanent-ObjC++ bucket; at the flip it
became a category on the Swift class, in `FileBrowserViewControllerCxx.mm`. Extracting just the MBMenu literal so the
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

## The flip — what it did, and the four things it could not carry across

`53923fe4`. `FileBrowserViewController.mm` (1410 lines, 75 methods) became
`FileBrowserViewController.swift` (1390), plus `FileBrowserViewControllerCxx.mm`
(277) for the ObjC++ remainder. The prep had settled the mechanics, and those
parts went exactly as planned: the class's `.h` became a hand-written
declaration (rule 23) and left the bridging header — that one `#import` line was
the only bridging-header removal, because every type the Swift needed had
already been split into exported companions — and all three temporary headers
were deleted.

**What the prep had not predicted is the interesting part.** Four things could
not simply be translated, and three of them compile clean:

1. **The delegate conformances could not move to Swift** (rule 47). The peeled
   sections spell their parameters `item: FileItem`, not `item: Any`, so
   declaring NSOutlineViewDataSource and the rest on the Swift class makes
   fourteen of those methods "conflicts with optional requirement" errors. They
   stay on an ObjC category in `FileBrowserViewControllerCxx.mm` — where the
   class extension had them all along.
2. **Which makes `outlineView.dataSource = self` untypeable, and the obvious
   workaround a crash.** `(self as AnyObject) as! NSOutlineViewDataSource` builds
   and then dies at run time: *Could not cast value of type
   'NSKVONotifying_FileBrowserViewController'*. Hence
   `+wireOutlineView:toController:` on the support class.
3. **Every undo silently stopped being registered** (rule 47 again, second
   form). `prepare(withInvocationTarget:) as? FileBrowserViewController` returns
   an NSProxy; the cast worked only while the class was ObjC. Now
   `-registerUndoWithTarget:handler:`.
4. **`MutableLongestCommonSubsequence` indexed past its buffer** (rule 48) and
   Swift will not do that, so the stride is corrected.

Two smaller ones worth knowing: `-presentError:` stayed ObjC++ for a *new*
reason (nullability, not rule 31 — see "What is still ObjC++"), and the services
registration keeps `"NSFilenamesPboardType"` / `"Apple URL pasteboard type"` by
raw value, because `.fileURL` / `.URL` are different types and swapping them
would change which services the browser offers.

**The app run for this commit is finished**, though its commit message says
otherwise — see the note at the end of "What is left".

## The numbered rules moved to `ide/RULES.md`

Rules 23–49 were earned in this port and now live, together with rules 1–22, in
[`ide/RULES.md`](RULES.md) — one file, so a survey reads all 49 rather than a
third of them. Add new rules there, at the end; never renumber. The operational
notes below (build gotchas, driving the app) stayed here — they are session
notes, not numbered rules.


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

**Check whether the screen is simply locked before believing any of this.** The
flip's app run ended with `screenshot` returning "permission missing or
SCContentFilter failure" and System Events unable to see the app's windows —
which is exactly the signature below, and was not it: the machine had locked
while a build ran. A screenshot taken once it was awake showed the lock screen
immediately. The distinction matters because this note otherwise says "do not
diagnose it", and waiting out a bug that is actually a locked Mac means waiting
forever. `pmset -g` or one more screenshot costs nothing.

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

- **A synthetic drag needs to be slow and finely stepped, and "eight or so moves
  with a pause" is not enough.** A press, three moves and a release highlights
  the drop row but the drop does not happen — the file stays put and it reads as
  "validateDrop: rejected it". Nine moves and a 1.5s pause before the release
  still did not drop. What works: ~12 moves, a 1s pause on arrival, then a
  **one-pixel jiggle at the destination** (off the drop row by a pixel and back)
  and a 2s pause before the release. The jiggle is what was missing — the last
  move has to land while the drag session is already settled on the row.
  Check the *disk*, not the outline view, before believing either result: the
  failed attempt highlighted the drop row **and spring-loaded the folder open**,
  which looks exactly like success.
- **Quitting can hang on an unsaved untitled document** left over from testing
  New File. `osascript … to quit` blocks on the save sheet with no output; look
  at the screen rather than assuming the app is wedged.
