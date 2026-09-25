# Vendored from textmate/dialog-1.x

This directory was a git submodule of <https://github.com/textmate/dialog-1.x>
until 2026-09-24. It is now ordinary tracked source, taken verbatim from the
commit the submodule was pinned to:

    43df3148ed451774298af6965b6b71e43630ba8e

**Why.** This legacy 1.x plug-in still ships and is still used: `tm_dialog2`
forwards any old-style `-switch` invocation to it, and the shared Ruby UI library
(`TextMate::UI` in the Bundle Support bundle) drives async nib windows and
progress dialogs through it, as do the SQL and Objective-C bundles. It used
Distributed Objects with the same always-on, guessable-name exposure the 2.x
plug-in had, so it is hardened onto an owner-only socket in place — which means
changing a repository this project does not own, so the code is brought in.
Upstream has not moved since March 2021.

**License.** The repository declares no license file of its own. It is the same
TextMate/MacroMates dialog lineage as `PlugIns/dialog`, whose `README.mdown`
grants "permission to copy, use, modify, sell and distribute this software."
Changes made here are recorded in this repository's history.
