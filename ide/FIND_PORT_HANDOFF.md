# The Find port — done, and the tail

_Written 2026-08-05 as a plan for `Find.mm`; rewritten 2026-08-07 when that port
landed. **Find has no big files left.** What follows is what the last one cost
and what is still in the directory, not a plan._

Find is **1107 lines of ObjC++** (measured, `.mm` outside `tests/`), against 2238
before this port and 3123 at `cbaa5894`. Tests: **76**, from zero on 2026-08-04.

Watch how that number moves, because it is the thing this document has been wrong
about most often. `Find.mm` was 1402 lines and the directory fell by 1131, not by
1402: `FindSupport.mm` (271) is where its C++ went. That is the fourth time in
this framework — `FFResultNode` left 244 behind, `FFDocumentSearch` 76,
`FFResultsViewController` nothing. **Porting relocates C++ as often as it removes
it.** Measure the directory; never subtract the file you ported.

| file | lines | state |
|---|---:|---|
| `FindSupport.mm` | 271 | C++ by design, new — see below |
| `FFResultNodeSupport.mm` | 244 | C++ by design, stays |
| `FFTextFieldViewController.mm` | 216 | small, unsurveyed |
| `FFStatusBarViewController.mm` | 156 | small, unsurveyed |
| `FFFolderMenu.mm` | 108 | small, unsurveyed |
| `FFDocumentSearchSupport.mm` | 76 | C++ by design, stays |
| `CommonAncestor.mm` | 36 | a Swift global cannot be `@objc` — see TMFileReference's `FileItemImage.mm` |

The Swift side is 2678 lines across four files, of which `Find.swift` is 1533.

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

## Done: `Find.mm` (1402 lines → Swift + 271 of ObjC++, 2026-08-07)

### What it actually took

`Find.swift` (1533) plus `FindSupport.h`/`.mm` (271), and three new headers that
exist only to make the split possible:

| file | why |
|---|---|
| `FindTypes.h` | `FindMatch`, `FFSearchTarget`, `FindDelegate` — **see below**, this was the one structural surprise |
| `FFFindAction.h` | the eight action tags, lifted out of `Find.mm`'s file scope so a test can name them |
| `FindSupport.h` | the C++ boundary: 13 functions, one class, one NS_ENUM |

### The decision that shaped it: no C++ in `Find.swift` at all

Probes (`f9bb0414`) established that Swift *can* name `find::options_t`,
`text::pos_t` and `text::range_t` under this project's interop mode. This port
did not use that. Everything C++ went behind `FindSupport.h`, including an
**ObjC++ category carrying the whole `OakFindServerProtocol` conformance** — the
`BEInterop.mm`/`CRSupport.mm` recipe, now used a third time.

Two of the protocol's five requirements are C++ (`-findOptions` returns
`find::options_t`, `-didFind:…atPosition:` takes `text::pos_t const&`). The
category implements those two and forwards to a C++-free Swift surface
(`findOptionsMask`, `findOperationTag`, `-didFindNumber:statusString:`); the other
three are ordinary ObjC and are Swift methods. Swift never declares conformance
and never imports `OakFindProtocol.h`.

The reason to prefer this over the probe's answer: one declared boundary per
framework, with the enum conversions sitting next to the `static_assert`s that pin
them, rather than C++ spellings scattered through a 900-line window controller.

### `Find.h` had to be split, and that was not foreseen

`Find.h` declared four things: `FindMatch`, `FFSearchTarget`, `FindDelegate` and
`@interface Find`. The Swift needs the first three and **must not see the
fourth** — it defines that class. So the three moved to `FindTypes.h`, which the
bridging header imports and `Find.h` re-imports, and both are now exported.

Two things fell out of that:

- `Find.h` imports it **quoted**, not `<Find/FindTypes.h>`. A target's farm
  include dirs are its *dependencies'* headers, never its own, so the angle form
  does not resolve while compiling this framework. `BundlesManager.h → Bundle.h`
  and `OakDocumentView.h → OakTextView.h` already do it the quoted way.
- No consumer changed. `#import <Find/Find.h>` still yields everything.

**Generalise this before the next port:** any public header that declares both a
class being ported *and* types the Swift needs will need the same split. Check
for it while surveying, not after the bridging header fails to compile.

### The menus were hand-rolled, as planned — with one detail worth keeping

Option (1) from the old plan, and it was right; both menus are ~20 items. The
detail that a reading of the call site would have missed: in `MBCreateMenuItem`,
**an item with a nil title becomes a separator**, so `Find.mm`'s
`{ /* Placeholder */ }` first item was `[NSMenuItem separatorItem]`, not an empty
item. A pop-up button never draws item 0, so nothing shows either way — but the
menu would have been off by one had it been reproduced as an empty item, and
every key equivalent below it would have shifted. Read the builder, not the DSL.

`MBMenuItem`'s other defaults that matter: `modifierFlags` defaults to
`NSEventModifierFlagCommand` (not 0), `enabled` to `YES`, and a non-nil
`.delegate` alone is enough to make it build a submenu — which is how
"Select Result" gets the submenu that `-menuNeedsUpdate:` fills.

### What the tests caught, and what only the app could

Coverage went 50 → 76. The 26 new tests are three files, all written against the
ObjC++ *before* the port, all of which required extracting the logic into named
members first and pinning them in `FindTesting.h`:

- `t_find_option_assembly.mm` (7) — the five check boxes plus the two
  action-implied bits. The one that earns its keep is
  `test_ignore_whitespace_is_suppressed_by_regular_expression`: `-ignoreWhitespace`
  is **not** the ivar the check box writes, because its getter answers NO whenever
  regularExpression is on. A port that stores five plain `Bool`s compiles, passes
  the other six tests, and silently changes what every regexp search matches.
- `t_find_status_strings.mm` (16) — five sentences, each of which picks a
  different wording at N = 1, plus the positional-format transposition that would
  otherwise read "Found needle results for “2”".
- `t_find_operation.mm` (3) — `FFFindOperation` against `find_operation_t`, the
  same NS_ENUM split `FFFindOptions` already was.

**And then the app, which was again not optional.** Five things it exercised that
no test reaches: both hand-rolled menus (including `-validateMenuItem:` driving
the check marks and the disabled "Check All"), the "Select Result" submenu built
by `-updateShowTabMenu:` with its ⌘1–⌘6 numbering and file icons, a folder search
end to end, the `std::multimap` replace path against a scratch fixture, and the
in-document find — which is the whole `OakFindServerProtocol` round trip through
the ObjC++ category and back, and the only way to see `format_string::expand`
produce "Found “x” at line 1, column 7."

### One thing looked like a regression and was not

After Replace All, the "Replace All" button stays **enabled**, though
`-canReplaceAll` reads as though it should go false once every match is read-only.
Rather than reason about it, the alpha.7 Release build — which still has the
ObjC++ `Find.mm` — was driven through the identical sequence: **it behaves the
same**. Pre-existing, not introduced.

Worth keeping as a method note: a shipped build of the previous commit is a free
A/B oracle for any "is this a port defect?" question, and it settles in minutes
what reading two implementations settles in an hour. The first attempt at that
comparison was invalid — the ObjC++ run had not actually searched, so its button
was disabled for the trivial reason — which is its own reminder to check that the
control run did the thing before comparing outcomes.

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
