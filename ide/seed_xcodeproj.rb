#!/usr/bin/env ruby
# frozen_string_literal: true
#
# One-shot seeder for the hand-authored TextMate.xcodeproj (Phase 2 / Stream 1).
#
# Rationale: the user chose a hand-authored .xcodeproj (Apple-native format) over
# XcodeGen/Tuist/SPM. The agreed tactic is "seed programmatically once, then
# maintain natively." This uses the `xcodeproj` gem (the library CocoaPods uses
# to author real .pbxproj files) to lay down the initial project from the target
# graph extracted out of the .rave specs (ide/extract_specs.rb -> ide/gen/specs.json).
#
# Run:  ruby ide/extract_specs.rb > ide/gen/specs.json && ruby ide/seed_xcodeproj.rb
# Deps: gem install --user-install xcodeproj
#
# Re-runnable: regenerates TextMate.xcodeproj from scratch each time.

require "xcodeproj"
require "pathname"
require "fileutils"
require "json"
require "set"

ROOT      = File.expand_path("..", __dir__)
PROJ_PATH = File.join(ROOT, "TextMate.xcodeproj")

# --- dependency prefixes (Stream 2: reproducible deps, not user-local) --------
# The external deps (capnp, kj, boost, sparsehash) resolve from one or more
# "prefix" dirs, each contributing <prefix>/include and <prefix>/lib. Resolution
# mirrors ./configure so the Xcode build matches the rave/CI build on a clean
# machine:
#   * default  -> Homebrew's prefix (`brew --prefix`): /opt/homebrew on Apple
#                 Silicon, /usr/local on Intel; /usr/local if brew is absent.
#   * override -> TM_DEP_PREFIX, a colon-separated list, for non-Homebrew setups.
#                 e.g. the local nix-sdk sandbox (see textmate-build-setup memory):
#                 TM_DEP_PREFIX="$HOME/nix-sdk/arm64:$HOME/nix-sdk/x86_64"
#                 (boost is header-only and lives only under the x86_64 prefix).
HOME       = ENV["HOME"]
DEP_PREFIXES =
  if (env = ENV["TM_DEP_PREFIX"].to_s.strip) != ""
    env.split(":").map(&:strip).reject(&:empty?)
  else
    brew = `brew --prefix 2>/dev/null`.strip
    [brew.empty? ? "/usr/local" : brew]
  end
DEPLOY_TGT = "15.0"                       # migration floor (Stream 4); also > SDK min 10.13

