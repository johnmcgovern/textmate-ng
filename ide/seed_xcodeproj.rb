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

ROOT      = File.expand_path("..", __dir__)
PROJ_PATH = File.join(ROOT, "TextMate.xcodeproj")

# --- environment-derived include/lib paths (see textmate-build-setup memory) ---
HOME       = ENV["HOME"]
NIX_ARM    = "#{HOME}/nix-sdk/arm64"
NIX_X86    = "#{HOME}/nix-sdk/x86_64"    # boost (header-only) lives only here
DEPLOY_TGT = "15.0"                       # migration floor (Stream 4); also > SDK min 10.13

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

GEN_INCLUDE = "ide/gen/include"           # generated <fw/header.h> symlink farm

# NOTE: the generated <fw/header.h> farm is deliberately NOT here. Adding the flat
# farm root to every target lets one framework's dir shadow a same-named *system*
# framework (e.g. TM's `network` fw shadows Apple's <Network/Network.h>, which the
# WebKit PCH pulls in) — this broke AllLibs. Instead each target gets ONLY the farm
# dirs for its transitive require closure (see header_closure), mirroring rave's
# per-target `-I _Include/<fw>` scoping.
COMMON_HEADER_PATHS = [
  "$(SRCROOT)/Shared/include",
  "$(DERIVED_FILE_DIR)",                   # generated capnp/ragel headers
  "#{NIX_ARM}/include",                    # capnp, kj, sparsehash, google
  "#{NIX_X86}/include",                    # boost (header-only; arch-independent)
]

# External `libraries X` -> linker flags. capnp/kj come from nix-sdk; the rest
# from the macOS SDK.
LIB_LDFLAGS = {
  "capnp" => ["-lcapnp"], "kj" => ["-lkj"],
  "curl" => ["-lcurl"], "iconv" => ["-liconv"],
  "sqlite3" => ["-lsqlite3"], "z" => ["-lz"],
}

SKIP_TARGETS = %w[NewApplication].freeze  # bare Xcode template, not a real target

# ---------------------------------------------------------------------------
specs = JSON.parse(File.read(File.join(ROOT, GEN_INCLUDE, "..", "specs.json")))
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
  FileUtils.rm_rf(farm)
  specs.each do |spec|
    next if spec["headers"].empty?
    # Double-nested (rave's _Include/<fw>/<fw>/*.h): the *search dir* added to a
    # target is ide/gen/include/<fw>, and it contains only a <fw>/ subdir. So
    # `<fw/header.h>` resolves here, but a same-named system framework umbrella
    # (e.g. <Network/Network.h>) does NOT — unless <fw> is on this target's path.
    dest_dir = File.join(farm, spec["name"], spec["name"])
    FileUtils.mkdir_p(dest_dir)
    spec["headers"].each do |rel|
      link = File.join(dest_dir, File.basename(rel))
      FileUtils.ln_s(File.join(ROOT, rel), link) unless File.exist?(link)
    end
  end
  puts "built include farm for #{specs.count { |s| !s['headers'].empty? }} targets"
end

def make_build_rules(project)
  nix_path = %(export PATH="$HOME/.nix-profile/bin:$PATH")

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
  bs["HEADER_SEARCH_PATHS"]         = ["$(inherited)"] + COMMON_HEADER_PATHS
  bs["LIBRARY_SEARCH_PATHS"]        = ["$(inherited)", "#{NIX_ARM}/lib"]
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
    bs["HEADER_SEARCH_PATHS"] += header_closure(t["name"]).map { |d| "$(SRCROOT)/#{GEN_INCLUDE}/#{d}" }
    bs["OTHER_CFLAGS"] += per_target_cflags unless per_target_cflags.empty?
    bs["OTHER_CPLUSPLUSFLAGS"] = ["$(inherited)"] + per_target_cxxflags unless per_target_cxxflags.empty?
    if k == :plugin || k == :qlgen
      bs["WRAPPER_EXTENSION"] = (k == :qlgen ? "qlgenerator" : "tmplugin")
      bs["MACH_O_TYPE"] = "mh_bundle"
      ip = infoplist_for(t)
      bs["INFOPLIST_FILE"] = "$(SRCROOT)/#{ip}" if ip
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

  target.build_configurations.each do |config|
    bs = config.build_settings
    bs["OTHER_LDFLAGS"] = ["$(inherited)"] + ld_libs + ld_fw
  end
  puts "linked #{t['name']} [#{k}]: #{closure.size} libs, #{ext_libs.size} ext-libs, #{fworks.size} frameworks"
end

# Aggregate to compile-check every static library at once.
all_libs = project.new_aggregate_target("AllLibs", [], :osx, DEPLOY_TGT)
specs.select { |t| kind(t) == :lib }.each { |t| all_libs.add_dependency(targets[t["name"]]) }

project.save
puts "wrote #{PROJ_PATH} (#{targets.size} targets)"
