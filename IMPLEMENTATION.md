# Command Registry Implementation

Juice uses an explicit static command registry and prerequisite Dispatcher. Each command owns its declaration, argument contract, and command-specific implementation; the registry only aggregates declarations. Workspace preparation owns the discovery → resolution → dependency → prepared-workspace state transitions.

## Module ownership

| Module | Responsibility |
| --- | --- |
| `src/commands/command.jai` | Shared `Command`, `Command_Context`, handler and argument-validator types |
| `src/commands/registry.jai` | Static array of command-owned declarations |
| `src/commands/build.jai` | Build declaration, argument contract, compilation, batch revalidation, and prepared-workspace orchestration |
| `src/commands/run.jai` | Run declaration, argument contract, target selection, diagnostics, and artifact launch |
| `src/commands/clean.jai` | Clean declaration, argument contract, cleanup scope, all-path validation, and deletion policy |
| `src/commands/test.jai` | Test declaration, argument contract, discovery scan, transpile orchestration, driver generation, and the Testing module view special case (`testing_module_view` helper) |
| `src/dispatcher.jai` | Registry validation, lookup, planning, and execution; production and test registries share it |
| `src/workspace.jai` | Workspace discovery, member validation, the discovery/preparation state machine, and the command-side preparation entry (`ensure_workspace_prepared`) |
| `src/dependency.jai` | Dependency fetching, workspace-member lookup over the discovery snapshot, the local dependency directory derivation (`packages_dir`), and the shared compile import-directory assembly (`compiler_import_directories`, ticket 0048) |
| `src/target.jai` | Shared effective-target resolution, artifact plans, and artifact-path revalidation |
| `src/path_safety.jai` | Shared filesystem/path inspection and validation, plus the juice modules directory derivation |
| `src/transpile_cache.jai` | Pure content-addressed cache keys/paths for transpiled views, and the transpile subtree root |
| `src/metaprogram.jai` | Shared compiler metaprogram generator (one-shot workspace/intercept/message-loop skeleton) consumed by Build and Test |
| `src/main.jai` | File loading, context initialization (package root and cache paths), CLI argument slicing, and dispatch |

Command metadata, prerequisites, handlers, and the argument contract are declared in the owning command file. Handlers print usage from their own declaration rather than maintaining a second usage string. Adding a command requires adding its file to the load list and its declaration to the registry; no automatic registration is involved.

Build and Run still consume the same artifact plan.

## Dispatcher

`dispatch_command` takes the registry as its input and returns a structured `Dispatch_Result`. Production and tests invoke the same implementation; the tests do not reimplement registry validation or lookup.

The Dispatcher builds and validates the complete selected graph before invoking any handler:

1. Validate the registry: declarations, duplicate names, and missing prerequisites.
2. Look up the requested command; reject unknown commands.
3. Plan the selected graph with the requested command's own argument validator. Invalid arguments stop the dispatch before any prerequisite runs.
4. Detect cycles during planning, before any execution.
5. Execute the ordered graph once per command. Prerequisites receive empty arguments; only the requested command receives the user's arguments.
6. Propagate prerequisite and handler failures with `Dispatch_Result` instead of bare bools.

## Command execution

```text
run → build
build / run / test → ensure_workspace_prepared → ensure_workspace_discovered → prepare_workspace
clean → discovery within its own handler, without dependency preparation
```

- Build compiles all effective targets of the **root package**, not all workspace members.
- Run chooses an explicit, case-sensitive target; otherwise it chooses the only target or the target matching the package name. It launches the selected prepared artifact after Build completes.
- Clean discovers root and member `target/` directories (whole-directory deletion). Without a manifest, it cleans only the current root's `target/`. Legacy `result/` and `.packages` directories are no longer managed.
- Clean validates every deletion target before deleting any. A deletion failure does not prevent attempts on the remaining validated paths, but the overall result is failure.
- Clean does not prepare dependencies. Discovery may execute manifests, so Clean is not free of manifest side effects.
- Handlers return `bool`; the CLI exits with status 1 on failure.

