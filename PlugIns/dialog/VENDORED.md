# Vendored from textmate/dialog

This directory was a git submodule of <https://github.com/textmate/dialog> until
2026-09-24. It is now ordinary tracked source in this repository, taken verbatim
from the commit the submodule was pinned to:

    fa2f59e3a8dfe31edd975525d888e31e748ea7eb
    "Use NSTableViewStylePlain for completion menu when running on macOS 11"

**Why.** The one remaining use of Apple's deprecated WebView in the shipped
application was here — `Commands/tooltip/TMDHTMLTips.mm`, which draws HTML
tooltips — and changing it meant either changing a repository this project does
not own or bringing the code in. Upstream has not moved since April 2021. Like
the bundle mirror, this removes a dependency on something outside the project.

**License.** Unchanged: the terms at the top of README.mdown ("Permission to copy,
use, modify, sell and distribute this software is granted…") still apply, and are
kept with the files for that reason. Changes made here are recorded in this
repository's history rather than upstream's.
