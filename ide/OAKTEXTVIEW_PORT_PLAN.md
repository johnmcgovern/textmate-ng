# Porting OakTextView

Written 2026-09-22. OakTextView is the largest body of unported code left and
the one a mistake is most visible in — it is the editor. This is the order to
take it in and why, so the first slice is not chosen by whatever is on top.

## What is actually there

| File | Lines | Notes |
| --- | --- | --- |
| `OakTextView.mm` | 4,633 | the monolith |
| `GutterView.mm` | 562 | a separate `NSView`, drawn beside the text |
| `OakDocumentViewSupport.mm` | 218 | support file (rule 25) |
| `OakCommandRefresh.mm` | 193 | builds the command environment |
| `OTVStatusBarSupport.mm` | 35 | support file |
| `OakChoiceMenuConstants.mm` | 8 | constants |

Already Swift: `OakDocumentView` (853), `OTVStatusBar` (417),
`OakChoiceMenu` (300), `OTVHUD` (142), `LiveSearchView` (65).

**379 lines of `OakTextView.mm` touch C++** (`ng::`, `text::`, `std::`,
`oak::`). That is the real constraint, not the line count: rule 37 means a type
crossing into Swift has to be expressible on both sides, and the editor's buffer,
ranges and scopes are all C++.

`OakTextViewTesting.h` says the file "subclasses three C++ classes with virtual
methods" and is therefore not a porting candidate. Checked, and it is nearly
right: `OakTextView` is an Objective-C class, but it *defines* C++ subclasses
inside itself — `buffer_refresh_callback_t : ng::callback_t` among them — and
holds pointers to them. Swift cannot express a subclass of a C++ class with
virtual methods, so those stay Objective-C++ whatever else happens. The
conclusion stands even though the reason is one step removed: the C++ core of
this file is not going to Swift, and any plan that assumes otherwise is wrong.

## The order

**1. `GutterView.mm` first.** It is a separate file, a plain `NSView`, and only
23 of its lines touch C++. Its public header is already Foundation types with one
exception, `-setHighlightedRange:(std::string const&)` — and **nothing outside
the file calls it**, measured, not assumed. The only caller is its own
`-setHighlightedRangeString:` bridge two lines below. So the C++ in its public
surface is already dead and the port does not have to solve rule 37 at all.

It is also the right first slice on risk: the gutter has produced two of this
project's worst shipped bugs, it is visible in the first second of looking, and
it can now be checked by screenshot.

**2. The support files** — `OakCommandRefresh.mm`, `OakDocumentViewSupport.mm`,
`OTVStatusBarSupport.mm`. These exist precisely because Swift cannot reach what
they reach (rule 25), so they are the last things to port, not the first. Listed
here only so nobody starts with them by mistake.

**3. `OakTextView.mm` in named pieces, never wholesale.** It has section markers
already and they are the seams:

- `OakAccessibleLink` (~10 lines) and `OakTextViewFindServer` (~50) are
  self-contained classes that happen to live in the file. They move out first,
  as their own files, still Objective-C++ — a move is not a port, and doing both
  at once makes the diff unreviewable.
- `NSTextInputClient` (~220 lines) is the marked-text and input-method surface.
  It is self-contained, it is testable without the rest, and getting it wrong is
  invisible until somebody types Japanese.
- The two accessibility blocks (`NSAccessibilityStaticText`,
  `NSAccessibilityNavigableStaticText`) — already measured as answering from the
  protocol methods rather than the legacy API, so the pins go on the protocol.
- What remains is the C++-facing core: the buffer, selection and layout, and the
  callback subclasses. **That part is not going to Swift at all.** The goal there
  is to shrink it to a support file behind a narrow Objective-C++ face (rule 25),
  not to port it — so "done" for this framework means a small deliberate island
  of C++, not zero.

## How, every time

The two-commit method, unchanged: **pins first, written against the Objective-C++
and proved to pass**, then flip the implementation to Swift and prove they still
pass. A pin written after the flip tests the port against itself.

Mutation-check both sides. A pin that passes against the original and against a
deliberately broken port is not a pin.

## Started: GutterView pins, 2026-09-22

Eight tests against the Objective-C++, before any Swift. Three mutations:
`isFlipped` returning NO, every column reading as visible, and the line-number
column never being inserted.

The third one survived, and it was a fault in my test rather than in the
gutter. It asked `visibilityForColumnWithIdentifier:`, which answers from a set
of *hidden* identifiers — so a column that was never inserted also reads as
visible, and the assertion was true either way. It asserts through width now,
which does depend on the column existing, and the same mutation fails it.

One test also failed first time for a better reason than it passed: setting a
highlighted range did not mark the view dirty, because a view with no window is
not required to record `-setNeedsDisplayInRect:`. The pin now puts it in a
window. Both of those are the two-commit method working as intended — the pins
found my wrong assumptions while the original was still there to check against.

## What would make this go wrong

Not the size. The two failures this project has already had in this area were a
gutter that drew nothing and a Settings window that crashed on open, and both
were green in the suite the whole time. The smoke pass by screenshot is what
catches that class, and it is cheap now — take one after every slice.
