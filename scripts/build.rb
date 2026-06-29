#!/usr/bin/env ruby
# frozen_string_literal: true

# Build script for @unitsml/unitsml. Runs Opal::Builder against the
# unitsml-ruby source tree, then concatenates with the Opal-compiled
# unitsdb + mml peer packages to produce a runnable bundle.
#
# Chain:
#   @lutaml/opal-runtime  (peer, optional — falls back to empty)
#   @unitsml/unitsdb      (peer — provides Unitsdb::* classes)
#   @plurimath/mml        (peer — provides Mml::* classes)
#   @unitsml/unitsml      (this package — provides Unitsml.parse)
#
# This script is invoked from scripts/build.js via `bundle exec ruby`.

require "opal"
require "opal/builder"
require "fileutils"

# Server-only or C-extension deps that unitsml-ruby can't load under
# Opal. lutaml/model is also stubbed here because we don't yet have
# @lutaml/lutaml-model as an npm peer — unitsdb-js and mml-js also
# stub it, so Opal.require() resolves to the first stub registered.
#
# unitsdb/opal and mml/opal are stubbed HERE but provided as real
# peer packages (@unitsml/unitsdb, @plurimath/mml) at runtime. The
# stub is a no-op; the real peer module loads first via
# dist/unitsml-loader.js.
UPSTREAM_STUBS = %w[
  lutaml/model
  lutaml/model/xml
  lutaml/model/json
  lutaml/model/yaml
  lutaml/model/key_value
  lutaml/model/toml
  lutaml/model/type
  lutaml/model/serialize
  unitsdb
  unitsdb/opal
  mml
  mml/opal
  ox
  htmlentities
  parslet
  plurimath
  nokogiri
  omml
  omml/opal
].freeze

# Peer packages whose Opal-compiled app code is concatenated into
# the self-contained flavor. Each entry is [npm_name, dist_file].
# At runtime these provide the Ruby classes unitsml subclasses
# (Unitsdb::Database, Mml::V4::*).
PEER_PACKAGES = [
  ["@lutaml/opal-runtime", "dist/runtime.js"],
  ["@unitsml/unitsdb",     "dist/unitsdb-no-opal.js"],
  ["@plurimath/mml",       "dist/mml-no-opal.js"],
].freeze

ENTRY = "unitsml/opal"

def build_app_code(ruby_dir, dist_dir)
  builder = Opal::Builder.new
  builder.append_paths(File.join(ruby_dir, "lib"))
  builder.append_paths(File.join(ruby_dir, "lib", "unitsml", "opal"))
  # peers (unitsdb, mml) are no longer stubbed — they're loaded as
  # prerequired peers from the npm packages below.
  builder.stubs = UPSTREAM_STUBS.dup
  builder.prerequired = %w[opal]
  builder.compiler_options = { source_map: false }

  output = builder.build(ENTRY).to_s
  path = File.join(dist_dir, "unitsml-no-opal.js")
  FileUtils.mkdir_p(dist_dir)
  File.write(path, output)
  warn "wrote #{path} (#{output.bytesize / 1024} KiB)"
  output
end

def read_peer(runtime_pkg_root, npm_name, dist_file)
  candidates = [
    File.join(runtime_pkg_root, "node_modules", npm_name, dist_file),
    # Monorepo-style sibling layout (dev only)
    File.join(runtime_pkg_root, "..", "..", npm_name, dist_file),
  ]
  candidates.each do |p|
    next unless File.exist?(p)

    content = File.read(p)
    warn "read #{npm_name}/#{dist_file} from #{p} (#{content.bytesize / 1024} KiB)"
    return content
  end
  warn "Peer #{npm_name}/#{dist_file} not found. " \
       "Install with: npm install #{npm_name}"
  ""
end

def build_self_contained(app_code, peer_sources, version, dist_dir)
  header = <<~HEADER
    // @unitsml/unitsml — self-contained build (Opal runtime + peers embedded)
    // Generated from unitsml-ruby v#{version}
    // Embedded peers: @lutaml/opal-runtime, @unitsml/unitsdb, @plurimath/mml
    //
  HEADER
  combined = "#{header}#{peer_sources.join("\n")}\n#{app_code}"
  path = File.join(dist_dir, "unitsml.js")
  File.write(path, combined)
  warn "wrote #{path} (#{combined.bytesize / 1024} KiB)"
end

def write_entry_loader(dist_dir)
  # CJS entry that resolves the peer chain at runtime. Bundler
  # users get this; CDN users get the self-contained unitsml.js.
  loader = <<~JS
    // @unitsml/unitsml — external entry point
    // Loads peers in order, then unitsml app code.
    require("@lutaml/opal-runtime");
    require("@unitsml/unitsdb");
    require("@plurimath/mml");
    require("./unitsml-no-opal.js");
    module.exports = globalThis.Opal.const_get("Unitsml");
  JS
  path = File.join(dist_dir, "unitsml-loader.js")
  File.write(path, loader)
  warn "wrote #{path}"
end

def write_types(dist_dir)
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
peer_sources = PEER_PACKAGES.map { |name, file| read_peer(runtime_root, name, file) }
build_self_contained(app_code, peer_sources, version, dist_dir)
write_entry_loader(dist_dir)
write_types(dist_dir)