// Build script for @unitsml/unitsml.
//
// Reads unitsml-ruby at the released ref, Opal-compiles it, and emits
// two flavors:
//   dist/unitsml-no-opal.js  — app code only, references @lutaml/opal-runtime
//   dist/unitsml.js          — self-contained (runtime + app, for CDN users)
//   dist/index.d.ts          — TypeScript definitions
//
// Inputs (from CI workflow):
//   version     — unitsml version (e.g. "0.6.7")
//   ruby_ref    — git ref of unitsml-ruby (e.g. "v0.6.7")
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

const RUNTIME_PKG = "@lutaml/opal-runtime";
const RUBY_REPO = "https://github.com/unitsml/unitsml-ruby.git";

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

function compileUnitsml() {
  // Opal-compile unitsml through its own boot file. Mark Opal as
  // external — this gives us unitsml app code without the runtime,
  // which we bundle separately for the shared-runtime case.
  const cmd = [
    "bundle exec opal",
    "-I lib",
    "-I lib/unitsml/opal",
    "-r unitsml/opal",
    "--no-source-map",
    "-o app.js",
  ].join(" ");
  run(cmd, { cwd: TMP });
  return fs.readFileSync(path.join(TMP, "app.js"), "utf8");
}

function readRuntime() {
  // The shared Opal runtime ships in @lutaml/opal-runtime. Use the
  // locally installed copy (declared as devDependency).
  const candidates = [
    path.join(ROOT, "node_modules", RUNTIME_PKG, "dist", "runtime.js"),
    path.join(ROOT, "..", "..", RUNTIME_PKG, "dist", "runtime.js"),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return fs.readFileSync(p, "utf8");
  }
  throw new Error(
    `Could not locate ${RUNTIME_PKG}/dist/runtime.js — install it first`
  );
}

function writeApp(appCode) {
  fs.writeFileSync(path.join(DIST, "unitsml-no-opal.js"), appCode);
  console.error(
    `wrote dist/unitsml-no-opal.js (${(appCode.length / 1024).toFixed(1)} KiB)`
  );
}

function writeSelfContained(appCode) {
  const runtime = readRuntime();
  const header = [
    "// @unitsml/unitsml — self-contained build",
    "// Opal runtime: @lutaml/opal-runtime",
    `// unitsml version: ${VERSION}`,
    "",
  ].join("\n");
  const combined = `${header}${runtime}\n${appCode}`;
  fs.writeFileSync(path.join(DIST, "unitsml.js"), combined);
  console.error(
    `wrote dist/unitsml.js (${(combined.length / 1024).toFixed(1)} KiB)`
  );
}

function writeTypes() {
  // Minimal types. The full unitsml surface is dynamic — JS users
  // get an `any` for `Unitsml` and the formatter methods.
  const dts = `declare const Unitsml: any;
export = Unitsml;
export default Unitsml;
`;
  fs.writeFileSync(path.join(DIST, "index.d.ts"), dts);
  console.error("wrote dist/index.d.ts");
}

rmrf(DIST);
ensureDir(DIST);

checkoutUnitsmlRuby();
const appCode = compileUnitsml();
writeApp(appCode);
writeSelfContained(appCode);
writeTypes();

rmrf(TMP);
console.error("build complete");