# App version, captured the way rave does (grep the latest Changes.md heading). Fed
# to the app Info.plist as the ${APP_VERSION} build-setting expansion.
APP_VERSION = (File.read(File.join(File.expand_path("..", __dir__),
                "Applications/TextMate/about/Changes.md"))[/^## .* \(v(.*)\)$/, 1] || "0.0.0")

# Preprocessor defs from default.rave's global FLAGS. Passed as verbatim -D tokens
# in OTHER_CFLAGS (GCC_PREPROCESSOR_DEFINITIONS strips the inner quotes that make
# NULL_STR a C string literal). Backslash-escaped so quotes survive xcodebuild's
# one round of shell-splitting.
GLOBAL_DEFINE_FLAGS = [
  %q{-DNULL_STR=\"￿\"},
  %q{-DREST_API=\"https://api.textmate.org\"},
]

# Language-dispatching prefix header (Shared/PCH/prelude.h) routes to
# prelude.c/.cc/.m/.mm by TU language, so one target mixes all four (plus
# generated .capnp.cpp/.cc) under a single GCC_PREFIX_HEADER.
PREFIX_HEADER = "Shared/PCH/prelude.h"

GEN_DIR         = "ide/gen"               # generated artifacts (gitignored)
GEN_INCLUDE     = "#{GEN_DIR}/include"     # generated <fw/header.h> symlink farm
GEN_INCLUDE_NOU = "#{GEN_DIR}/include-nou" # variant farm w/o the <fw>.h umbrella, for
                                          # system-colliding frameworks on WebKit-pulling
                                          # targets (see header_farm_dirs / option 4)

# System frameworks (lowercased) in the active SDK. A TM framework whose name
# case-collides with one of these (e.g. `network` vs Apple's Network.framework)
# must NOT be blanket-added to every requiring target's -I path: on case-insensitive
# APFS it would shadow the system header that the WebKit PCH pulls in
# (<Network/Network.h>, a newer-SDK addition). Such a farm dir is added only to
# targets that actually include <fw/...> themselves (see header_farm_dirs).
SYSTEM_FRAMEWORKS = Dir.glob(File.join(`xcrun --sdk macosx --show-sdk-path`.strip,
  "System/Library/Frameworks/*.framework")).map { |p| File.basename(p, ".framework").downcase }.to_set

# NOTE: the generated <fw/header.h> farm is deliberately NOT here. Adding the flat
# farm root to every target lets one framework's dir shadow a same-named *system*
# framework (e.g. TM's `network` fw shadows Apple's <Network/Network.h>, which the
# WebKit PCH pulls in) — this broke AllLibs. Instead each target gets ONLY the farm
# dirs for its transitive require closure (see header_closure), mirroring rave's
# per-target `-I _Include/<fw>` scoping.
COMMON_HEADER_PATHS = [
  "$(SRCROOT)/Shared/include",
  "$(DERIVED_FILE_DIR)",                   # generated capnp/ragel headers
  *DEP_PREFIXES.map { |p| "#{p}/include" }, # capnp, kj, sparsehash, google, boost
]

# External `libraries X` -> linker flags. capnp/kj come from the dep prefix(es)
# (see DEP_PREFIXES); the rest from the macOS SDK.
LIB_LDFLAGS = {
  "capnp" => ["-lcapnp"], "kj" => ["-lkj"],
  "curl" => ["-lcurl"], "iconv" => ["-liconv"],
  "sqlite3" => ["-lsqlite3"], "z" => ["-lz"],
}

SKIP_TARGETS = %w[NewApplication].freeze  # bare Xcode template, not a real target

# ---------------------------------------------------------------------------
specs = JSON.parse(File.read(File.join(ROOT, GEN_DIR, "specs.json")))
                .reject { |t| SKIP_TARGETS.include?(t["name"]) }
BY_NAME = specs.each_with_object({}) { |t, h| h[t["name"]] = t }

def kind(t)
  p = t["prefix"]; e = t["executable"]
  return :app    if p&.include?(".app/")
  return :qlgen  if p&.include?(".qlgenerator")
  return :plugin if p&.include?(".tmplugin") || t["ln_flags"].include?("-bundle")
  return :tool   if e
  :lib
end

# Transitive closure of `require` over lib targets (headers come from the farm;
# this set is what an executable/bundle must link).
def lib_closure(name, seen = {})
  t = BY_NAME[name]
  return seen unless t
  (t["require"] + t["require_headers"]).each do |dep|
    next if seen[dep] || dep == name
    seen[dep] = true if BY_NAME[dep] && kind(BY_NAME[dep]) == :lib
    lib_closure(dep, seen)
  end
  seen
end

# Transitive closure over `require` + `require_headers` (mirrors rave's
# required_targets(include_weak: true), excluding self). These are the frameworks
# whose farm include dirs a target may see. Scoping to this set — rather than the
# whole farm — is what stops same-named system frameworks from being shadowed.
def header_closure(name)
  seen = {}
  root = BY_NAME[name]
  queue = (root["require"] + root["require_headers"]).dup
  until queue.empty?
    dep = queue.shift
    next if seen[dep] || dep == name
    seen[dep] = true
    t = BY_NAME[dep] or next
    queue.concat(t["require"] + t["require_headers"])
  end
  seen.keys.select { |d| BY_NAME[d] && !BY_NAME[d]["headers"].empty? }
end

# Does target t's own sources/headers angle-include <fw/...>?
def target_includes?(t, fw)
  re = /#\s*(?:include|import)\s*<#{Regexp.escape(fw)}\//i
  (t["sources"] + t["headers"]).uniq.any? do |rel|
    path = File.join(ROOT, rel)
    File.file?(path) && File.foreach(path).any? { |ln| ln =~ re }
  end
end

# ObjC/ObjC++ sources compile with prelude.m/.mm, which #import <WebKit/WebKit.h> —
# and on the current SDK that transitively pulls <Network/Network.h>. So a target
# with any .m/.mm source is a "WebKit-pulling" target.
def pulls_webkit?(t)
  t["sources"].any? { |rel| rel.end_with?(".m", ".mm") }
end

# The farm include dirs a target compiles with: its transitive header closure. A
# system-colliding framework (e.g. `network` vs Apple's Network.framework) is only
# added when the target actually includes <fw/...> (else it would shadow the system
# header). When such a target ALSO pulls WebKit, it uses the no-umbrella variant
# farm so <Network/Network.h> resolves to Apple, not TM (option 4).
def header_farm_dirs(t)
  header_closure(t["name"]).map do |fw|
    if SYSTEM_FRAMEWORKS.include?(fw.downcase)
      next nil unless target_includes?(t, fw)
      base = pulls_webkit?(t) ? GEN_INCLUDE_NOU : GEN_INCLUDE
      "$(SRCROOT)/#{base}/#{fw}"
    else
      "$(SRCROOT)/#{GEN_INCLUDE}/#{fw}"
    end
  end.compact
end

# Rewrite relative -I flags to $(SRCROOT)-anchored ones for Xcode.
def fix_include_flags(flags)
  flags.map do |f|
    if f.start_with?("-I") && !f[2..].start_with?("/", "$")
      "-I$(SRCROOT)/#{f[2..]}"
    else
      f
    end
  end
end

def build_include_farm(specs)
  farm = File.join(ROOT, GEN_INCLUDE)
  nou  = File.join(ROOT, GEN_INCLUDE_NOU)
  FileUtils.rm_rf(farm)
  FileUtils.rm_rf(nou)
  specs.each do |spec|
    next if spec["headers"].empty?
    # Double-nested (rave's _Include/<fw>/<fw>/*.h): the *search dir* added to a
    # target is ide/gen/include/<fw>, and it contains only a <fw>/ subdir. So
    # `<fw/header.h>` resolves here, but a same-named system framework umbrella
    # (e.g. <Network/Network.h>) does NOT — unless <fw> is on this target's path.
    dest_dir = File.join(farm, spec["name"], spec["name"])
    FileUtils.mkdir_p(dest_dir)
    # For system-colliding frameworks (e.g. `network`), also build a variant farm
    # that omits the <fw>.h umbrella. A WebKit-pulling target that includes <fw/...>
    # uses this variant so the umbrella include the SDK does (<Network/Network.h>)
    # falls through to the real system framework instead of TM's header.
    colliding = SYSTEM_FRAMEWORKS.include?(spec["name"].downcase)
    umbrella  = "#{spec['name'].downcase}.h"
    nou_dir   = File.join(nou, spec["name"], spec["name"])
    FileUtils.mkdir_p(nou_dir) if colliding
    spec["headers"].each do |rel|
      base = File.basename(rel)
      src  = File.join(ROOT, rel)
      link = File.join(dest_dir, base)
      FileUtils.ln_s(src, link) unless File.exist?(link)
      if colliding && base.downcase != umbrella
        nlink = File.join(nou_dir, base)
        FileUtils.ln_s(src, nlink) unless File.exist?(nlink)
      end
    end
  end
  puts "built include farm for #{specs.count { |s| !s['headers'].empty? }} targets"
end

# The capnp/ragel codegen tools are invoked by name inside Xcode script build
# rules, whose PATH is sanitized and excludes Homebrew's bin. Prepend every dep
# prefix's bin (Homebrew: `<brew>/bin` has capnp + ragel) plus the nix-profile
# bin (where they live on the nix dev box). Non-existent entries are harmless.
TOOL_BIN_DIRS = (DEP_PREFIXES.map { |p| "#{p}/bin" } + ["$HOME/.nix-profile/bin"]).uniq

def make_build_rules(project)
  nix_path = %(export PATH="#{TOOL_BIN_DIRS.join(":")}:$PATH")

  capnp = project.new(Xcodeproj::Project::Object::PBXBuildRule)
  capnp.compiler_spec = "com.apple.compilers.proxy.script"
  capnp.file_type = "pattern.proxy"
  capnp.file_patterns = "*.capnp"
  capnp.is_editable = "1"
  capnp.output_files = [
    "$(DERIVED_FILE_DIR)/$(INPUT_FILE_BASE).capnp.cpp",
    "$(DERIVED_FILE_DIR)/$(INPUT_FILE_BASE).capnp.h",
  ]
  capnp.script = <<~SH
    #{nix_path}
    capnp compile -oc++:"$DERIVED_FILE_DIR" --src-prefix="$INPUT_FILE_DIR" "$INPUT_FILE_PATH"
    mv "$DERIVED_FILE_DIR/$INPUT_FILE_BASE.capnp.c++" "$DERIVED_FILE_DIR/$INPUT_FILE_BASE.capnp.cpp"
  SH

  ragel = project.new(Xcodeproj::Project::Object::PBXBuildRule)
  ragel.compiler_spec = "com.apple.compilers.proxy.script"
  ragel.file_type = "pattern.proxy"
  ragel.file_patterns = "*.rl"
  ragel.is_editable = "1"
  ragel.output_files = ["$(DERIVED_FILE_DIR)/$(INPUT_FILE_BASE).cc"]
  ragel.script = <<~SH
    #{nix_path}
    ragel -o "$DERIVED_FILE_DIR/$INPUT_FILE_BASE.cc" "$INPUT_FILE_PATH"
  SH

  [capnp, ragel]
end

def apply_common_settings(config, extra = {})
  bs = config.build_settings
  bs["SDKROOT"]                     = "macosx"
  bs["MACOSX_DEPLOYMENT_TARGET"]    = DEPLOY_TGT
  bs["ARCHS"]                       = "arm64"
  bs["ONLY_ACTIVE_ARCH"]            = "YES"
  bs["CLANG_CXX_LANGUAGE_STANDARD"] = "c++2a"
  bs["GCC_C_LANGUAGE_STANDARD"]     = "c99"
  bs["CLANG_ENABLE_OBJC_ARC"]       = "YES"
  bs["GCC_CHAR_IS_UNSIGNED_CHAR"]   = "YES"
  bs["CLANG_ENABLE_MODULES"]        = "NO"
  bs["ALWAYS_SEARCH_USER_PATHS"]    = "NO"   # keep USER_HEADER_SEARCH_PATHS quote-only (-iquote)
  bs["CODE_SIGN_IDENTITY"]          = "-"    # ad-hoc (rave CS_IDENTITY); enough for a local launchable build
  bs["APP_MIN_OS"]                  = DEPLOY_TGT  # for ${APP_MIN_OS} expansion in Info.plist templates
  bs["HEADER_SEARCH_PATHS"]         = ["$(inherited)"] + COMMON_HEADER_PATHS
  bs["LIBRARY_SEARCH_PATHS"]        = ["$(inherited)", *DEP_PREFIXES.map { |p| "#{p}/lib" }]
  bs["OTHER_CFLAGS"]                = [
    "$(inherited)", *GLOBAL_DEFINE_FLAGS,
    "-Wno-parentheses", "-Wno-sign-compare", "-Wno-switch", "-Wno-c99-designator",
  ]
  bs["GCC_PRECOMPILE_PREFIX_HEADER"] = "YES"
  bs["GCC_PREFIX_HEADER"]            = "$(SRCROOT)/#{PREFIX_HEADER}"
  extra.each { |k, v| bs[k] = v }
end

def dir_of(rel)
  "$(SRCROOT)/#{File.dirname(rel)}"
end

# The Info.plist a bundle/app declares among its `files` (dest "." inputs). rave
# copies it to Contents/Info.plist; in Xcode that's the INFOPLIST_FILE setting, and
# Xcode auto-expands ${TARGET_NAME} etc. from build settings (no cpp preprocess).
def infoplist_for(t)
  (t["files"] || []).each do |f|
    (f["inputs"] || []).each { |i| return i if File.basename(i) == "Info.plist" }
  end
  nil
end

# The app's Entitlements.plist is a template with ${CS_GET_TASK_ALLOW}. Xcode won't
# reliably expand a custom var inside an entitlements file, so pre-substitute it
# (release => false, per default.rave `config release`) into a concrete generated
# file and point CODE_SIGN_ENTITLEMENTS at that. Returns the SRCROOT-relative path.
def generate_entitlements(name, src_rel)
  out_rel = "#{GEN_INCLUDE.sub('include', 'entitlements')}/#{name}.plist"
  out_abs = File.join(ROOT, out_rel)
  FileUtils.mkdir_p(File.dirname(out_abs))
  File.write(out_abs, File.read(File.join(ROOT, src_rel)).gsub("${CS_GET_TASK_ALLOW}", "false"))
  out_rel
end

# ---------------------------------------------------------------------------
build_include_farm(specs)

project = Xcodeproj::Project.new(PROJ_PATH)
targets = {}

PRODUCT_TYPE = { lib: :static_library, tool: :command_line_tool,
                 app: :application, plugin: :bundle, qlgen: :bundle }.freeze

# Pass 1: create every target with its sources + compile settings.
specs.each do |t|
  k = kind(t)
  target = project.new_target(PRODUCT_TYPE[k], t["name"], :osx, DEPLOY_TGT)
  # Append with << (NOT ObjectList#replace): replace fails to parent the rule
  # objects, so they drop out of the object graph on save and every target ends up
  # referencing dangling UUIDs — Xcode then reports "no rule to process file" for
  # *.capnp / *.rl. Fresh objects per target (a shared rule reparents away).
  make_build_rules(project).each { |rule| target.build_rules << rule }
  targets[t["name"]] = target

  group = project.main_group.new_group(t["name"], t["dir"])
  t["sources"].each do |rel|
    ref = group.new_file(File.join(ROOT, rel))
    target.source_build_phase.add_file_reference(ref)
  end

  own_dirs = t["sources"].map { |rel| dir_of(rel) }.uniq
  per_target_cflags = fix_include_flags(t["flags"] + t["c_flags"])
  per_target_cxxflags = fix_include_flags(t["cxx_flags"])

  target.build_configurations.each do |config|
    extra = { "PRODUCT_NAME" => t["name"] }
    if config.name == "Release"
      extra["GCC_OPTIMIZATION_LEVEL"] = "s"
      # rave's `config release` defines NDEBUG (default.rave). This compiles out the
      # oak/debug asserts + debug-log paths that reference OakBadAssertion /
      # oak::to_s — symbols that live in libOakDebug.a, which release deliberately
      # does NOT link (OakDebug is `require`d only in `config debug`). Without this,
      # executables fail to link with undefined oak::* symbols.
      extra["GCC_PREPROCESSOR_DEFINITIONS"] = ["$(inherited)", "NDEBUG"]
    end
    apply_common_settings(config, extra)
    bs = config.build_settings
    # Own source dirs go on the QUOTE-only path (-iquote), not -I: a framework's
    # `#include "foo.h"` resolves here, but a system `<glob.h>` / `<version.h>` pulled
    # in by the prelude must NOT resolve to a same-named header in the target's own
    # src dir (e.g. regexp/src/glob.h shadowing POSIX <glob.h>).
    bs["USER_HEADER_SEARCH_PATHS"] = ["$(inherited)"] + own_dirs
    bs["HEADER_SEARCH_PATHS"] += header_farm_dirs(t)
    bs["OTHER_CFLAGS"] += per_target_cflags unless per_target_cflags.empty?
    bs["OTHER_CPLUSPLUSFLAGS"] = ["$(inherited)"] + per_target_cxxflags unless per_target_cxxflags.empty?
    if k == :plugin || k == :qlgen
      bs["WRAPPER_EXTENSION"] = (k == :qlgen ? "qlgenerator" : "tmplugin")
      bs["MACH_O_TYPE"] = "mh_bundle"
      ip = infoplist_for(t)
      bs["INFOPLIST_FILE"] = "$(SRCROOT)/#{ip}" if ip
    end
    if k == :app
      ip = infoplist_for(t)
      bs["INFOPLIST_FILE"] = "$(SRCROOT)/#{ip}" if ip
      # Mirror the Info.plist's CFBundleIdentifier (com.macromates.${TARGET_NAME})
      # so Xcode stops warning that the plist id differs from an empty
      # PRODUCT_BUNDLE_IDENTIFIER. NOTE (Stream 3): `com.macromates.*` is MacroMates'
      # identifier — TextMate-NG must switch to its own id under our Apple Developer
      # account before notarization. When that happens, change BOTH this setting and
      # Applications/TextMate/Info.plist's CFBundleIdentifier together.
      bs["PRODUCT_BUNDLE_IDENTIFIER"] = "com.macromates.$(TARGET_NAME)"
      bs["APP_VERSION"] = APP_VERSION                 # ${APP_VERSION} in Info.plist
      if t["entitlements"] && !t["entitlements"].empty?
        bs["CODE_SIGN_ENTITLEMENTS"] = "$(SRCROOT)/#{generate_entitlements(t['name'], t['entitlements'])}"
      end
    end
  end
  puts "target #{t['name']} [#{k}] (#{t['sources'].size} src)"
end

# Pass 2: link wiring for executables & loadable bundles (tools/plugins/qlgen/app).
# Each static lib in the link closure is added to the Frameworks build phase (so it
# links) plus a target dependency (so it builds first). We deliberately add NO
# lib<->lib edges (Xcode forbids cycles; ld64 resolves static-archive cycles at
# link time). External `libraries` and `frameworks` are unioned over the closure +
# the target itself and passed as -l… / -framework … in OTHER_LDFLAGS.
specs.each do |t|
  k = kind(t)
  next if k == :lib
  target = targets[t["name"]]

  closure = lib_closure(t["name"]).keys        # lib target names to link
  closure.each do |lib|
    lt = targets[lib] or next
    target.frameworks_build_phase.add_file_reference(lt.product_reference)
    target.add_dependency(lt)
  end

  link_scope = closure + [t["name"]]
  ext_libs = link_scope.flat_map { |n| BY_NAME[n] ? BY_NAME[n]["libraries"] : [] }.uniq
  ld_libs  = ext_libs.flat_map { |l| LIB_LDFLAGS[l] || (warn("*** no LIB_LDFLAGS mapping for '#{l}' (#{t['name']})"); []) }
  fworks   = link_scope.flat_map { |n| BY_NAME[n] ? BY_NAME[n]["frameworks"] : [] }.uniq
  ld_fw    = fworks.flat_map { |f| ["-framework", f] }

  # Per-target `ln_flags` propagate to whatever links the target (rave semantics),
  # e.g. license's `-Wl,-U,__Z15revoked_serialsv` (allow the weak-import
  # revoked_serials() to be undefined). `-bundle` is excluded — it's a product-type
  # marker already handled by MACH_O_TYPE, not something to force onto an executable.
  ld_extra = link_scope.flat_map { |n| BY_NAME[n] ? BY_NAME[n]["ln_flags"] : [] }
                       .uniq.reject { |f| f == "-bundle" }

  target.build_configurations.each do |config|
    bs = config.build_settings
    bs["OTHER_LDFLAGS"] = ["$(inherited)"] + ld_libs + ld_fw + ld_extra
  end
  puts "linked #{t['name']} [#{k}]: #{closure.size} libs, #{ext_libs.size} ext-libs, #{fworks.size} frameworks"
end

# Pass 3: bundle layout for app/plugin/qlgen targets. Each `files`/`copy` entry
# becomes a Copy Files build phase. Plain inputs are copied from source; @refs are
# built products (tools/bundles) copied in + a target dependency so they build
# first. The Info.plist entry is skipped (handled by INFOPLIST_FILE in Pass 1).
def copy_dest(dest)
  case dest
  when "Resources"     then [:resources, ""]
  when "MacOS"         then [:executables, ""]
  when "PlugIns"       then [:plug_ins, ""]
  when "SharedSupport" then [:shared_support, ""]
  when "."             then [:wrapper, "Contents"]     # :wrapper is the .app ROOT
  when %r{\AResources/(.+)\z} then [:resources, $1]
  else [:wrapper, "Contents/#{dest}"]                  # e.g. Contents/Library/QuickLook
  end
end

specs.each do |t|
  k = kind(t)
  next unless [:app, :plugin, :qlgen].include?(k)
  target = targets[t["name"]]
  (t["files"] + t["copy"]).each do |entry|
    inputs = (entry["inputs"] || []).reject { |i| File.basename(i) == "Info.plist" }
    refs   = entry["refs"] || []
    next if inputs.empty? && refs.empty?
    spec, sub = copy_dest(entry["dest"])
    phase = target.new_copy_files_build_phase("Copy to #{entry['dest']}")
    phase.symbol_dst_subfolder_spec = spec
    phase.dst_path = sub
    inputs.each do |rel|
      phase.add_file_reference(project.main_group.new_file(File.join(ROOT, rel)))
    end
    refs.each do |r|
      rt = targets[r.sub(/\A@/, "")] or next   # refs carry an `@` prefix in the spec
      phase.add_file_reference(rt.product_reference)
      target.add_dependency(rt)
    end
  end
  puts "bundled #{t['name']} [#{k}]"
end

# Aggregate to compile-check every static library at once.
all_libs = project.new_aggregate_target("AllLibs", [], :osx, DEPLOY_TGT)
specs.select { |t| kind(t) == :lib }.each { |t| all_libs.add_dependency(targets[t["name"]]) }

project.save
puts "wrote #{PROJ_PATH} (#{targets.size} targets)"
