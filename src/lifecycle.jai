// Lifecycle hook mechanism (ticket 021): the closed nine-stage enum, the
// hook shape ({stage, position, hook}), the per-stage context (stage name +
// stage-observable state slots + the three-level diagnostic sink + the
// per-registration plugin_state slots), the hook-table registration/merge
// surface and the mount dispatch carrying the deterministic ordering and
// the failure semantics.
//
// Ordering (spec §6.4, decided): the stage order is the enum declaration
// order — hardcoded, add-only; command orchestration iterates the stages it
// runs as a subsequence of it. Within one mount the hook order is
// registration declaration order; before and after hooks both run in
// registration order (forward — the reverse-symmetric option was rejected).
// Stages the command never runs (e.g. PRESTEP without a declared hook
// plugin) silently never fire: the dispatch only fires the mount it is
// asked to run, nothing else.
//
// PRESTEP's state (ticket 057, spec §6.1/§6.2 design revision 2026-10-21):
// Prestep_Stage carries the root/member directories the command fills plus
// the append-only source substitution table and drop set the pre-step hooks
// fill. The stage-level table rules live in the prestep_add_* API below: a
// duplicate original with a different replacement, or the same original in
// both tables, records an ERROR diagnostic (which fails the stage by the
// ordinary dispatch rule — even a hook that ignores the return value cannot
// smuggle a conflicting table past the dispatch).
//
// Failure semantics (spec §6.5): a hook returning false or adding an
// ERROR-level diagnostic fails the stage (fail fast — the dispatch stops),
// which fails the command and the exit code. Observer hooks (before/after,
// diagnostics-only) fail the same way — continue-on-failure belongs to the
// test execution layer, not the hook layer.
//
// Cross-stage state = the slot protocol (spec §6.5, decided):
// Lifecycle_Context.plugin_state slots align with hook registration order;
// the host owns the storage; slots are null at construction (the juice
// Transpile_Context precedent, not a framework-injected environment). No
// closures: every channel is explicit data in the context.
//
// This ticket ships the mechanism as a library face only — no command
// orchestration is wired (the at dispatch joins with tickets 027/028, the
// plugin merge/dup-check surface is 024's). main.jai stays untouched.
//
// This module is a bootstrap #load target and must stay test-free; its unit
// tests live in tests/lifecycle_tests.jai (0053 rule).

#import "Basic";

// ---------------------------------------------------------------------------
// Stage enum
// ---------------------------------------------------------------------------

// The closed nine-stage enum (spec §6.1). The declaration order IS the
// hardcoded stage order — command orchestration runs a subsequence of it.
// ADD ONLY: never rename, reorder or remove members — stage names are part
// of the versioned plugin surface (spec §6.1's versioned promise), so a
// rename would silently break the plugins and cache keys referencing it
// (the closed-enum discipline). The tests pin the ordinal order.
Lifecycle_Stage :: enum u8 {
    DISCOVER;    // build/test/clean: workspace state machine (root checks,
                 // manifest eval, member validation)
    PREPARE;     // build/test: artifact plans + dependency resolution/fetch
    VALIDATE;    // build: full revalidation (root/artifacts/sources)
    DEP_STRIP;   // build/test: dependency closure STRIP views + shim rewrites
    PRESTEP;     // build/test: pre-step plugin stage (source substitution table
                 // + drop set; no built-in implementation — undeclared =
                 // no-op). Ticket 057 wires it; the at position stays
                 // reserved for a future whole-stage takeover.
    TRANSPILE;   // build/test: probe / EXPAND views / cache keys
    COMPILE;     // build/test: metaprogram generation + spawn + artifact check
    EXECUTE;     // test/run: compile-time #run execution / artifact launch
    CLEAN;       // clean: path table, validate-then-delete
}

// Reporting surface: the stage's name — the plugin merge face's
// mount-conflict diagnostics (ticket 024) and future reporting use it. The
// add-only discipline extends here: a new stage needs a new case.
stage_name :: (stage: Lifecycle_Stage) -> string {
    if stage == {
        case .DISCOVER;   return "DISCOVER";
        case .PREPARE;    return "PREPARE";
        case .VALIDATE;   return "VALIDATE";
        case .DEP_STRIP;  return "DEP_STRIP";
        case .PRESTEP;    return "PRESTEP";
        case .TRANSPILE;  return "TRANSPILE";
        case .COMPILE;    return "COMPILE";
        case .EXECUTE;    return "EXECUTE";
        case .CLEAN;      return "CLEAN";
    }
    return "?";
}

// ---------------------------------------------------------------------------
// Hook shape
// ---------------------------------------------------------------------------

// The three mounting positions per stage (spec §6.2).
Hook_Position :: enum u8 {
    before;  // observe/transform the stage's inputs, before the stage body
    at;      // replace the stage's implementation (the seam pluginization,
             // spec §6.3)
    after;   // observe/transform the stage's outputs, after the stage body
}

Lifecycle_Hook :: struct {
    stage:    Lifecycle_Stage;
    position: Hook_Position;
    // The hook body: observes/transforms through ctx, reads its
    // registration's plugin_state slot through state. Returns false =
    // stage failure (same as adding an ERROR diagnostic).
    hook: #type (ctx: *Lifecycle_Context, state: *void) -> bool;
}

