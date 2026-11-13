# jaix-demo: the member pre-step plugin, wired

Minimal demo of the `juice-plugin-jaix` member pre-step plugin (ticket 061,
spec §8.3; Phase 1 shipped it static in src/): a BIN package whose sources
use the try/catch extension syntax, built and tested through juice.

## Layout

- `package.jai` — the plugin declaration
  (`{id="juice-plugin-jaix", version="0.1.0", options=[config]}`) plus the
  `workspace.members` entry naming the member package. The `exe` option stays
  empty, so the plugin probes PATH for "jaix". The static fixture tree does
  not contain the member: the E2E copies this directory into a scratch
  workspace and copies the real `packages/juice-plugin-jaix` tree beside it.
- `jaix.config.jai` — the jaix configuration: the try/catch built-in plugin
  (MULTI_RETURN convention). Juice's own test block mechanism stays out of
  the config (the double processing exclusion).
- `src/main.jai` — the entry: a literal in-package `#load` chain into
  calc.jai, no extension syntax (its mirror view is byte-identical to the
  original).
- `src/calc.jai` — the extension-syntax file: `x := try half(n);` lowers to
  a multi-return error check.
- `src/calc_tests.jai` — the mixed-package surface: a juice test block file.
  It stays out of the jaix mirror; `juice test` runs it through juice's own
  transpile path.

## Commands

With jaix on PATH (the tests inject the sibling jaix-cli build):

- `juice build` — pre-step first (per-file `jaix transpile` into
  `target/jaix/`), then compiles the mirror entry view and produces
  `target/jaix-demo.exe`.
- `juice test` — the same pre-step, then the test program compiles the
  mirror views plus the original test block file: 3 tests pass.

The jaix CLI writes one session driver per transpile call into the child's
working directory; the plugin pins that directory to `target/jaix-drivers/`,
so no driver files ever land next to the package sources (stale litter from
older tools is identified by content and removed by the plugin).