## Workspace preparation

`Workspace_State` replaces the context's discovery/prepared pairs with one phase (`EMPTY`, `DISCOVERED`, `PREPARED`). The workspace module owns the transitions:

- `ensure_workspace_discovered` publishes the discovery result and prints the discovery message. Repeated calls are idempotent.
- `prepare_workspace` resolves effective targets and artifact plans, then prepares dependencies only when plans exist. It publishes a prepared result only after every required step succeeds; a failed attempt leaves discovery reusable and exposes no partial prepared workspace.
- `ensure_workspace_prepared` is the command-side entry (ticket 0040): one idempotent call chains the two phases and hands back the prepared result (null = failure, already reported by the failing phase). Build, Run and Test call it as their first step; Run's call after Build's prerequisite run is a no-op on the phase machine. The command-specific guard (ticket 0037) is absorbed — the failure message now names the concrete discovery/preparation error.
- `get_prepared_workspace` stays the raw state accessor for tests.
- Workspace preparation is not registered as a command; the registry holds only invocable commands.

`Workspace_Discovery` retains the evaluated member declarations (`member_packages`, root first) instead of only member paths. Dependency preparation consumes this snapshot and no longer re-executes member manifests; workspace-member lookups no longer load manifests.

Manifest evaluation runs one jai child process per manifest. Its temp files (`eval_manifest_<hash>.jai` / `manifest_data_<hash>.txt` in the XDG cache directory) are named by a hash of the manifest's absolute path — distinct manifests never collide across sequential or concurrent evaluations — and the generated evaluator exits non-zero when it cannot write its data, which the loader retries up to twice. The previous shared fixed names plus an unchecked write had produced silent stale reads when an AV scanner briefly locked the data file, intermittently dropping workspace members (ticket 0035).

## Test seams

The production implementation is the test surface:

- `dispatch_command`/`validate_registry` accept a registry, so tests drive the production Dispatcher with test registries instead of copied algorithms.
- `run_prepared_workspace` accepts a launch operation, defaulting to `run_artifact_plan`. Tests use a recording adapter to verify selection, exact artifact/root forwarding, no launch on invalid selection, and launch-failure propagation.
- `clean_discovered_workspace` accepts validation and deletion operations, defaulting to the real filesystem operations. Recording adapters verify deletion scope, all-path validation before deletion, no deletion after validation failure, and continued deletion after an individual failure.
- `build_prepared_workspace` accepts a compile operation, defaulting to `compile_artifact_plan`. Recording adapters verify the targetless no-op, the revalidation gate before any compilation, exact per-plan forwarding, and fail-fast on the first compile failure.
- `ensure_workspace_discovered`, `prepare_workspace` and `ensure_workspace_prepared` accept discovery, resolution, and dependency operations with production defaults. Tests verify the state transitions, no-dependency no-op for targetless packages, that failures publish nothing, and the entry's idempotency.
- `fetch_workspace_dependencies` accepts a fetch operation, defaulting to `fetch_dependency`. Tests verify member dependencies are skipped and fetch failures propagate.

Production handlers use the defaults. Real process execution, compilation, workspace discovery, and dependency fetching remain in the production path; the build revalidation gate runs in tests over the real filesystem checks.

## Jai-specific constraints

- `context` is reserved; handler parameters use `ctx`.
- Empty typed arrays use `string.[]`.
- Command declarations use `BUILD_COMMAND :: Command.{...};`.
- Registry aggregation uses `COMMAND_REGISTRY :: Command.[BUILD_COMMAND, ...];`.
- Prerequisites remain string literals: a struct declaration's `.name` is not accepted as a constant element in a top-level array literal by the current compiler.
- Multi-return procedure types need parenthesized returns, e.g. `#type (driver: *Build_Driver) -> (Workspace_Discovery, bool)`.

## Build and tests

```bash
jai build.jai
./target/juice.exe test
```

