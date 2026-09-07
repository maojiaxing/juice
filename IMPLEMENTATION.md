# Command Registry Implementation

This branch implements a static command registry and dispatcher system for Juice, inspired by Rust's `linkme` library's distributed-registration pattern but adapted to Jai's static compilation model.

## Architecture Changes

### Core Components

1. **Command Registry** (`src/commands/registry.jai`)
   - Static array of `Command` structs
   - Explicit declarations for all built-in commands
   - Defines command metadata, prerequisites, visibility, and handlers

2. **Dispatcher** (`src/dispatcher.jai`)
   - Registry validation (duplicates, missing prerequisites, cycles)
   - Command lookup with visibility filtering
   - Prerequisite graph traversal with once-per-dispatch execution
   - Failure propagation and short-circuiting
   - Auto-generated usage/help from registry

3. **Command Handlers** (`src/commands/`)
   - `command.jai`: Shared types (`Command`, `Command_Context`, `Command_Handler`)
   - `prepare.jai`: Internal workspace preparation (manifest loading, dependency resolution)
   - `build.jai`: Build all targets
   - `run.jai`: Build and run executable target
   - `clean.jai`: Remove build outputs without workspace preparation

4. **Main Integration** (`src/main.jai`)
   - Simplified to driver initialization and dispatch invocation
   - No longer performs unconditional workspace preparation
   - Command-specific argument slicing

### Command Dependency Graph

```
run → build → prepare-workspace
build → prepare-workspace
clean → (no prerequisites)
```

### Key Design Decisions

- **Explicit static registry**: Uses Jai's `Type.[...]` array literal syntax instead of linker-section magic
- **Command-owned preparation**: Each command declares its prerequisites; `clean` avoids expensive manifest/dependency operations
- **Internal commands**: `prepare-workspace` is not user-invocable but serves as a prerequisite
- **Once-per-dispatch execution**: Diamond dependencies (e.g., `run` needing both `build` and `prepare-workspace` transitively) execute shared prerequisites only once
- **Failure ownership**: Handlers return `bool`; main loop calls `exit(1)`
- **Argument ownership**: Each handler parses only arguments after the command name

## Implementation Notes

### Jai-Specific Constraints

- `context` is a reserved keyword; all handler parameters use `ctx` instead
- Empty typed arrays use `string.[]` syntax
- Function pointer types: `Handler :: #type (ctx: *T, args: [] string) -> bool;`
- Static arrays of structs: `REGISTRY :: Command.[.{...}, .{...}];`

### Testing

Tests verify:
- Registry validation (duplicates, missing prerequisites)
- Visible vs. internal command lookup
- Graph traversal logic

Test execution:
```bash
cd tests
jai build_test.jai
cd ..
./bin/test_dispatcher.exe
```

All tests pass.

### Verification

- ✅ Build succeeds
- ✅ `clean` works without `package.jai`
- ✅ Unknown commands rejected before workspace preparation
- ✅ Usage message generated from registry
- ✅ Tests confirm validation logic

### Limitations

- Juice itself has no `package.jai`, so `build`/`run` fail in this repository (expected)
- Full integration testing requires a separate Jai package with dependencies
- The `-12` suffix in help output suggests a format-width issue in the print statement

## Domain Model

See `CONTEXT.md` for terminology definitions used throughout the implementation.

## Related

- Original request: Adapt Rust `linkme`'s distributed registration pattern to Juice CLI
- Design selections captured in the conversation summary
- No linker-section mechanism used; pure static composition via `#load`
