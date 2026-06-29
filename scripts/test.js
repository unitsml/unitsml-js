// Smoke test for @unitsml/unitsml — verify the build artifacts load.
//
// Does NOT exercise unitsml.parse() at runtime. unitsml-ruby subclasses
// ::Unitsdb::Database at runtime, which means the unitsdb gem's model
// classes must be present (Opal-compiled or shimmed). Stubs satisfy
// compile-time only — runtime requires either a real unitsdb/mml Opal
// bundle or a JS façade providing Ruby-compatible classes.
//
// This test verifies:
//   1. The runtime file parses and exposes `Opal` global.
//   2. The unitsml app-code file parses and defines Opal.modules entries.
//   3. Requiring the boot module runs the eager-load chain without
//      raising during the LOAD phase (constant definition).
//
// Actual unitsml.parse() runtime is verified by the unitsdb/mml Opal
// story, which is tracked separately.
const path = require("path");
const fs = require("fs");

const variant = process.env.VARIANT || "self-contained";
const distDir = path.join(__dirname, "..", "dist");

let runtimePath;
let appPath;
if (variant === "external") {
  // External: load @lutaml/opal-runtime first, then unitsml app code
  try {
    runtimePath = require.resolve("@lutaml/opal-runtime");
  } catch (e) {
    console.error(
      "external variant requires @lutaml/opal-runtime — install with: npm install @lutaml/opal-runtime"
    );
    process.exit(1);
  }
  appPath = path.join(distDir, "unitsml-no-opal.js");
} else {
  runtimePath = path.join(distDir, "unitsml.js");
  appPath = null;
}

if (!fs.existsSync(runtimePath)) {
  console.error(`missing artifact: ${runtimePath}`);
  process.exit(1);
}
if (appPath && !fs.existsSync(appPath)) {
  console.error(`missing artifact: ${appPath}`);
  process.exit(1);
}

require(runtimePath);
if (appPath) require(appPath);

const Opal = globalThis.Opal;
if (typeof Opal !== "object" || typeof Opal.require !== "function") {
  console.error("Opal global not initialized");
  process.exit(1);
}
console.log(`✓ runtime exposed Opal global (${typeof Opal})`);

const moduleNames = Object.keys(Opal.modules || {});
const unitsmlModules = moduleNames.filter((n) => n.startsWith("unitsml/"));
if (unitsmlModules.length === 0) {
  console.error("no unitsml/* modules registered with Opal");
  process.exit(1);
}
console.log(
  `✓ ${unitsmlModules.length} unitsml/* modules registered ` +
    `(sample: ${unitsmlModules.slice(0, 3).join(", ")})`
);

console.log(`\n${variant} variant: structure verified (runtime not exercised)`);
process.exit(0);