// Build script for @unitsml/unitsml.
//
// Clones unitsml-ruby at the released ref, then runs scripts/build.rb
// which uses Opal::Builder to compile lib/unitsml/opal into both
// external and self-contained flavors.
//
// Inputs:
//   VERSION  — unitsml version (e.g. "0.6.7")
//   RUBY_REF — git ref of unitsml-ruby (e.g. "v0.6.7")
//
// Usage:
//   node scripts/build.js
//   VERSION=0.6.7 RUBY_REF=v0.6.7 node scripts/build.js
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const ROOT = process.cwd();
const DIST = path.join(ROOT, "dist");
const TMP = path.join(ROOT, ".tmp");

const VERSION = process.env.VERSION || require("../package.json").version;
const RUBY_REF = process.env.RUBY_REF || `v${VERSION}`;
const RUBY_REPO = process.env.RUBY_REPO || "https://github.com/unitsml/unitsml-ruby.git";

function run(cmd, opts = {}) {
  console.error(`$ ${cmd}`);
  try {
    return execSync(cmd, { stdio: ["ignore", "inherit", "inherit"], ...opts });
  } catch (err) {
    console.error(`command failed: ${cmd}`);
    process.exit(1);
  }
}

function rmrf(p) {
  fs.rmSync(p, { recursive: true, force: true });
}

function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}

function checkoutUnitsmlRuby() {
  rmrf(TMP);
  ensureDir(TMP);
  run(`git clone --depth 1 --branch ${RUBY_REF} ${RUBY_REPO} ${TMP}`);
  run("bundle install", { cwd: TMP });
}

function buildRuby() {
  // scripts/build.rb expects:
  //   RUBY_DIR         — path to unitsml-ruby
  //   DIST_DIR         — output directory
  //   RUNTIME_PKG_ROOT — directory where @lutaml/opal-runtime is installed
  //   VERSION          — unitsml version (for header comments)
  const env = {
    ...process.env,
    RUBY_DIR: TMP,
    DIST_DIR: DIST,
    RUNTIME_PKG_ROOT: ROOT,
    VERSION,
  };
  run(`bundle exec ruby ${path.join(ROOT, "scripts", "build.rb")}`, {
    cwd: TMP,
    env,
  });
}

rmrf(DIST);
ensureDir(DIST);

checkoutUnitsmlRuby();
buildRuby();

rmrf(TMP);
console.error("build complete");