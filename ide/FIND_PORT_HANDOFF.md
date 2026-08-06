# Finishing the Find port — Find.mm, and the tail

_Written 2026-08-05; revised the same day when `FFResultsViewController` landed.
Three of Find's four substantial files are Swift. Read `PROJECT_PHASES.md` under
"Phase 4 — Find, tests first" for what they cost; this covers what is left._

Find is **2238 lines of ObjC++** (measured, `.mm` outside `tests/`), against 3123
at `cbaa5894`. Tests: **50**, from zero on 2026-08-04.

Watch how that number moves. Three files totalling 1205 lines are ported and the
directory fell by 885, because `FFResultNode` and `FFDocumentSearch` each left a
C++ support file behind (244 + 76) while `FFResultsViewController` left nothing.
**Porting relocates C++ as often as it removes it.** Measure the directory; never
subtract the file you ported — that error has been made twice here already.

| file | lines | state |
|---|---:|---|
| `Find.mm` | 1402 | the window controller — **next, and last of the big ones** |
| `FFResultNodeSupport.mm` | 244 | C++ by design, stays |
| `FFTextFieldViewController.mm` | 216 | small, unsurveyed |
| `FFStatusBarViewController.mm` | 156 | small, unsurveyed |
| `FFFolderMenu.mm` | 108 | small, unsurveyed |
| `FFDocumentSearchSupport.mm` | 76 | C++ by design, stays |
| `CommonAncestor.mm` | 36 | a Swift global cannot be `@objc` — see TMFileReference's `FileItemImage.mm` |

---

## Read this first: the trap that has now bitten twice

**A Swift property that ObjC observes must be `@objc dynamic`, not `@objc`.**
`@objc` exposes the accessors to the runtime; it does not force message dispatch.
KVO works by swizzling the setter, so a call that Swift makes *directly* — which
is any call from Swift code — bypasses the notification entirely.

It has now caused two defects in three days, and shaped a third port:

- `FFDocumentSearch.currentPath` — caught before shipping, because the property
  exists solely to be observed and that was obvious on inspection.
- `FFResultNode.excluded` — **shipped**, and fixed in `9d560946`.
  Option-clicking a match checkbox (which excludes the whole file, via
  `item.parent.excluded = item.excluded`) stopped updating the file's other
  matches, because `-setExcluded:` on a branch loops over children *from Swift*.

The second one is the instructive one, because every cheap check passed:

- setting the property **from ObjC** worked all along (objc_msgSend hits the
  swizzle), so a test that set it from the test file passed;
- plain-clicking a match checkbox in the app worked, because the binding writes
  through ObjC — and that is what was clicked when the port was called verified;
  only the option-click path goes through Swift;
- only a property that **Swift itself writes** could expose it, and only via an
  observer on the object Swift wrote to.

**So, before porting either remaining file:**

```bash
grep -rn 'bind:\|addObserver:.*forKeyPath:\|keyPathsForValuesAffecting\|setValue:.*forKey:' Frameworks/Find/src
```

Every key path that lands on a class you are porting is a `dynamic` requirement.
Write the observer test *first*, watch it fail, then add `dynamic`.

`FFResultsViewController` needed **six** of them across three classes, and its
tests (`t_results_view_controller.mm`) were written before the port precisely so
that requirement was checkable rather than hoped for. It worked: the port was
right first time on that axis.

**A second hazard of the same family, found by those tests:** an ObjC ivar that
Swift turns into an implicitly-unwrapped property. `_outlineView` was a plain
ivar, so every use before `-loadView` was a message to nil — harmless, returning
0/nil/NO. Swift traps instead, and `-selectedResults` is reachable that early.
Make such a property an `Optional` and reproduce what nil-messaging returned;
`-isCollapsed` is the subtle one, where `isItemExpanded` answering NO for nil is
what makes the result "there are children".

---

## Done: `FFResultsViewController` (709 lines → Swift, 2026-08-05, `58383f19`)

### Why it went second, and what it cost

- **Almost no C++.** Two uses of `std::max` on `CGFloat` (lines 308, 317), both
  of which are Swift's `max`. No support file needed — the first Find file where
  that is true.
- **A clean header.** `FFResultsViewController.h` is pure ObjC: `SEL` properties,
  a `FFResultNode*`, `BOOL`s, and IBActions. Its only consumer is `Find.mm`, which
  stays ObjC++ for now, so the boundary holds still while the inside moves — the
  shape that made BundleEditor routine.
- **No nib.** Views are built in code (`OakCreateLabel`, visual-format
  constraints), so the nib-contract tests do not apply.

### What is actually in the file

Five classes, not one:

| class | role |
|---|---|
| `FFResultsViewController` | the outline view's data source + delegate |
| `OakTableCellView` | base cell; owns the `observeKeyPaths` mechanism |
| `OakSearchResultsCheckboxView` | the exclude checkbox |
| `OakSearchResultsMatchCellView` | a match row, with the excerpt |
| `OakSearchResultsHeaderCellView` | a file row, with icon + display path |

