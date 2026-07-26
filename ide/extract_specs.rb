#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Extract structured target specs from the project's .rave files, mirroring the
# subset of rave's DSL grammar that the specs actually use (see bin/rave Parser).
# Emits JSON on stdout; consumed by ide/seed_xcodeproj.rb.
#
# Grammar (per bin/rave):
#   line := '}' | '#...' | command args ['{']
#   blocks: target "name" { ... }  config "x" { ... }  arch a b { ... }
#   ${dirname}=basename(dir)  ${dir}=spec dir  ${target}=target name
#   sources/headers/tests globs are expanded relative to the spec dir.

require "json"
require "shellwords"

ROOT = File.expand_path("..", __dir__)

SPEC_FILES = Dir.glob(File.join(ROOT, "{Applications,Frameworks,PlugIns,vendor}/*/default.rave")).sort

LINE_RE = /^\s*(?:(\})|(#.*)|([a-z_]+)\s*(.+?)?\s*(\{)?)\s*$/

# One target accumulator.
def new_target(name, dir)
  {
    "name" => name, "dir" => dir,
    "require" => [], "require_headers" => [],
    "headers" => [], "sources" => [], "tests" => [], "cxx_tests" => [],
    "libraries" => [], "frameworks" => [],
    "executable" => nil, "prefix" => nil,
    "ln_flags" => [], "files" => [], "copy" => [],
    "entitlements" => nil,
    "flags" => [], "c_flags" => [], "cxx_flags" => [],
    "objc_flags" => [], "objcxx_flags" => [],
  }
end

ADD_FLAG_VARS = {
  "FLAGS" => "flags", "C_FLAGS" => "c_flags", "CXX_FLAGS" => "cxx_flags",
  "OBJC_FLAGS" => "objc_flags", "OBJCXX_FLAGS" => "objcxx_flags"
}.freeze

def expand_vars(str, vars)
  str.gsub(/\$(?:\{(.+?)\}|(\w+))/) { vars[$1 || $2] || "" }
end

# Glob relative to dir, supporting {a,b} and ** (Dir.glob handles both).
def glob_rel(pattern, dir)
  abs = File.join(ROOT, dir, pattern)
  Dir.glob(abs, File::FNM_EXTGLOB).sort.map { |p| p.sub("#{ROOT}/", "") }
end

all = []

SPEC_FILES.each do |path|
  dir  = File.dirname(path).sub("#{ROOT}/", "")
  base = { "dir" => dir, "dirname" => File.basename(dir) }

  # Block stack: each frame carries the variable context and a kind.
  # kind :root | :target | :config | :arch
  stack = [{ kind: :root, vars: base.dup, target: nil }]

  File.foreach(path) do |line|
    m = line.match(LINE_RE)
    next unless m
    close, comment, command, params, open = m[1], m[2], m[3], m[4], m[5]
    next if comment
    if close
      stack.pop
      next
    end
    next unless command

    args = params ? Shellwords.split(params) : []
    top  = stack.last

    if open
      vars = top[:vars].dup
      case command
      when "target"
        name = expand_vars(args.first, vars.merge("target" => args.first))
        name = expand_vars(args.first, vars) # dirname/dir already in vars
        vars = vars.merge("target" => name)
        tgt  = new_target(name, dir)
        all << tgt
        stack.push({ kind: :target, vars: vars, target: tgt })
      when "config", "arch"
        stack.push({ kind: command.to_sym, vars: vars, target: top[:target] })
      else
        # unknown block; push to keep brace balance
        stack.push({ kind: :other, vars: vars, target: top[:target] })
      end
      next
    end

    # Non-block directive. Only meaningful inside a target (or its sub-blocks).
    tgt = top[:target]
    vars = top[:vars]
    next unless tgt

    ev = args.map { |a| expand_vars(a, vars) }

    case command
    when "require"          then tgt["require"]         += ev
    when "require_headers"  then tgt["require_headers"] += ev
    when "libraries"        then tgt["libraries"]       += ev
    when "frameworks"       then tgt["frameworks"]      += ev
    when "headers"          then tgt["headers"]  += ev.flat_map { |g| glob_rel(g, dir) }
    when "sources"          then tgt["sources"] += ev.flat_map { |g| glob_rel(g, dir) }
    when "tests"            then tgt["tests"]     += ev.flat_map { |g| glob_rel(g, dir) }
    when "cxx_tests"        then tgt["cxx_tests"] += ev.flat_map { |g| glob_rel(g, dir) }
    when "executable"       then tgt["executable"] = ev.first
    when "prefix"           then tgt["prefix"]     = ev.first
    when "files", "copy"
      refs, globs = ev.partition { |e| e.start_with?("@") }
      dest = globs.pop
      expanded = globs.flat_map { |g| glob_rel(g, dir) }
      tgt[command] += [{ "dest" => dest, "inputs" => expanded, "refs" => refs }]
    when "add"
      var = ev.first
      if var == "LN_FLAGS"
        tgt["ln_flags"] += ev[1..]
      elsif (key = ADD_FLAG_VARS[var])
        # re-split so "-I${dir} -I${dir}/vendor" becomes two tokens
        tgt[key] += ev[1..].flat_map { |s| Shellwords.split(s) }
      end
    when "expand"
      tgt["entitlements"] = ev[1] if ev.first == "CS_ENTITLEMENTS"
    end
  end
end

puts JSON.pretty_generate(all)
