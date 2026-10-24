#!/usr/bin/env ruby
# frozen_string_literal: true

# Build script for @unitsml/unitsml. Runs Opal::Builder against the
# unitsml-ruby source tree and chains the Opal-compiled unitsdb,
# mml, and lutaml-model peers into the final bundle.
#
# Chain:
#   @lutaml/opal-runtime  (peer — Opal VM)
#   @lutaml/lutaml-model  (peer — Serializable parent class)
#   @unitsml/unitsdb      (peer — Unitsdb::* classes)
#   @plurimath/mml        (peer — Mml::* classes)
#   @unitsml/unitsml      (this package — Unitsml.parse)
#
# Key fix: Opal 1.8.x defaults to its Prefork scheduler, which hangs
# on lutaml-model (forked workers deadlock on its 516 autoloads).
# Setting OPAL_PREFORK_DISABLE=1 selects Opal's built-in Sequential
# scheduler, which compiles safely. Opal 2 adds a Threaded option as
# well; we can drop the env var once we depend on Opal 2.

require "opal"
require "opal/builder"
require "fileutils"
require "tmpdir"

# Avoid the Opal 1.8.x prefork deadlock on large gem trees.
ENV["OPAL_PREFORK_DISABLE"] ||= "1"

# Server-only or C-extension deps. lutaml-model is provided by its
# own npm peer (compiled inline below until @lutaml/lutaml-model is
# published).
UPSTREAM_STUBS = %w[
  ox
  htmlentities
  parslet
  plurimath
  nokogiri
  omml
  omml/opal
  unitsdb
  unitsdb/opal
  mml
  mml/opal
  # lutaml-model transitive deps that aren't Opal-compatible
  rdf
  rdf/turtle
  rdf-turtle
  rdf/ntriples
  rdf/model
  linkeddata
  json/ld
  jsonld
  json-ld
  rdf/vocab
  spira
  weakref
  rexml/document
  rexml/streamlistener
  rexml/parsers/baseparser
  rexml/parsers/treeparser
  rexml/light/node
  rexml/text
].freeze

# Peer packages whose Opal-compiled app code is concatenated into
# the self-contained flavor.
PEER_PACKAGES = [
  ["@lutaml/opal-runtime", "dist/runtime.js"],
  ["@unitsml/unitsdb",     "dist/unitsdb-no-opal.js"],
  ["@plurimath/mml",       "dist/mml-no-opal.js"],
].freeze

ENTRY = "unitsml/opal"

def checkout_lutaml_model
  if (local = ENV["LUTAML_MODEL_SRC"]) && File.directory?(File.join(local, "lib"))
    return local
  end

  dir = Dir.mktmpdir("lutaml-model")
  success = system("git", "clone", "--depth", "1",
                   "https://github.com/lutaml/lutaml-model.git", dir)
  abort "git clone of lutaml-model failed" unless success
  dir
end

def build_lutaml_model(dist_dir)
  src = checkout_lutaml_model
  builder = Opal::Builder.new
  builder.append_paths(File.join(src, "lib"))
  moxml_lib = ENV.fetch("MOXML_SRC", "/Users/mulgogi/src/lutaml/moxml/lib")
  if File.directory?(moxml_lib)
    builder.append_paths(moxml_lib)
    builder.append_paths(File.join(moxml_lib, "compat/opal"))
  end
  builder.stubs = %w[
    lutaml/xml
    nokogiri ox oga
    rdf rdf/turtle rdf-turtle rdf/ntriples rdf/model
    linkeddata json/ld jsonld json-ld rdf/vocab spira
    weakref rexml/document rexml/streamlistener
    rexml/parsers/baseparser rexml/parsers/treeparser
    rexml/light/node rexml/text
  ]
  builder.prerequired = %w[opal]
  builder.compiler_options = { source_map: false }
  output = builder.build("lutaml/model").to_s
  path = File.join(dist_dir, "lutaml-model-no-opal.js")
  File.write(path, output)
  warn "compiled #{path} (#{output.bytesize / 1024} KiB)"
  output
end

def build_unitsml_app(ruby_dir, dist_dir)
  builder = Opal::Builder.new
  builder.append_paths(File.join(ruby_dir, "lib"))
  builder.append_paths(File.join(ruby_dir, "lib", "unitsml", "opal"))
  builder.stubs = UPSTREAM_STUBS.dup + %w[lutaml-model lutaml/model]
  builder.prerequired = %w[opal lutaml/model]
  builder.compiler_options = { source_map: false }

  output = builder.build(ENTRY).to_s
  path = File.join(dist_dir, "unitsml-no-opal.js")
  File.write(path, output)
  warn "wrote #{path} (#{output.bytesize / 1024} KiB)"
  output
end

def read_peer(runtime_pkg_root, npm_name, dist_file)
  candidates = [
    File.join(runtime_pkg_root, "node_modules", npm_name, dist_file),
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
    // Embedded peers: @lutaml/opal-runtime, @lutaml/lutaml-model,
    //                @unitsml/unitsdb, @plurimath/mml
    //
  HEADER
  combined = "#{header}#{peer_sources.join("\n")}\n#{app_code}"
  path = File.join(dist_dir, "unitsml.js")
  File.write(path, combined)
  warn "wrote #{path} (#{combined.bytesize / 1024} KiB)"
end

def write_entry_loader(dist_dir)
  loader = <<~JS
    // @unitsml/unitsml — external entry point
    // Loads peers in order, then unitsml app code.
    require("@lutaml/opal-runtime");
    require("@lutaml/lutaml-model");
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

File.write(File.join(dist_dir, "lutaml-model-no-opal.js"), build_lutaml_model(dist_dir))
app_code = build_unitsml_app(ruby_dir, dist_dir)
peer_sources = PEER_PACKAGES.map { |name, file| read_peer(runtime_root, name, file) }
peer_sources << File.read(File.join(dist_dir, "lutaml-model-no-opal.js"))
build_self_contained(app_code, peer_sources, version, dist_dir)
write_entry_loader(dist_dir)
write_types(dist_dir)