// ---------------------------------------------------------------------------
// Diagnostics (the three-level sink)
// ---------------------------------------------------------------------------

// The three-level diagnostic sink (the compiler_report shape: ERROR /
// WARNING / INFO — spec §8.2's 三汇). ERROR entries fail the stage;
// WARNING and INFO only report.
Lifecycle_Diagnostic_Level :: enum u8 {
    ERROR;
    WARNING;
    INFO;
}

Lifecycle_Diagnostic :: struct {
    level:   Lifecycle_Diagnostic_Level;
    message: string;
}

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

Lifecycle_Context :: struct {
    // The stage being run. The dispatch sets it, so hooks always observe
    // the stage they were mounted on.
    stage: Lifecycle_Stage;
    // Stage-observable state (spec §6.1 table). The orchestrator fills the
    // slots its stage produces; slots of stages not run stay null. The
    // slots are *void by design — every stage's state is a different type
    // (the same heterogeneous-storage rationale as the plugin_state slots
    // below); hooks and the orchestrator cast. Tickets 027/028 are the
    // first producers; PRESTEP's state (Prestep_Stage) is filled by the
    // build/test commands before the stage dispatches.
    workspace:      *void;  // DISCOVER: Workspace_Discovery (root checks,
                            // manifest, members)
    artifact_plans: *void;  // PREPARE/VALIDATE: artifact plans + dependency
                            // resolution
    views:          *void;  // DEP_STRIP/TRANSPILE: the view table (dep strip
                            // views, EXPAND views, cache keys)
    artifact_paths: *void;  // COMPILE: metaprogram generation, spawn result,
                            // artifact outputs
    prestep:        *void;  // PRESTEP: Prestep_Stage (root/member dirs +
                            // source substitution table + drop set)
    exit_code:      s64;    // EXECUTE: the spawned process exit code (test
                            // #run / run launch)
    paths:          *void;  // CLEAN: the path table (validate-then-delete)
    // The three-level diagnostic sink. Host-owned storage (the orchestrator
    // may reuse one sink across the command); the dispatch inspects only
    // entries added during its own run, so a pre-existing ERROR from an
    // earlier stage never fails a later dispatch.
    diagnostics: *[..] Lifecycle_Diagnostic;
    // Per-registration cross-stage state slots, aligned with the hook
    // table's registration order: registration i's hooks read slot i (a
    // missing slot reads as null). Host-owned storage; slots are null at
    // construction — the juice slot protocol, not a framework-injected
    // env (spec §6.5).
    plugin_state: [..] *void;
}

// ---------------------------------------------------------------------------
// PRESTEP stage state (ticket 057, spec §6.1/§6.2)
// ---------------------------------------------------------------------------

// One source substitution: the original package-relative path -> the
// replacement's absolute path. The pre-step plugin's output; the command
// consumes it to choose compile inputs (the build entry selection and the
// test command's per-file EXPAND source). The table is append-only, covers
// the root package only and never introduces a new file.
Source_Substitution :: struct {
    original:    string;
    replacement: string;
}

// The PRESTEP stage's observable state (spec §6.1 "可观测状态"). The command
// fills root_dir/member_dirs before dispatching (the pre-step plugin scans
// the package itself and skips the member subtrees); the before hooks fill
// the substitution table and the drop set; the command consumes both after
// the stage:
// - build: a substituted entry compiles the replacement path directly
//   (closure probing and strip views are skipped); a dropped entry fails
//   the build with a diagnostic; other plans are untouched;
// - test: a substituted file's EXPAND source comes from the replacement
//   while rel_path, numbering and path_mapping keep the original; a dropped
//   file never enters the test program.
// A stage without hook plugins keeps both tables empty — the no-op shape.
Prestep_Stage :: struct {
    root_dir:      string;                    // the root package dir
    member_dirs:   [..] string;               // workspace member package dirs
                                              // (the root itself excluded)
    substitutions: [..] Source_Substitution;  // append-only (root package only)
    drops:         [..] string;               // dropped package-relative paths
}

// Add one substitution row to the stage (spec §6.2 stage-level rules):
// - the same original with the same replacement is a no-op (stacked hooks
//   re-adding an identical row never fail);
// - the same original with a different replacement is a stage failure — the
//   table cannot answer which replacement wins;
// - an original already in the drop set is a stage failure — a file cannot
//   be both replaced and excluded.
// A failure records an ERROR diagnostic on the context (the ordinary
// dispatch failure rule then fails the stage even when the hook returns
// true) and returns false. A missing prestep slot is the same failure.
prestep_add_substitution :: (ctx: *Lifecycle_Context, original: string, replacement: string) -> bool {
    if ctx.prestep == null {
        array_add(ctx.diagnostics, .{level = .ERROR, message = "source substitution without prestep state"});
        return false;
    }
    stage := cast(*Prestep_Stage) ctx.prestep;
    for s: stage.substitutions {
        if s.original != original continue;
        if s.replacement == replacement return true;
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("conflicting source substitution: %", original)});
        return false;
    }
    for dropped: stage.drops {
        if dropped != original continue;
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("source substitution conflicts with a drop: %", original)});
        return false;
    }
    array_add(*stage.substitutions, .{original = original, replacement = replacement});
    return true;
}

