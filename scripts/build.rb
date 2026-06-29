#!/usr/bin/env ruby
# frozen_string_literal: true

# Build script for @unitsml/unitsml. Runs Opal::Builder against the
# unitsml-ruby source tree to produce both the external-flavor
# (unitsml app code only) and self-contained-flavor (runtime + app)
# builds.
#
# This script is invoked from scripts/build.js via `bundle exec ruby`,
# so it runs in the bundler context where unitsml-ruby's deps
# (unitsdb, mml, etc.) are resolvable.

require "opal"
require "opal/builder"
require "fileutils"

# Gems that unitsml depends on transitively but cannot be Opal-compiled
# (C extensions, server-only libraries). The Opal boot file at
# lib/unitsml/opal.rb documents the same list. Stubs let the build
# complete without resolving these requires to real Ruby files.
UPSTREAM_STUBS = %w[
  lutaml/model
  lutaml/xml
  unitsdb
  unitsdb/opal
  mml
  mml/opal
  omml
  omml/opal
  ox
  htmlentities
  parslet
  plurimath
  nokogiri
].freeze

# Entry point to compile — unitsml-ruby's own Opal boot file.
ENTRY = "unitsml/opal"

def new_builder(lib_paths)
  builder = Opal::Builder.new
  Array(lib_paths).each { |p| builder.append_paths(p) }
  builder.stubs = UPSTREAM_STUBS.dup
  # Mark `opal` as prerequired — Opal assumes the runtime is provided
  # externally (by @lutaml/opal-runtime) and only emits the app code.
  builder.prerequired = %w[opal]
  builder.compiler_options = { source_map: false }
  builder
end

def build_app_code(ruby_dir, dist_dir)
  lib_paths = [
    File.join(ruby_dir, "lib"),
    File.join(ruby_dir, "lib", "unitsml", "opal"),
  ]
  output = new_builder(lib_paths).build(ENTRY).to_s
  path = File.join(dist_dir, "unitsml-no-opal.js")
  FileUtils.mkdir_p(dist_dir)
  File.write(path, output)
  warn "wrote #{path} (#{output.bytesize / 1024} KiB)"
  output
end

def read_runtime(runtime_pkg_root)
  candidates = [
    File.join(runtime_pkg_root, "node_modules", "@lutaml", "opal-runtime", "dist", "runtime.js"),
    File.join(runtime_pkg_root, "node_modules", "@lutaml", "opal-runtime", "dist", "runtime.cjs"),
    File.join(runtime_pkg_root, "..", "..", "..", "lutaml", "opal-runtime", "dist", "runtime.js"),
  ]
  candidates.each do |p|
    next unless File.exist?(p)

    runtime = File.read(p)
    warn "read runtime from #{p} (#{runtime.bytesize / 1024} KiB)"
    return runtime
  end
  warn "Could not locate @lutaml/opal-runtime/dist/runtime.js. " \
       "Falling back to inline Opal runtime via Opal::Builder."
  inline_runtime
end

def inline_runtime
  # Fallback: emit the Opal runtime by compiling a no-op stub. This
  # path is used during local dev before @lutaml/opal-runtime is
  # published. In CI, the npm package should be the source.
  builder = Opal::Builder.new
  builder.stubs = UPSTREAM_STUBS.dup
  builder.compiler_options = { source_map: false }
  builder.build_str("", "(runtime)", prerequired: [], stubs: ["opal-runtime-stub"])
  builder.to_s
end

def build_self_contained(app_code, runtime, version, dist_dir)
  header = <<~HEADER
    // @unitsml/unitsml — self-contained build (Opal runtime embedded)
    // Generated from unitsml-ruby v#{version}
    // Opal runtime: @lutaml/opal-runtime
    //
  HEADER
  combined = "#{header}#{runtime}\n#{app_code}"
  path = File.join(dist_dir, "unitsml.js")
  File.write(path, combined)
  warn "wrote #{path} (#{combined.bytesize / 1024} KiB)"
end

def write_types(dist_dir)
  # unitsml-ruby's Unitsml module is dynamic; we surface `Unitsml`
  # as `any` rather than try to model every formatter method.
  dts = <<~TS
    declare const Unitsml: any;
    export = Unitsml;
    export default Unitsml;
  TS
  path = File.join(dist_dir, "index.d.ts")
  File.write(path, dts)
  warn "wrote #{path}"
end

ruby_dir = ENV.fetch("RUBY_DIR")
dist_dir = ENV.fetch("DIST_DIR")
runtime_root = ENV.fetch("RUNTIME_PKG_ROOT")
version = ENV.fetch("VERSION")

FileUtils.mkdir_p(dist_dir)

app_code = build_app_code(ruby_dir, dist_dir)
runtime = read_runtime(runtime_root)
build_self_contained(app_code, runtime, version, dist_dir)
write_types(dist_dir)