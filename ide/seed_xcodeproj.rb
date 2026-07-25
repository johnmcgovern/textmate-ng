#!/usr/bin/env ruby
# frozen_string_literal: true
#
# One-shot seeder for the hand-authored TextMate.xcodeproj (Phase 2 / Stream 1).
#
# Rationale: the user chose a hand-authored .xcodeproj (Apple-native format) over
# XcodeGen/Tuist/SPM. The agreed tactic is "seed programmatically once, then
# maintain natively." This script uses the `xcodeproj` gem (the same library
# CocoaPods uses to author real .pbxproj files) to lay down the initial project.
# After seeding, the .xcodeproj is committed and edited in Xcode going forward.
#
# Run:  ruby ide/seed_xcodeproj.rb
# Deps: gem install --user-install xcodeproj
#
# It is re-runnable: it regenerates TextMate.xcodeproj from scratch each time so
# the seed stays reproducible while we iterate on it.

require "xcodeproj"
require "pathname"
require "fileutils"

ROOT      = File.expand_path("..", __dir__)
PROJ_PATH = File.join(ROOT, "TextMate.xcodeproj")

# --- environment-derived include/lib paths (see textmate-build-setup memory) ---
HOME       = ENV["HOME"]
NIX_ARM    = "#{HOME}/nix-sdk/arm64"
NIX_X86    = "#{HOME}/nix-sdk/x86_64"    # boost (header-only) lives only here
DEPLOY_TGT = "15.0"                       # migration floor (Stream 4); also > SDK min 10.13