Port them as a group. `OakTableCellView` is the base of the other two and carries
the shared observation logic, so splitting the file across commits means the
subclasses cannot compile until the base moves.

### The specific hazards

1. **`+keyPathsForValuesAffectingExcerptString`** (line 115) is a KVO dependency
   declaration listing `objectValue.readOnly`, `objectValue.excluded`,
   `objectValue.replaceString` and three of its own properties. In Swift this is
   `class var keyPathsForValuesAffectingExcerptString: Set<String>` — and the
   properties it *names on this class* (`replaceString`,
   `showReplacementPreviews`, `backgroundStyle`) must themselves be `dynamic`, or
   the dependency never fires. This is the same trap one level up.

2. **`OakTableCellView.observeKeyPaths`** (lines 85, 100) is a hand-rolled
   observation bridge: the cell registers on its view controller for a list of
   key paths with `NSKeyValueObservingOptionInitial`, then mirrors each value
   onto itself with `setValue:forKey:`. That is KVC-by-string in both directions.
   Swift will compile it happily and it will fail at runtime if any property name
   changes spelling — the `getter=` class of bug. Keep the names byte-identical,
   and prefer porting this class last within the file so the others are known
   good.

3. **Bindings are established in `init`, on views.** `[textField bind:…]`
   requires the *binding target* to be KVO compliant, which is the controller and
   the cell, not just the node. Everything the cells bind to is listed above;
   `objectValue` itself comes from `NSTableCellView` and is already fine.

4. **`NextNode`/`PreviousNode`** (lines 11–17) are free functions doing tree
   traversal. A Swift global cannot be `@objc`, but nothing outside the file
   calls them — make them private statics or methods, no shim needed.

5. **`setResults:`** (line 395) replaces the whole tree. Check what it does with
   the outline view's selection state; the results view is the only thing that
   remembers `_lastSelectedResult` across a re-search.

### Coverage, written first (2026-08-05)

The framework had 40 tests and **none touched this file**. It is a view controller,
so the GUI-suite problem in Stream 7 applies to driving the outline view — but
three things are testable without one:

- `NextNode`/`PreviousNode` traversal over a hand-built `FFResultNode` tree
  (currently unreachable — make them internal rather than static as part of the
  port, or test through `selectNextResultWrapAround:`).
- `excerptString`'s decision table: the ternary at line 145 picks between
  `item.replaceString`, `self.replaceString` and `@""` based on
  `isReadOnly`/`excluded`/`showReplacementPreviews`. Eight combinations, all pure.
- **A KVO test per bound key path**, per the section above. These are the ones
  that would have caught `9d560946`. **Written 2026-08-05** —
  `t_results_view_controller.mm`, 6 tests, green against the ObjC++. They cover
  `replaceString`, `showReplacementPreviews` and `showKeyEquivalent`, which the
  cells observe *on the controller* through `OakTableCellView`'s bridge, plus
  readability-by-name since that bridge mirrors values with `-setValue:forKey:`.
  The controller is constructible in a test process — checked, not assumed.

**Outcome.** Of the three, only the KVO tests were written, and they were the
right call: they carried the port. The `excerptString` decision table stayed
untested because the cell classes have no header and exposing them would have
been a redesign — it was verified in the app instead (excluding a row reverts its
preview while the others stay replaced, which walks the whole table). The
traversal helpers stayed `private`: nothing outside the file calls them, and
making them internal purely to test them would have been the tail wagging the
dog.

Two importer renames also turned up, the shape TMFileReference recorded for
`TMURLWillCloseNotification`: `+tmMatchedTextSelectedBackgroundColor` arrives as
`tmMatchedTextSelectedBackground()`, suffix stripped, likewise the underline
twin. And `validateMenuItem:` is `NSMenuItemValidation`, not an
`NSViewController` override.

---

## Next: `Find.mm` (1402 lines)

### Why it was left until last

It is the window controller everything else hangs off, it owns the
`OakFindProtocol` conformance, and it is the only file in the framework that is
genuinely C++-heavy. Doing it last means every class it talks to is already Swift
and already tested.

### `Find.h` has C++ in it — the survey said otherwise and was wrong

**Read this before planning the port.** The framework was picked partly because a
survey reported "no C++ in any of its eight public headers". That was false: the
grep searched `std::|namespace|#include <`, and `Find.h` uses `#import <…>` and
spells its C++ `text::`.

```objc
#import <text/types.h>

@interface FindMatch : NSObject
@property (nonatomic, readonly) text::range_t firstRange;   // Swift cannot hold this
@property (nonatomic, readonly) text::range_t lastRange;
- (instancetype)initWithUUID:(NSUUID*)uuid firstRange:(text::range_t const&)f lastRange:(text::range_t const&)l;
@end

@protocol FindDelegate <NSObject>
- (void)selectRange:(text::range_t const&)range inDocument:(OakDocument*)aDocument;
```

