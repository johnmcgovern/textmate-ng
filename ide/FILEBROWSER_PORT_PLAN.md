# FileBrowser port — the survey, before any code

_Written 2026-08-13 at the end of the session that shipped alpha.10, so a fresh
session can start on FileBrowser without re-deriving the survey. Everything here
was measured, not assumed; where it says "not established", it means nobody has
checked yet, and you should._

Start by reading **the numbered rules at the end of `ide/FIND_PORT_HANDOFF.md`**.
There are 22 and 8 of them were earned by something that compiled, passed its
tests, and was still wrong. The survey below is that checklist applied once.

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

## One warning that is not about this framework

`OakBackgroundFillView`'s overpaint bug (`6b419366`) made the *gutter* invisible
for the whole life of the fork, and the same helper draws dividers in this
framework. If something here looks blank that should not be, check that before
suspecting your port — and read rule 22, which is the procedure that found it.