# Preprocessor defs from default.rave's global FLAGS. Passed as verbatim -D tokens
# in OTHER_CFLAGS rather than GCC_PREPROCESSOR_DEFINITIONS, because the latter
# strips the inner quotes that make NULL_STR a C string literal ("￿").
# %q{} keeps the backslash literal (no escape processing).
GLOBAL_DEFINE_FLAGS = [
  %q{-DNULL_STR=\"￿\"},
  %q{-DREST_API=\"https://api.textmate.org\"},
]

# A generated symlink farm reproduces rave's cross-framework include model:
# code includes <fw/header.h>, resolved from ide/gen/include/<fw>/header.h.
GEN_INCLUDE = "ide/gen/include"

# Header search paths every target needs (project sources + vendored deps).
COMMON_HEADER_PATHS = [
  "$(SRCROOT)/Shared/include",
  "$(SRCROOT)/#{GEN_INCLUDE}",   # <fw/header.h> umbrella farm
  "$(DERIVED_FILE_DIR)",         # generated capnp/ragel headers land here
  "#{NIX_ARM}/include",          # capnp, kj, sparsehash, google
  "#{NIX_X86}/include",          # boost (header-only; arch-independent)
]

# ---------------------------------------------------------------------------
# Target specs. Growing outward from the leaf `text` lib, one slice at a time.
# type: :static_library for Frameworks/*; apps/tools/bundles come later.
#   headers_glob: which headers to expose under the <name>/ umbrella
#   deps:         other lib targets this one requires (build order + headers)
# ---------------------------------------------------------------------------
# Language-dispatching prefix header (see Shared/PCH/prelude.h) — one PCH that
# routes to prelude.c/.cc/.m/.mm by TU language, so a target can mix languages
# (and generated .capnp.cpp / .cc) under a single GCC_PREFIX_HEADER.
PREFIX_HEADER = "Shared/PCH/prelude.h"

LIB_SPECS = [
  {
    name: "text", dir: "Frameworks/text",
    sources_glob: ["Frameworks/text/src/*.cc"],
    headers_glob: ["Frameworks/text/src/*.h"],
    deps: [],
  },
  {
    name: "cf", dir: "Frameworks/cf",
    sources_glob: ["Frameworks/cf/src/*.cc"],
    headers_glob: ["Frameworks/cf/src/*.h"],
    deps: ["text"],
  },
  {
    name: "encoding", dir: "Frameworks/encoding",
    sources_glob: ["Frameworks/encoding/src/*.mm", "Frameworks/encoding/src/*.capnp"],
    headers_glob: ["Frameworks/encoding/src/encoding.h"],
    deps: [],
  },
]

# Custom build rules that reproduce rave's code generators. Each returns a
# PBXBuildRule; generated sources land in $(DERIVED_FILE_DIR) and are then
# compiled by Xcode's normal rules (proven by the encoding capnp target).
def make_build_rules(project)
  nix_path = %(export PATH="$HOME/.nix-profile/bin:$PATH")

  capnp = project.new(Xcodeproj::Project::Object::PBXBuildRule)
  capnp.compiler_spec = "com.apple.compilers.proxy.script"
  capnp.file_type     = "pattern.proxy"
  capnp.file_patterns = "*.capnp"
  capnp.is_editable   = "1"
  capnp.output_files  = [
    "$(DERIVED_FILE_DIR)/$(INPUT_FILE_BASE).capnp.cpp",
    "$(DERIVED_FILE_DIR)/$(INPUT_FILE_BASE).capnp.h",
  ]
  capnp.script = <<~SH
    #{nix_path}
    capnp compile -oc++:"$DERIVED_FILE_DIR" --src-prefix="$INPUT_FILE_DIR" "$INPUT_FILE_PATH"
    # Xcode reliably compiles .cpp; the capnp c++ plugin emits .c++.
    mv "$DERIVED_FILE_DIR/$INPUT_FILE_BASE.capnp.c++" "$DERIVED_FILE_DIR/$INPUT_FILE_BASE.capnp.cpp"
  SH

  ragel = project.new(Xcodeproj::Project::Object::PBXBuildRule)
  ragel.compiler_spec = "com.apple.compilers.proxy.script"
  ragel.file_type     = "pattern.proxy"
  ragel.file_patterns = "*.rl"
  ragel.is_editable   = "1"
  ragel.output_files  = ["$(DERIVED_FILE_DIR)/$(INPUT_FILE_BASE).cc"]
  ragel.script = <<~SH
    #{nix_path}
    ragel -o "$DERIVED_FILE_DIR/$INPUT_FILE_BASE.cc" "$INPUT_FILE_PATH"
  SH

  [capnp, ragel]
end

# Build the <fw>/header.h symlink farm from every spec's headers_glob.
def build_include_farm(specs)
  farm = File.join(ROOT, GEN_INCLUDE)
  require "fileutils"
  FileUtils.rm_rf(farm)
  specs.each do |spec|
    dest_dir = File.join(farm, spec[:name])
    FileUtils.mkdir_p(dest_dir)
    Array(spec[:headers_glob]).flat_map { |g| Dir.glob(File.join(ROOT, g)) }.sort.uniq.each do |hdr|
      link = File.join(dest_dir, File.basename(hdr))
      FileUtils.ln_s(hdr, link)
    end
  end
  puts "built include farm at #{GEN_INCLUDE}/ for #{specs.size} targets"
end

def apply_common_settings(config, extra = {})
  bs = config.build_settings
  bs["SDKROOT"]                     = "macosx"
  bs["MACOSX_DEPLOYMENT_TARGET"]    = DEPLOY_TGT
  bs["ARCHS"]                       = "arm64"
  bs["ONLY_ACTIVE_ARCH"]           = "YES"
  bs["CLANG_CXX_LANGUAGE_STANDARD"] = "c++2a"
  bs["GCC_C_LANGUAGE_STANDARD"]     = "c99"
  bs["CLANG_ENABLE_OBJC_ARC"]       = "YES"
  bs["GCC_CHAR_IS_UNSIGNED_CHAR"]   = "YES"           # -funsigned-char
  bs["CLANG_ENABLE_MODULES"]        = "NO"            # project predates modules; PCH-driven
  bs["HEADER_SEARCH_PATHS"]         = ["$(inherited)"] + COMMON_HEADER_PATHS
  bs["LIBRARY_SEARCH_PATHS"]        = ["$(inherited)", "#{NIX_ARM}/lib"]
  # -D defines + warning knobs from default.rave FLAGS
  bs["OTHER_CFLAGS"]                = [
    "$(inherited)",
    *GLOBAL_DEFINE_FLAGS,
    "-Wno-parentheses", "-Wno-sign-compare", "-Wno-switch", "-Wno-c99-designator",
  ]
  bs["CODE_SIGNING_ALLOWED"]        = "NO"            # libs aren't signed
  extra.each { |k, v| bs[k] = v }
end

# ---------------------------------------------------------------------------
build_include_farm(LIB_SPECS)

project = Xcodeproj::Project.new(PROJ_PATH)
targets_by_name = {}
build_rules = make_build_rules(project)

LIB_SPECS.each do |spec|
  target = project.new_target(:static_library, spec[:name], :osx, DEPLOY_TGT)
  targets_by_name[spec[:name]] = target
  build_rules.each { |r| target.build_rules << r }

  group = project.main_group.new_group(spec[:name], spec[:dir])
  files = Array(spec[:sources_glob]).flat_map { |g| Dir.glob(File.join(ROOT, g)) }.sort.uniq
  raise "no sources matched #{spec[:sources_glob]}" if files.empty?

  files.each do |abs|
    ref = group.new_file(abs)
    target.source_build_phase.add_file_reference(ref)
  end

  # Own source dirs, so intra-target quoted includes ("foo.h") and generated
  # sources compiled from DERIVED_FILE_DIR resolve their siblings.
  own_src_dirs = files.map { |f| "$(SRCROOT)/#{File.dirname(Pathname.new(f).relative_path_from(Pathname.new(ROOT)).to_s)}" }.uniq

  target.build_configurations.each do |config|
    extra = {}
    extra["GCC_PRECOMPILE_PREFIX_HEADER"] = "YES"
    extra["GCC_PREFIX_HEADER"]            = "$(SRCROOT)/#{PREFIX_HEADER}"
    extra["PRODUCT_NAME"]                 = spec[:name]
    extra["GCC_OPTIMIZATION_LEVEL"]       = "s" if config.name == "Release"  # -Os
    apply_common_settings(config, extra)
    config.build_settings["HEADER_SEARCH_PATHS"] += own_src_dirs
  end

  puts "seeded target #{spec[:name]} (#{files.size} sources)"
end

# Wire dependencies (build order; header exposure is via the farm).
LIB_SPECS.each do |spec|
  target = targets_by_name[spec[:name]]
  Array(spec[:deps]).each do |dep|
    dep_target = targets_by_name[dep] or raise "unknown dep #{dep} for #{spec[:name]}"
    target.add_dependency(dep_target)
  end
end

project.save
puts "wrote #{PROJ_PATH}"
