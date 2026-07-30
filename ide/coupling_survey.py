#!/usr/bin/env python3
"""Phase 4 coupling survey — how hard is each UI framework to port to Swift?

Run:  python3 ide/coupling_survey.py
Needs ide/gen/specs.json (ruby ide/extract_specs.rb > ide/gen/specs.json).

Why this exists: the Phase 4 roadmap originally ordered frameworks by `wc -l`,
and that misled badly. BundleEditor looked like a 1.3k-line leaf and turned out
to keep its entire model in C++ (be::entry_t browser tree, plist::dictionary_t
property bags) plus two constructs Swift cannot express at all. Line count
measures typing; these columns measure the things that actually cost time.

Columns, roughly in order of how much they hurt:

  cbk    C++ structs subclassed to receive callbacks (bundles::callback_t &c).
         Swift cannot subclass a C++ type with virtual methods — always a shim.
  load   +load implementations. Swift has no equivalent. Cheap if the body is a
         one-line registration (FileBrowser), expensive if it encodes an
         ordering guarantee (BundleEditor).
  objc   Swift-impossible *ObjC* constructs, independent of C++: NSProxy
         subclasses and NSInvocation (which Swift cannot import at all), and
         C-variadic methods. Added after OakTabBarView — which scored a clean 3
         — turned out to contain an NSProxy/NSInvocation animator shim. The
         C++-only columns missed it entirely.
  state  C++ ivars + @properties. This is the BundleEditor killer: when the
         class's *state* is C++, porting means writing an ObjC model layer
         first, which is new code that exists only to let Swift drive C++.
  sigs   ObjC method signatures mentioning C++ types. A Swift class cannot
         implement these as @objc, so each one needs an adapter or a rewritten
         signature. Cross-target ones (in public headers) are worse.
  pubAPI Whether the public headers parse as plain ObjC. NOT a blocker on its
         own — our bridging headers use SWIFT_OBJC_INTEROP_MODE=objcxx and can
         read C++ — but "direct" means consumers face no interop questions.
  xib    Nib contracts. Cheap to get wrong, now cheap to test (Pass 4 copies
         framework resources into test bundles as of 2026-07-28).
"""
import glob, json, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

# Phase 4 scope: the ObjC++ UI frameworks. OakTextView is included as a control —
# it is the one the roadmap says stays ObjC++, so it should rank worst.
UI = ["HTMLOutputWindow", "MenuBuilder", "CrashReporter", "BundleMenu", "OakTabBarView",
      "SoftwareUpdate", "TMFileReference", "OakCommand", "HTMLOutput", "BundlesManager",
      "OakFilterList", "Find", "BundleEditor", "DocumentWindow", "OakAppKit",
      "FileBrowser", "OakTextView"]

CXX = re.compile(
    r'\b(?:std|boost|bundles|plist|text|io|ns|cf|scope|scm|regexp|settings|command|document'
    r'|oak|be|theme|layout|ng|encoding|network|parse|file|selection|editor|buffer|find)::'
    r'|^\s*namespace\s|^\s*(?:struct|class|template)\s')


def public_headers(fw):
    """Expand the rave `headers` globs, including {a,b} brace syntax (glob won't)."""
    rave = f"Frameworks/{fw}/default.rave"
    m = re.search(r'^\s*headers\s+(.+)$', open(rave).read(), re.M) if os.path.exists(rave) else None
    if not m:
        return []
    out = []
    for pat in m.group(1).split():
        b = re.search(r'\{([^}]*)\}', pat)
        for p in ([pat.replace(b.group(0), a) for a in b.group(1).split(",")] if b else [pat]):
            out += [f for f in glob.glob(f"Frameworks/{fw}/{p}", recursive=True) if f.endswith(".h")]
    return sorted(set(out))


def objc_include_flags():
    specs = json.load(open("ide/gen/specs.json"))
    sdk = subprocess.run(["xcrun", "--sdk", "macosx", "--show-sdk-path"],
                         capture_output=True, text=True).stdout.strip()
    sysfw = {os.path.basename(p)[:-10].lower()
             for p in glob.glob(f"{sdk}/System/Library/Frameworks/*.framework")}
    brew = subprocess.run(["brew", "--prefix"], capture_output=True, text=True).stdout.strip() or "/usr/local"
    incs = ["-I", ".", "-I", "Shared/include", "-I", f"{brew}/include"]
    for t in specs:
        if t["headers"]:
            # same no-umbrella variant the seed uses for system-colliding names
            base = "ide/gen/include-nou" if t["name"].lower() in sysfw else "ide/gen/include"
            incs += ["-I", f"{base}/{t['name']}"]
    return sdk, incs


