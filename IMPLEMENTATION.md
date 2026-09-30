# Command Registry Implementation

Juice uses an explicit static command registry and prerequisite Dispatcher. Each command owns its declaration, argument contract, and command-specific implementation; the registry only aggregates declarations. Workspace preparation owns the discovery → resolution → dependency → prepared-workspace state transitions.

## Module ownership

| Module | Responsibility |
| --- | --- |
| `src/commands/command.jai` | Shared `Command`, `Command_Context`, handler and argument-validator types |
| `src/commands/registry.jai` | Static array of command-owned declarations |
| `src/commands/prepare.jai` | Internal discovery/preparation declarations; thin adapters over the workspace state |
| `src/commands/build.jai` | Build declaration, argument contract, compilation, batch revalidation, and prepared-workspace orchestration |
| `src/commands/run.jai` | Run declaration, argument contract, target selection, diagnostics, and artifact launch |
| `src/commands/clean.jai` | Clean declaration, argument contract, cleanup scope, all-path validation, and deletion policy |
| `src/dispatcher.jai` | Registry validation, lookup, planning, and execution; production and test registries share it |
| `src/workspace.jai` | Workspace discovery, member validation, and the discovery/preparation state machine |
| `src/dependency.jai` | Dependency fetching and workspace-member lookup over the discovery snapshot |
| `src/driver.jai` | Process-wide driver: package root, dependency directory, and XDG cache/data/config paths |
| `src/target.jai` | Shared effective-target resolution, artifact plans, and artifact-path revalidation |
| `src/path_safety.jai` | Shared filesystem/path inspection and validation |
| `src/main.jai` | File loading, driver initialization, CLI argument slicing, and dispatch |

Command metadata, prerequisites, visibility, handlers, and the argument contract are declared in the owning command file. Handlers print usage from their own declaration rather than maintaining a second usage string. Adding a command requires adding its file to the load list and its declaration to the registry; no automatic registration is involved.

Build and Run still consume the same artifact plan.

## Dispatcher

`dispatch_command` takes the registry as its input and returns a structured `Dispatch_Result`. Production and tests invoke the same implementation; the tests do not reimplement registry validation or lookup.

The Dispatcher builds and validates the complete selected graph before invoking any handler:

1. Validate the registry: declarations, duplicate names, and missing prerequisites.
2. Look up the requested command; reject unknown and internal commands.
3. Plan the selected graph with the requested command's own argument validator. Invalid arguments stop the dispatch before any prerequisite runs.
4. Detect cycles during planning, before any execution.
5. Execute the ordered graph once per command. Prerequisites receive empty arguments; only the requested command receives the user's arguments.
6. Propagate prerequisite and handler failures with `Dispatch_Result` instead of bare bools.

Internal commands still run as prerequisites, but direct invocation is now rejected with `INTERNAL_COMMAND_INVOKED`.

## Command execution

```text
run → build → prepare-workspace → discover-workspace
build → prepare-workspace → discover-workspace
clean → discovery within its own handler, without dependency preparation
```

- Build compiles all effective targets of the **root package**, not all workspace members.
- Run chooses an explicit, case-sensitive target; otherwise it chooses the only target or the target matching the package name. It launches the selected prepared artifact after Build completes.
- Clean discovers root/member result directories and the root `.packages` directory. Without a manifest, it cleans only the current root's `result` and `.packages`.
- Clean validates every deletion target before deleting any. A deletion failure does not prevent attempts on the remaining validated paths, but the overall result is failure.
- Clean does not prepare dependencies. Discovery may execute manifests, so Clean is not free of manifest side effects.
- Handlers return `bool`; the CLI exits with status 1 on failure.

## Workspace preparation

`Workspace_State` replaces the context's discovery/prepared pairs with one phase (`EMPTY`, `DISCOVERED`, `PREPARED`). The workspace module owns the transitions:

- `ensure_workspace_discovered` publishes the discovery result and prints the discovery message. Repeated calls are idempotent.
- `prepare_workspace` resolves effective targets and artifact plans, then prepares dependencies only when plans exist. It publishes a prepared result only after every required step succeeds; a failed attempt leaves discovery reusable and exposes no partial prepared workspace.
- `get_prepared_workspace` returns the prepared result, or null before preparation. Build and Run consume the result through this accessor.
- The internal discovery/preparation commands are thin adapters over these transitions and no longer own resolution or dependency policy.

`Workspace_Discovery` retains the evaluated member declarations (`member_packages`, root first) instead of only member paths. Dependency preparation consumes this snapshot and no longer re-executes member manifests; workspace-member lookups no longer load manifests.

## Test seams

The production implementation is the test surface:

- `dispatch_command`/`validate_registry` accept a registry, so tests drive the production Dispatcher with test registries instead of copied algorithms.
- `run_prepared_workspace` accepts a launch operation, defaulting to `run_artifact_plan`. Tests use a recording adapter to verify selection, exact artifact/root forwarding, no launch on invalid selection, and launch-failure propagation.
- `clean_discovered_workspace` accepts validation and deletion operations, defaulting to the real filesystem operations. Recording adapters verify deletion scope, all-path validation before deletion, no deletion after validation failure, and continued deletion after an individual failure.
- `build_prepared_workspace` accepts a compile operation, defaulting to `compile_artifact_plan`. Recording adapters verify the targetless no-op, the revalidation gate before any compilation, exact per-plan forwarding, and fail-fast on the first compile failure.
- `ensure_workspace_discovered` and `prepare_workspace` accept discovery, resolution, and dependency operations with production defaults. Tests verify the state transitions, no-dependency no-op for targetless packages, and that failures publish nothing.
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
cd tests
jai build_test.jai
../bin/test_dispatcher.exe
```

`tests/test_commands.jai` covers production registry aggregation, command argument/preparation guards, Run orchestration, and Clean policy. `tests/test_workspace.jai` covers the workspace state machine and dependency snapshot consumption. `tests/test_dispatcher.jai` covers registry validation, lookup, cycle detection, diamond deduplication, argument preflight, and failure propagation through the production Dispatcher.

## Unchanged limitations

- Dispatcher prerequisite execution still happens in the prepared order; only the requested command receives user arguments.
- Juice itself has no `package.jai`; build/run smoke tests need a separate package.
- The existing help formatter can print a `-12` suffix; correcting it is separate from command ownership.
- On the current Windows toolchain, real Clean attempts on populated directories fail with `Invalid switch`. This was reproduced with both this refactor and an independently compiled, unchanged `69974af` snapshot. Command-policy tests pass, but successful deletion of populated directories is not verified on Windows; fixing the filesystem deletion operation is separate work.

See `CONTEXT.md` for domain terminology.
