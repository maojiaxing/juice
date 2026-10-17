# jaix-demo: the juice jaix pre-step, wired and manual

Minimal demo of the jaix pre-step (spec 055 / docs/spec.md §12): a BIN package
whose sources use the try/catch extension syntax, built through juice with the
package's jaix marker — plus the same build spelled out as a manual two-step
script.

## Layout

- `package.jai` — the jaix marker (`jaix = .{ config = "jaix.config.jai" }`);
  the `exe` field stays empty, so juice probes PATH for "jaix".
- `jaix.config.jai` — the jaix configuration: the try/catch built-in plugin
  (MULTI_RETURN convention). Juice's own test block mechanism stays out of the
  config (the double processing exclusion).
- `src/main.jai` — the entry: a literal in-package `#load` chain into
  calc.jai, no extension syntax (its mirror view is byte-identical to the
  original).
- `src/calc.jai` — the extension-syntax file: `x := try half(n);` lowers to a
  multi-return error check.
- `src/calc_tests.jai` — the mixed-package surface: a juice test block file.
  It stays out of the jaix mirror; `juice test` runs it via juice's own path.
- `two-step.bat` — the manual two-step script.

## Wired: one step

The marker wires the pre-step into juice, so the ordinary commands just work
(jaix must be on PATH — the marker keeps its `exe` field empty):

- `juice build` — pre-step first (per-file `jaix transpile` into
  `target/jaix/`), then compiles the mirror entry view and produces
  `target/jaix-demo.exe`.
- `juice run` — builds (run depends on build), then executes the artifact:
  `double(20): NONE 40`, `double(-6): NEGATIVE 0` (the try lowering's success
  and error-propagation paths).
- `juice test` — the same pre-step, then the test program compiles the mirror
  views plus the original test block file: 3 tests pass.

## Manual: the two-step script

`two-step.bat` (Windows batch — runs from cmd or Git Bash) spells out what the
wired build does internally:

- step 1 — the manual pre-step: the per-file `jaix transpile` loop over
  `src/*.jai` into the `target/jaix/` mirror (all-absolute paths; the juice
  test block file and the config stay out — the same exclusion set as the
  wired scan for this fixture's current topology). Note the script's skip is
  a name match (`calc_tests.jai`) while the wired scan detects test-block
  content: adding a demo source that contains test blocks requires updating
  the script's skip list;
- step 2 — the ordinary `juice build` + `juice run`.

```bat
two-step.bat                REM step 1 + step 2
two-step.bat transpile-only REM step 1 alone: inspect the mirror before the
                            REM wired build overwrites it
```

The seam and the wiring agree by construction: step 2's wired build re-runs
step 1 itself (the marker), overwriting the mirror with byte-identical views —
the manual step 1 and the wired pre-step are idempotent. The E2E dual-path
test asserts that identity byte for byte and checks that both paths produce
the same artifact and run output.

## Tool resolution and litter

jaix resolves through PATH (the wired pre-step probes PATH for "jaix"),
falling back to the sibling dev layout (`../../../../jaix-cli/target` from
this directory); juice resolves to this repository's own build
(`../../../target/juice.exe`) first — the jaix marker is this repo's feature,
so a stale PATH-installed juice would reject the manifest — falling back to
the PATH lookup. jaix's CLI driver files land in the working directory
(hash-named `.jai`, one per transpile call); the script removes them — the
wired build's own spawns would otherwise be scanned as package sources by the
next juice invocation.