def imports_as_plain_objc(fw, hdrs, sdk, incs):
    """Compile the public headers as Objective-C (not ObjC++). Failure => ObjC++ only."""
    if not hdrs:
        return None
    body = '#include "Shared/PCH/prelude.m"\n' + "".join(
        f'#import <{fw}/{os.path.basename(h)}>\n' for h in hdrs)
    with tempfile.NamedTemporaryFile("w", suffix=".m", delete=False) as f:
        f.write(body)
        path = f.name
    try:
        r = subprocess.run(["clang", "-x", "objective-c", "-fsyntax-only", "-fobjc-arc",
                            "-isysroot", sdk] + incs + [path], capture_output=True, text=True)
        return r.returncode == 0
    finally:
        os.unlink(path)


def analyze(fw, sdk, incs):
    src = f"Frameworks/{fw}/src"
    # Recurse. Four frameworks keep sources in subdirectories of src/ —
    # HTMLOutput/src/browser, FileBrowser, OakFilterList, scm — and two specs
    # already glob them with `src/**/*.mm`. A non-recursive glob here did not
    # merely undercount loc: every coupling metric below was computed from the
    # top-level files only, so a framework's C++ state, C++-typed signatures and
    # ObjC-only constructs could sit in a subdirectory and score zero. That is
    # how HTMLOutput came to be recommended as a ~715-line score-12 port when it
    # is ~1440 lines with a std::map in its public API. (Found 2026-07-29 while
    # acting on that recommendation.)
    impl = sorted(glob.glob(f"{src}/**/*.mm", recursive=True)
                  + glob.glob(f"{src}/**/*.cc", recursive=True)
                  + glob.glob(f"{src}/**/*.m", recursive=True))
    loc = sum(len(open(f, errors="ignore").read().splitlines()) for f in impl)

    ivar = prop = sig = load = cbk = objc = 0
    for f in impl + glob.glob(f"{src}/**/*.h", recursive=True):
        t = open(f, errors="ignore").read()
        load += len(re.findall(r'^\+\s*\(\s*void\s*\)\s*load\b', t, re.M))
        cbk += len(re.findall(r'\b\w+::callback_t\b', t))
        objc += len(re.findall(r':\s*NSProxy\b|\bNSInvocation\b|,\s*\.\.\.\s*\)', t))
        for line in t.splitlines():
            s = line.strip()
            if s.startswith("@property") and CXX.search(s):
                prop += 1
            elif re.match(r'^[-+]\s*\(', s) and CXX.search(s):
                sig += 1
        for blk in re.findall(r'@(?:interface|implementation)[^\n]*\n\{(.*?)\n\}', t, re.S):
            ivar += sum(1 for l in blk.splitlines() if CXX.search(l) and l.strip().endswith(";"))

    hdrs = public_headers(fw)
    return dict(fw=fw, loc=loc, state=ivar + prop, sig=sig, load=load, cbk=cbk, objc=objc,
                direct=imports_as_plain_objc(fw, hdrs, sdk, incs),
                nibs=len(glob.glob(f"Frameworks/{fw}/resources/**/*.xib", recursive=True)))


def main():
    if not os.path.exists("ide/gen/specs.json"):
        sys.exit("run: ruby ide/extract_specs.rb > ide/gen/specs.json")
    sdk, incs = objc_include_flags()
    rows = [analyze(fw, sdk, incs) for fw in UI]
    for r in rows:
        # weights reflect what actually cost time on the first three ports
        r["score"] = r["cbk"] * 100 + r["objc"] * 10 + r["load"] * 5 + r["state"] * 8 + r["sig"] + r["loc"] / 500

    print(f"{'framework':<18}{'loc':>6}{'pubAPI':>8}{'state':>7}{'sigs':>6}{'+load':>6}{'cbk':>5}{'objc':>6}{'xib':>5}{'score':>7}")
    print("-" * 74)
    for r in sorted(rows, key=lambda r: r["score"]):
        api = "direct" if r["direct"] else ("shim" if r["direct"] is not None else "—")
        print(f"{r['fw']:<18}{r['loc']:>6}{api:>8}{r['state']:>7}{r['sig']:>6}"
              f"{r['load']:>6}{r['cbk']:>5}{r['objc']:>6}{r['nibs']:>5}{r['score']:>7.0f}")
    print("\nLower score = easier port. See the module docstring for what each column means.")


if __name__ == "__main__":
    main()
