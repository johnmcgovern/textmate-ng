# TextMate

## Download

TextMate-NG has no published download yet — alpha builds are handed over
directly. That link is *upstream* TextMate 2:
[download TextMate from here](https://macromates.com/download).

## Installing a test build

Alpha builds are **Apple Silicon only and need macOS 15 Sequoia or later** (see
the Apple Silicon and minimum-version notes in the release notes). They are
signed ad-hoc rather than with an Apple Developer ID, and are not notarized —
that is gated on Stream 3 in `PROJECT_PHASES.md`.

Unpack with `ditto` rather than double-clicking the archive, so the code
signature and extended attributes survive:

```
ditto -x -k TextMate-NG-<version>.zip /Applications/
```

If the archive reached the machine by a route that sets the quarantine flag —
AirDrop, a browser download, email — Gatekeeper will refuse to open it, reporting
that the app "is damaged and can't be opened". It is not damaged; that is what
Gatekeeper says about an app it cannot verify because it is unsigned and
unnotarized. Clear the flag on the copy:

```
xattr -dr com.apple.quarantine /Applications/TextMate-NG.app
```

Copying with `scp` or `rsync` over SSH does not set the flag in the first place,
which avoids the step entirely.

Two things a test build deliberately will not do: it will not update itself
(software-update channels are unconfigured while the fork has no server), and
its QuickLook generator will not load, because Apple's QuickLook host processes
are library-validated and refuse ad-hoc-signed plug-ins.

## Feedback

You can use [the TextMate mailing list](https://lists.macromates.com/listinfo/textmate) or [#textmate][] IRC channel on [freenode.net][] for questions, comments, and bug reports.

You can also [contact MacroMates](https://macromates.com/support).

Before you submit a bug report please read the [writing bug reports](https://github.com/textmate/textmate/wiki/writing-bug-reports) instructions.

## Screenshot

![textmate](https://raw.github.com/textmate/textmate/gh-pages/images/screenshot.png)

# Building

TextMate-NG builds with Xcode. `bin/rave`/ninja, the original build system, was
retired 2026-07-26 (tag `rave-final`) once the Xcode build reached full parity —
see `PROJECT_PHASES.md`'s rave parity audit.

## Setup

To build TextMate-NG, you need the following:

 * [boost][]            — portable C++ source libraries
 * [Cap’n Proto][capnp] — serialization library
 * [multimarkdown][]    — marked-up plain text compiler (compiles the About pages)
 * [ragel][]            — state machine compiler
 * [sparsehash][]       — a cache friendly `hash_map`
 * the `xcodeproj` gem  — authors the generated `.xcodeproj`

```sh
brew install boost capnp google-sparsehash multimarkdown ragel
gem install --user-install xcodeproj
```

TextMate-NG is **Apple Silicon only** (see the "Decided" section of
`PROJECT_PHASES.md` for why); building on Intel is not supported.

After installing dependencies, make sure you have a full checkout (including
submodules), then generate and build the Xcode project:

```sh
git clone --recursive https://github.com/johnmcgovern/textmate-ng.git
cd textmate-ng
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 RUBYOPT="-EUTF-8"
ruby ide/extract_specs.rb > ide/gen/specs.json && ruby ide/seed_xcodeproj.rb
xcodebuild -project TextMate.xcodeproj -target TextMate -configuration Release build
open build/Release/TextMate-NG.app
```

`TextMate.xcodeproj` is generated, not committed — regenerate it any time with
the two `ruby` commands above (`ide/extract_specs.rb` parses the `default.rave`
spec files that describe the target graph; `ide/seed_xcodeproj.rb` authors the
`.pbxproj` from that). Re-running is safe: it rebuilds the project from scratch.

## Running the test suite

```sh
xcodebuild test -project TextMate.xcodeproj -scheme AllTests -configuration Debug
```

## Building from within TextMate

Open `TextMate.xcodeproj` in Xcode and use its own Run/Test actions (⌘R/⌘U). The
`.tm_properties`-driven ⌘B-to-build-a-ninja-target workflow described by older
versions of this document no longer applies.

# Legal

The source for TextMate is released under the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

TextMate is a trademark of Allan Odgaard.

[boost]:         http://www.boost.org/
[multimarkdown]: http://fletcherpenney.net/multimarkdown/
[ragel]:         http://www.complang.org/ragel/
[capnp]:         https://github.com/capnproto/capnproto.git
[sparsehash]:    https://code.google.com/p/sparsehash/
[#textmate]:     irc://irc.freenode.net/#textmate
[freenode.net]:  http://freenode.net/