// Add one dropped package-relative path to the stage: a repeated drop is a
// no-op; a path already in the substitution table is a stage failure (the
// same rule as the reverse order in prestep_add_substitution). Failures
// record an ERROR diagnostic and return false.
prestep_add_drop :: (ctx: *Lifecycle_Context, original: string) -> bool {
    if ctx.prestep == null {
        array_add(ctx.diagnostics, .{level = .ERROR, message = "source drop without prestep state"});
        return false;
    }
    stage := cast(*Prestep_Stage) ctx.prestep;
    for dropped: stage.drops {
        if dropped == original return true;
    }
    for s: stage.substitutions {
        if s.original != original continue;
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("drop conflicts with a source substitution: %", original)});
        return false;
    }
    array_add(*stage.drops, original);
    return true;
}

// The replacement of a substituted original; ("", false) when the path is
// not substituted (or the stage is null — the undeclared no-op shape).
prestep_substitution_for :: (stage: *Prestep_Stage, original: string) -> (string, bool) {
    if stage == null return "", false;
    for s: stage.substitutions {
        if s.original == original return s.replacement, true;
    }
    return "", false;
}

// Whether the pre-step dropped a package-relative path (a null stage drops
// nothing — the undeclared no-op shape).
prestep_is_dropped :: (stage: *Prestep_Stage, original: string) -> bool {
    if stage == null return false;
    for dropped: stage.drops {
        if dropped == original return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Hook table: registration and merge
// ---------------------------------------------------------------------------

// One registration: a plugin's hooks contribution (its `hooks` array, spec
// §5.1). All hooks of one registration share one plugin_state slot — slot
// index = registration index in the table. Registration order = declaration
// order = execution order.
Hook_Registration :: struct {
    hooks: [..] Lifecycle_Hook;
}

// Register one contribution into the hook table. Empty contributions are
// skipped: they have no hooks, so they must not consume a state slot (slot
// indices would shift for every later registration). The hooks are copied
// into the registration's own array (the caller's array may be a temporary
// or a slice of a larger one).
register_hooks :: (table: *[..] Hook_Registration, hooks: [] Lifecycle_Hook) {
    if hooks.count == 0 return;
    reg: Hook_Registration;
    for h: hooks array_add(*reg.hooks, h);
    array_add(table, reg);
}

// Concatenate two hook tables in order (a's registrations first) — the
// merge preserves declaration order across contributions.
merge_hook_tables :: (a: [] Hook_Registration, b: [] Hook_Registration) -> [..] Hook_Registration {
    merged: [..] Hook_Registration;
    for r: a array_add(*merged, r);
    for r: b array_add(*merged, r);
    return merged;
}

// ---------------------------------------------------------------------------
// Mount dispatch
// ---------------------------------------------------------------------------

// Run the hooks mounted at one (stage, position) in registration order
// (before and after both forward, spec §6.4). Each hook receives its
// registration's plugin_state slot (slot i for registration i; missing
// slots read as null). Stages never dispatched silently never fire — this
// function is the only firing point.
//
// Failure semantics (spec §6.5): a hook returning false or adding an
// ERROR-level diagnostic fails the stage — the dispatch stops immediately
// (fail fast; observer hooks get the same abort treatment) and the caller
// fails the command. Only diagnostics added during this dispatch count, so
// the host may reuse one sink across stages.
run_mounted_hooks :: (table: [] Hook_Registration, stage: Lifecycle_Stage, position: Hook_Position, ctx: *Lifecycle_Context) -> bool {
    ctx.stage = stage;
    before := ctx.diagnostics.count;
    for r, i: table {
        for h: r.hooks {
            if h.stage != stage || h.position != position continue;
            state: *void = null;
            if i < ctx.plugin_state.count state = ctx.plugin_state[i];
            if !h.hook(ctx, state) return false;
            if has_new_error(ctx.diagnostics, before) return false;
        }
    }
    return true;
}

// Any ERROR-level entry in the sink at/after index `from`? The dispatch's
// failure check inspects only entries added during its own run (the host
// may reuse one sink across stages).
has_new_error :: (diagnostics: *[..] Lifecycle_Diagnostic, from: s64) -> bool {
    for i: from..diagnostics.count-1 {
        if diagnostics.*[i].level == .ERROR return true;
    }
    return false;
}

// Whether any registration mounts a hook at (stage, position). The at
// dispatch's replacement query (spec 004 decision 17): a mounted at hook
// replaces the stage's built-in implementation; no mount means the built-in
// runs — the empty hook set is the default pipeline. The table is expected
// to be a merge product, where at exclusivity per stage is already enforced
// (ticket 024's merge_plugins).
has_mounted_hook :: (table: [] Hook_Registration, stage: Lifecycle_Stage, position: Hook_Position) -> bool {
    for r: table {
        for h: r.hooks {
            if h.stage == stage && h.position == position return true;
        }
    }
    return false;
}
