// Smoke test for @unitsml/unitsml — run after build.
const path = require("path");

const variant = process.env.VARIANT || "self-contained";
const entry =
  variant === "external"
    ? path.join(__dirname, "..", "dist", "unitsml-no-opal.js")
    : path.join(__dirname, "..", "dist", "unitsml.js");

// Ensure the runtime is available for the external variant.
if (variant === "external") {
  try {
    require.resolve("@lutaml/opal-runtime");
  } catch (e) {
    console.error(
      "external variant requires @lutaml/opal-runtime — install with: npm install @lutaml/opal-runtime"
    );
    process.exit(1);
  }
}

const Unitsml = require(entry);

const cases = [
  { input: "mm", expectSymbol: "m" },
  { input: "km", expectSymbol: "m" },
  { input: "kg", expectSymbol: "g" },
  { input: "1", expectSymbol: "1" },
];

let pass = 0;
let fail = 0;
for (const { input, expectSymbol } of cases) {
  try {
    const formula = Unitsml.parse(input);
    const value = formula.value[0];
    const got = value && (value.unit_name || (value.value && value.value[0]));
    if (got === expectSymbol) {
      console.log(`✓ "${input}" → ${got}`);
      pass++;
    } else {
      console.log(`✗ "${input}" → expected ${expectSymbol}, got ${got}`);
      fail++;
    }
  } catch (err) {
    console.log(`✗ "${input}" → error: ${err.message}`);
    fail++;
  }
}

console.log(`\n${pass} passed, ${fail} failed (variant: ${variant})`);
process.exit(fail === 0 ? 0 : 1);