So `Find.mm` is the **`FFResultNode` shape** — a real C++ half needing a support
file — not the `FFResultsViewController` shape that needed none. Budget for that
from the start.

### What has to stay ObjC++

| piece | where | why |
|---|---|---|
| `FindMatch` (12 lines, `Find.mm:50-61`) | move to `FindSupport.mm` | two `text::range_t` properties; stays declared in `Find.h` |
| the `-selectRange:` call | `Find.mm:1239` | passes `item.match.range`, a `text::range_t const&`, through the delegate protocol |
| `-setUpFindMatches:` | `Find.mm:1149` | builds `FindMatch` from `match.range` |
| the replace path | `Find.mm:~960` | `std::multimap<std::pair<size_t,size_t>, std::string>` handed to `-performReplacements:checksum:`, whose signature is C++ in `OakDocument.h` and is not moving |
| `format_string::expand`, `path::relative_to`, `text::format`, `std::to_string` | scattered | the usual suspects |

Everything else — the window, the bindings, the search-target switch, the status
strings — is ordinary AppKit.

### `_findOptions` already has its ObjC spelling

`Find.mm:139` declares it `find::options_t` in the class extension and builds it
with `|` from `find::` constants (`:881`), testing it with `&` (`:1030`).
**`FFFindOptions` already exists for exactly this type** (`FFFindOptions.h`, from
the FFDocumentSearch port). Reuse it; do not invent a second spelling.

### The blocker to decide before starting

**`Find.mm` calls `MBCreateMenu` twice** (lines 356, 578), and MenuBuilder's
public API is a C++ DSL — `std::vector<MBMenuItem>` with designated-initializer
aggregates — that **Swift cannot construct**. This is the MenuBuilder trap
arriving from the other direction, and it is the reason MenuBuilder is scheduled
*last* (see `PROJECT_PHASES.md`, Phase 4 coupling survey).

Three ways out, in order of preference:

1. **Hand-roll the two menus in Swift**, as `CommitWindow` and `Preferences`
   already do — their `.swift` files say so in comments
   (`FilesPreferences.swift:45` and siblings). Proven, local, no new API.
2. **A narrow ObjC++ shim** in a `FindSupport.mm`: one function per menu that
   builds the `MBMenu` and returns the `NSMenu*`. Cheap, but adds a file whose
   only purpose is to outlive MenuBuilder's C++ API.
3. **Port MenuBuilder first.** Rejected — it would ship a Swift menu API with
   zero Swift callers while the DSL stays alive for the six remaining ObjC++
   ones, one of which (`OTVStatusBar`, inside OakTextView) is permanent.

Take (1) unless the menus turn out to be large.

### The rest of the C++ surface

- **`find::options_t _findOptions`** (line 139) is a class-extension property,
  not public, and is built with `|` from `find::` constants (line 881) and tested
  with `&` (line 1030). `FFFindOptions` already exists for exactly this type —
  reuse it rather than inventing a second spelling.
- **`format_string::expand`** (lines 961, 1030, 1320) and `to_s`/`to_ns` are the
  usual suspects; they belong in a support file with the menu shim if one is
  written.
- **`std::multimap<std::pair<size_t,size_t>, std::string> replacements`** (line
  961) is handed to `-performReplacements:checksum:`. That signature is C++ in
  `OakDocument.h` and is not moving, so the replace path stays ObjC++ — probably
  the largest single piece that cannot be ported without an ABI decision like
  `FFFindOptions`. **Survey this before committing to a whole-file port**; it may
  be a `FindReplaceSupport.mm` rather than a Swift method.
- **`Find.mm:974`** does `[parent.children setValue:nil forKey:@"replaceString"]`
  — KVC on an array, which fans out to every element. It works against the Swift
  `FFResultNode` today because `replaceString` is `dynamic`. Do not remove that
  keyword.

### Coverage — partly written (2026-08-05, `b1595405`)

`Find.mm` is a window controller, so most of it needs the GUI-suite treatment.

- **`-acceptMatches:`** (line 1126) — **done**, 4 tests in `t_find_matches.mm`.
  The tree assembly, accumulation across batches, and the fact that a *recurring*
  document starts a new branch rather than rejoining its earlier one. Reached
  through `FindTesting.h`, which declares the class-extension members and thereby
  pins them for the port.
- **`Find` is constructible in a test** — asserted, not assumed. Its `-init`
  passes `@"UNUSED"` as a nib name; the window is built in code.
- **The find-options assembly** (line 881) — still to write. Five booleans in,
  one mask out; pure, and it should assert against `FFFindOptions` so the port has
  no room to invent a second spelling.
- **The status-string formatting** (lines 1188, 1272) — still to write.
  Pluralisation and number formatting, pure given a count. `:1188` picks between
  "searched one file" and "searched N files", which is the kind of thing a port
  quietly gets wrong at N=1.

---

## Rules earned so far, in one place

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
