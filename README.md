# @unitsml/unitsml

JavaScript release of [unitsml-ruby](https://github.com/unitsml/unitsml-ruby),
Opal-compiled and published as `@unitsml/unitsml` on npm.

## Install

```sh
npm install @unitsml/unitsml
```

## Usage

```js
const Unitsml = require("@unitsml/unitsml");

// Parse a unit string
const formula = Unitsml.parse("mm");

// Convert to MathML
const mathml = formula.to_mathml();

// Convert to LaTeX
const latex = formula.to_latex();
```

## Flavors

The package ships two entry points:

| Entry | File | Use case |
|---|---|---|
| `unitsml` (default) | `dist/unitsml.js` | **Self-contained** — Opal runtime embedded. One file, CDN-friendly, browser `<script>`-friendly. Larger (~1.5MB). |
| `unitsml-no-opal` | `dist/unitsml-no-opal.js` | **External** — references `@lutaml/opal-runtime` global. Smaller (~200KB). For bundler users (webpack, vite, rollup) who share runtime across multiple Opal-compiled packages. |

Modern bundlers (webpack 5+, Vite, Rollup) and Node's ESM resolver pick
`unitsml-no-opal.js`. The browser field / script-tag path picks
`unitsml.js`.

## Shared runtime

When bundling with `@plurimath/plurimath` or other Opal-compiled unitsml
packages, declare `@lutaml/opal-runtime` as a peer dep to share the
single Opal instance:

```json
"peerDependencies": {
  "@lutaml/opal-runtime": "^1.0.0"
}
```

If `@plurimath/plurimath` has already shipped with `@lutaml/opal-runtime`
declared, just `npm install @unitsml/unitsml` and the runtime dedups.

If it's absent (e.g., browser CDN with only one of the two packages
loaded), `@unitsml/unitsml` falls back to its embedded runtime
automatically.

## Source

Built from [unitsml-ruby](https://github.com/unitsml/unitsml-ruby)
by its release workflow. The Ruby gem remains the single source of
truth for both behavior and data.