The repository is a BIN package (manifest `package.jai`, target = `src/main.jai`); the development loop is `jai build.jai` then `./target/juice.exe test` at the repository root, and `juice test` is the only test entry — it runs the migrated test-block suite. `juice build` self-builds into `target/`, but on Windows the linker cannot overwrite the running `target/juice.exe` (LNK1104), so the dev-loop binary is rebuilt with `jai build.jai`, not by the running binary. E2E tests in the suite spawn `target/juice.exe` (ticket 0023 bootstrap flow: build juice first, then `juice test`). The old per-executable harness (`tests/build_test.jai`) was retired with the migration. `juice build` compiles through a generated metaprogram (`target/build-<name>.jai`); it, the test metaprogram and the bootstrap `build.jai` all set `Build_Options.intermediate_path` to `target/`, so jai intermediates (`.obj`, `.lib`, temp files) land there and leave with Clean.

The inline test blocks live next to the implementation in `src/`: production registry aggregation and command guards in `src/commands/registry.jai`, Run orchestration in `src/commands/run.jai`, Clean policy in `src/commands/clean.jai`, build orchestration in `src/commands/build.jai`, registry validation / lookup / cycle detection / diamond deduplication / argument preflight / failure propagation through the production Dispatcher in `src/dispatcher.jai`, target resolution in `src/target.jai`, the workspace state machine and dependency snapshot consumption in `src/workspace.jai`, the test pipeline in `src/commands/test.jai`, and the transpiler suite in `src/transpile_tests.jai` (kept out of `src/transpile.jai`/`src/transpile_cache.jai`, which the bootstrap metaprogram `#load`s). Exception (2026-10-14 user revision): the monorepo E2E tests live in `tests/test_monorepo.jai` rather than inline in the command files — they are collected by Test discovery like any other test file and run in the same test program.

## Monorepo (workspace member) test coverage

The `tests/data/workspace-*` fixture family (map 0041, fixture ticket 0042) anchors the monorepo matrix: `workspace-ok` is a root BIN depending on two LIB members (both import-entry layouts), `workspace-bad-*` fixtures each break one discovery branch, and `workspace-edge-*` pin the two boundary behaviors. Coverage:

- Discovery validation matrix (ticket 0043): every reachable failure branch is asserted end to end against the real `juice.exe` by its specific error message (`tests/test_monorepo.jai`); the path-validity gate is unit-tested in-process (`src/workspace.jai`). Direct in-process discovery tests are impossible: `load_package_manifest` derives its module directory from the running executable, which is the jai compiler inside the test program. The `does-not-exist` and `escapes-root` branches are defense-in-depth and unreachable via declared member paths.
- Build E2E (ticket 0044): shims link (not fetch) both members at their real import entries, the artifact runs and calls both member functions, and a test-free root closure compiles with zero transpile.
- Clean E2E (ticket 0045): root and member `target/` directories are removed whole while sources survive; members without a target directory don't fail the clean (`delete_directory_full` returns true for nonexistent paths).
- Test E2E (ticket 0046): a root test program resolves a member through its dependency shim and passes; the member's own tests do not run under the root. This exposed a real defect — the test compile injected only the juice modules directory, so no root test could `#import` any dependency (ticket 0048). Fixed by moving `compiler_import_directories` into `src/dependency.jai` and sharing it between Build and Test.
- Boundary behaviors pinned: the root listed as its own member hits the duplicate error; a member's own `workspace.members` declaration is silently ignored (recorded in `CONTEXT.md` under Workspace member).

## Unchanged limitations

- Dispatcher prerequisite execution still happens in the prepared order; only the requested command receives user arguments.
- The existing help formatter can print a `-12` suffix; correcting it is separate from command ownership.
- On the current Windows toolchain, real Clean attempts on populated directories fail with `Invalid switch`. This was reproduced with both this refactor and an independently compiled, unchanged `69974af` snapshot. Command-policy tests pass, but successful deletion of populated directories is not verified on Windows; fixing the filesystem deletion operation is separate work.

See `CONTEXT.md` for domain terminology.
