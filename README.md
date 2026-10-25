# @unitsml/unitsml

> **DEPRECATED.** This Opal-compiled package is retired: since the
> parslet→PARG migration, `Unitsml.parse` cannot run under Opal (the
> parsanol runtime is native). Use
> [`@unitsml/unitsml-ts`](https://github.com/unitsml/unitsml-ts)
> ([`@unitsml/unitsml-ts` on npm](https://www.npmjs.com/package/@unitsml/unitsml-ts)) —
> the native TypeScript implementation on the shared checksummed
> PARG artifact. No further releases will be made here.


JavaScript release of [unitsml-ruby](https://github.com/unitsml/unitsml-ruby),
Opal-compiled and published as `@unitsml/unitsml` on npm.

> **Status: scaffolding.** The build pipeline produces both flavors
> (self-contained + external Opal runtime), and the structure is
> verified. The runtime story for `Unitsml.parse()` itself is not
> complete — unitsml-ruby subclasses `::Unitsdb::Database` at runtime,
> so the unitsdb gem's model classes need to be available (either
> Opal-compiled alongside, or via a JS façade providing
> Ruby-compatible classes). See **Runtime status** below.

## Install

```sh
npm install @unitsml/unitsml
```

## Usage (target API)

```js
const Unitsml = require("@unitsml/unitsml");

const formula = Unitsml.parse("mm");
const mathml = formula.to_mathml();
const latex = formula.to_latex();
```

## Flavors

The package ships two entry points:

| Entry | File | Use case |
|---|---|---|
| `unitsml` (default) | `dist/unitsml.js` | **Self-contained** — Opal runtime embedded. One file, CDN-friendly, browser `<script>`-friendly. Larger (~1.5MB). |
| `unitsml-no-opal` | `dist/unitsml-no-opal.js` | **External** — references `@lutaml/opal-runtime` global. Smaller (~790KB). For bundler users (webpack, vite, rollup) who share runtime across multiple Opal-compiled packages. |

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

## Runtime status

The Opal compile of unitsml-ruby succeeds end-to-end. Running it
requires resolving these runtime dependencies, currently stubbed at
compile-time only:

- **`unitsdb-ruby`** — unitsml subclasses `::Unitsdb::Database`,
  `::Unitsdb::Unit`, etc. Either Opal-compile unitsdb-ruby alongside,
  or shim with `@unitsml/unitsdb` (which provides JSON data, not Ruby
  classes — would require a Ruby-compatible class adapter).
- **`mml-ruby`** — uses Mml::V4::* classes for MathML. Either
  Opal-compile mml-ruby (which transitively pulls moxml), or shim.
- **`ox`, `nokogiri`, `htmlentities`, `plurimath`** — server-only gems.
  `ox`/`nokogiri` can be shims if unitsml's XML adapter is configured
  for the pure-Ruby `oga` adapter (moxml's default under Opal).
  `htmlentities` is a small pure-Ruby gem, candidates for direct
  Opal-compile. `plurimath` is optional.

The cleanest path forward is to Opal-compile unitsdb-ruby + mml-ruby
as siblings, each published to npm with the same `@lutaml/opal-runtime`
peer. The build pipeline here then Opal-compiles unitsml with
**all three** as `prerequired`, producing a runnable bundle.

## Source

Built from [unitsml-ruby](https://github.com/unitsml/unitsml-ruby)
by its release workflow. The Ruby gem remains the single source of
truth for both behavior and data.