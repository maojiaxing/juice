// ---------------------------------------------------------------------------
// Lifecycle hook mechanism tests (ticket 021): the closed stage enum, the
// registration/merge surface and the mount dispatch — proven with synthetic
// recording hooks. Pinned behavior: the hardcoded stage order (add-only
// discipline), registration declaration order within a stage (before and
// after both forward), mount filtering (only the requested stage/position
// fires; unvisited stages stay silent), the failure semantics (false return
// or ERROR diagnostic fails the stage, fail fast, observer hooks included;
// only diagnostics added during the dispatch count) and the plugin_state
// slot protocol (one slot per registration, aligned with registration
// order, missing slots read as null, empty contributions consume nothing).
//
// Key constraint (same as the other sibling test files): src modules are
// bootstrap #load targets / entry closure members — test blocks would be
// illegal inside them, so this module stays test-free and its tests live
// here (tests/), per the test organization rule: referenced by no #load,
// collected into the test program by Test discovery's full-package scan.
// This file contains only test blocks and their helper declarations; zero
// production code coupling. Good-test standard: only external behavior is
// pinned (given hook set + stage/position -> firing trace / diagnostics /
// dispatch result); the dispatch internals are never asserted.
// ---------------------------------------------------------------------------

#import "Basic";
#import "Testing";
#import "String";

// ===========================================================================
// The synthetic recording hook
// ===========================================================================
//
// One hook procedure serves every fake: it records its label into the
// shared trace the state points at, records the ctx.stage it observed, and
// returns/emits diagnostics per the state's flags. The state travels
// through the plugin_state slot the dispatch hands over — so the trace also
// pins the slot-alignment channel itself.

// Null-slot pass-through records here (a file-scope sink — the null hook
// has no state of its own to record into).
NULL_TRACE: [..] string;

Rec_State :: struct {
    trace:      *[..] string;         // shared trace sink (the caller's array)
    label:      string;
    result:     bool = true;          // the hook's return value
    add_diag:   bool = false;         // add a diagnostic before returning
    add_level:  Lifecycle_Diagnostic_Level = .INFO;
    last_stage: Lifecycle_Stage;      // the ctx.stage the hook observed
}

rec_hook :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    if state == null {
        // Missing slot = null state: the dispatch must pass it through
        // untouched (the slot protocol's read-as-null convention).
        array_add(*NULL_TRACE, "null");
        return true;
    }
    rec := cast(*Rec_State) state;
    array_add(rec.trace, rec.label);
    rec.last_stage = ctx.stage;
    if rec.add_diag array_add(ctx.diagnostics, .{level = rec.add_level, message = tprint("rec diag: %", rec.label)});
    return rec.result;
}

// One-hook registration around the recording hook.
rec_reg :: (stage: Lifecycle_Stage, position: Hook_Position, state: *Rec_State) -> Hook_Registration {
    reg: Hook_Registration;
    array_add(*reg.hooks, .{stage = stage, position = position, hook = rec_hook});
    return reg;
}

// A context whose diagnostics point at the caller's sink.
rec_ctx :: (stage: Lifecycle_Stage, diags: *[..] Lifecycle_Diagnostic) -> Lifecycle_Context {
    ctx: Lifecycle_Context;
    ctx.stage = stage;
    ctx.diagnostics = diags;
    return ctx;
}

// ===========================================================================
// Unit tests over the lifecycle mechanism
// ===========================================================================

test "Lifecycle: the nine stages sit in the hardcoded order (add-only discipline)" {
    // The enum declaration order IS the stage order; the add-only promise
    // (spec §6.1) makes any rename/reorder/removal break this pin.
    expect(cast(s64) Lifecycle_Stage.DISCOVER == 0);
    expect(cast(s64) Lifecycle_Stage.PREPARE == 1);
    expect(cast(s64) Lifecycle_Stage.VALIDATE == 2);
    expect(cast(s64) Lifecycle_Stage.DEP_STRIP == 3);
    expect(cast(s64) Lifecycle_Stage.PRESTEP == 4);
    expect(cast(s64) Lifecycle_Stage.TRANSPILE == 5);
    expect(cast(s64) Lifecycle_Stage.COMPILE == 6);
    expect(cast(s64) Lifecycle_Stage.EXECUTE == 7);
    expect(cast(s64) Lifecycle_Stage.CLEAN == 8);
}

test "Lifecycle: before hooks run in registration order" {
    trace: [..] string;
    st_a: Rec_State;
    st_a.trace = *trace;
    st_a.label = "a";
    st_b: Rec_State;
    st_b.trace = *trace;
    st_b.label = "b";
    st_c: Rec_State;
    st_c.trace = *trace;
    st_c.label = "c";

    table: [..] Hook_Registration;
    register_hooks(*table, rec_reg(.TRANSPILE, .before, *st_a).hooks);
    register_hooks(*table, rec_reg(.TRANSPILE, .before, *st_b).hooks);
    register_hooks(*table, rec_reg(.TRANSPILE, .before, *st_c).hooks);

    diags: [..] Lifecycle_Diagnostic;
    ctx := rec_ctx(.TRANSPILE, *diags);
    array_add(*ctx.plugin_state, *st_a);
    array_add(*ctx.plugin_state, *st_b);
    array_add(*ctx.plugin_state, *st_c);

    expect(run_mounted_hooks(table, .TRANSPILE, .before, *ctx));
    expect(trace.count == 3);
    expect(trace[0] == "a" && trace[1] == "b" && trace[2] == "c");
}

test "Lifecycle: after hooks also run in registration order (forward)" {
    // The reverse-symmetric option was rejected (spec §6.4): after hooks
    // are NOT reversed — same forward declaration order as before hooks.
    trace: [..] string;
    st_a: Rec_State;
    st_a.trace = *trace;
    st_a.label = "a";
    st_b: Rec_State;
    st_b.trace = *trace;
    st_b.label = "b";

    table: [..] Hook_Registration;
    register_hooks(*table, rec_reg(.TRANSPILE, .after, *st_a).hooks);
    register_hooks(*table, rec_reg(.TRANSPILE, .after, *st_b).hooks);

    diags: [..] Lifecycle_Diagnostic;
    ctx := rec_ctx(.TRANSPILE, *diags);
    array_add(*ctx.plugin_state, *st_a);
    array_add(*ctx.plugin_state, *st_b);

    expect(run_mounted_hooks(table, .TRANSPILE, .after, *ctx));
    expect(trace.count == 2);
    expect(trace[0] == "a" && trace[1] == "b");
}

test "Lifecycle: only the requested mount fires" {
    // Hooks on other stages/positions stay silent — the dispatch fires
    // exactly the (stage, position) pair it is asked to run, including the
    // at position (its orchestration joins with tickets 027/028; the
    // dispatch itself is position-agnostic).
    trace: [..] string;
    st_pb: Rec_State;
    st_pb.trace = *trace;
    st_pb.label = "prep-before";
    st_tb: Rec_State;
    st_tb.trace = *trace;
    st_tb.label = "trans-before";
    st_ta: Rec_State;
    st_ta.trace = *trace;
    st_ta.label = "trans-after";
    st_ca: Rec_State;
    st_ca.trace = *trace;
    st_ca.label = "compile-at";

    table: [..] Hook_Registration;
    register_hooks(*table, rec_reg(.PREPARE, .before, *st_pb).hooks);
    register_hooks(*table, rec_reg(.TRANSPILE, .before, *st_tb).hooks);
    register_hooks(*table, rec_reg(.TRANSPILE, .after, *st_ta).hooks);
    register_hooks(*table, rec_reg(.COMPILE, .at, *st_ca).hooks);

    diags: [..] Lifecycle_Diagnostic;
    ctx := rec_ctx(.TRANSPILE, *diags);
    array_add(*ctx.plugin_state, *st_pb);
    array_add(*ctx.plugin_state, *st_tb);
    array_add(*ctx.plugin_state, *st_ta);
    array_add(*ctx.plugin_state, *st_ca);

    expect(run_mounted_hooks(table, .TRANSPILE, .before, *ctx));
    expect(trace.count == 1);
    expect(trace[0] == "trans-before");
    expect(diags.count == 0);

    // The at mount dispatches like any other position.
    expect(run_mounted_hooks(table, .COMPILE, .at, *ctx));
    expect(trace.count == 2);
    expect(trace[1] == "compile-at");
}

test "Lifecycle: a stage never dispatched silently never fires" {
    // PRESTEP without a declared hook plugin: the command never dispatches
    // it, so its hooks stay silent — no trace, no diagnostics, no failure
    // (jaix soft_fail semantics, spec §6.4).
    trace: [..] string;
    st_p: Rec_State;
    st_p.trace = *trace;
    st_p.label = "prestep";

    table: [..] Hook_Registration;
    register_hooks(*table, rec_reg(.PRESTEP, .before, *st_p).hooks);

    diags: [..] Lifecycle_Diagnostic;
    ctx := rec_ctx(.TRANSPILE, *diags);
    array_add(*ctx.plugin_state, *st_p);

    expect(run_mounted_hooks(table, .TRANSPILE, .before, *ctx));
    expect(trace.count == 0);
    expect(diags.count == 0);
}

test "Lifecycle: a false-returning hook fails the stage and stops the dispatch" {
    trace: [..] string;
    st_a: Rec_State;
    st_a.trace = *trace;
    st_a.label = "a";
    st_a.result = false;
    st_b: Rec_State;
    st_b.trace = *trace;
    st_b.label = "b";
    st_c: Rec_State;
    st_c.trace = *trace;
    st_c.label = "c";

    table: [..] Hook_Registration;
    register_hooks(*table, rec_reg(.TRANSPILE, .before, *st_a).hooks);
    register_hooks(*table, rec_reg(.TRANSPILE, .before, *st_b).hooks);
    register_hooks(*table, rec_reg(.TRANSPILE, .before, *st_c).hooks);

    diags: [..] Lifecycle_Diagnostic;
    ctx := rec_ctx(.TRANSPILE, *diags);
    array_add(*ctx.plugin_state, *st_a);
    array_add(*ctx.plugin_state, *st_b);
    array_add(*ctx.plugin_state, *st_c);

    expect(!run_mounted_hooks(table, .TRANSPILE, .before, *ctx));
    // Fail fast: the later hooks never ran. False alone fails — no
    // diagnostic needed.
    expect(trace.count == 1);
    expect(trace[0] == "a");
    expect(diags.count == 0);
}

test "Lifecycle: an ERROR diagnostic fails the stage (WARNING/INFO do not)" {
    trace: [..] string;
    st_a: Rec_State;
    st_a.trace = *trace;
    st_a.label = "a";
    st_a.add_diag = true;

    table: [..] Hook_Registration;
    register_hooks(*table, rec_reg(.TRANSPILE, .before, *st_a).hooks);

    diags: [..] Lifecycle_Diagnostic;
    ctx := rec_ctx(.TRANSPILE, *diags);
    array_add(*ctx.plugin_state, *st_a);

    st_a.add_level = .ERROR;
    expect(!run_mounted_hooks(table, .TRANSPILE, .before, *ctx));
    expect(diags.count == 1);
    expect(diags[0].level == .ERROR);
    expect(diags[0].message == "rec diag: a");

    // WARNING: reported, does not fail (the observer-hook channel).
    array_reset(*diags);
    st_a.add_level = .WARNING;
    expect(run_mounted_hooks(table, .TRANSPILE, .before, *ctx));
    expect(diags.count == 1);
    expect(diags[0].level == .WARNING);

    // INFO: reported, does not fail.
    array_reset(*diags);
    st_a.add_level = .INFO;
    expect(run_mounted_hooks(table, .TRANSPILE, .before, *ctx));
    expect(diags.count == 1);
    expect(diags[0].level == .INFO);
}

test "Lifecycle: only diagnostics added during the dispatch count" {
    // The host may reuse one sink across the command: an ERROR from an
    // earlier stage (already handled) must not fail a later dispatch.
    trace: [..] string;
    st_a: Rec_State;
    st_a.trace = *trace;
    st_a.label = "a";

    table: [..] Hook_Registration;
    register_hooks(*table, rec_reg(.TRANSPILE, .before, *st_a).hooks);

    diags: [..] Lifecycle_Diagnostic;
    array_add(*diags, .{level = .ERROR, message = "earlier stage error"});
    ctx := rec_ctx(.TRANSPILE, *diags);
    array_add(*ctx.plugin_state, *st_a);

    expect(run_mounted_hooks(table, .TRANSPILE, .before, *ctx));
    expect(diags.count == 1);
    expect(diags[0].message == "earlier stage error");
}

test "Lifecycle: one plugin_state slot per registration, aligned with registration order" {
    // Registration A contributes two hooks (before + after on the same
    // stage) — both must read slot 0; registration B's single hook reads
    // slot 1. The trace shape pins it: if slots were per-hook instead of
    // per-registration, A's after hook would read B's slot and record "b".
    trace: [..] string;
    st_a: Rec_State;
    st_a.trace = *trace;
    st_a.label = "a";
    st_b: Rec_State;
    st_b.trace = *trace;
    st_b.label = "b";

    reg_a: Hook_Registration;
    array_add(*reg_a.hooks, .{stage = .TRANSPILE, position = .before, hook = rec_hook});
    array_add(*reg_a.hooks, .{stage = .TRANSPILE, position = .after, hook = rec_hook});

    table: [..] Hook_Registration;
    register_hooks(*table, reg_a.hooks);
    register_hooks(*table, rec_reg(.TRANSPILE, .before, *st_b).hooks);

    diags: [..] Lifecycle_Diagnostic;
    ctx := rec_ctx(.TRANSPILE, *diags);
    array_add(*ctx.plugin_state, *st_a);
    array_add(*ctx.plugin_state, *st_b);

    expect(run_mounted_hooks(table, .TRANSPILE, .before, *ctx));
    expect(run_mounted_hooks(table, .TRANSPILE, .after, *ctx));
    expect(trace.count == 3);
    expect(trace[0] == "a" && trace[1] == "b" && trace[2] == "a");
}

test "Lifecycle: a missing slot reads as null" {
    // Slots shorter than the table: the registration without a slot gets
    // null state — the hook still runs, and the null is passed through
    // untouched (the juice slot protocol's read-as-null convention).
    array_reset(*NULL_TRACE);
    trace: [..] string;
    st_a: Rec_State;
    st_a.trace = *trace;
    st_a.label = "a";
    st_b: Rec_State;
    st_b.trace = *trace;
    st_b.label = "b";

    table: [..] Hook_Registration;
    register_hooks(*table, rec_reg(.TRANSPILE, .before, *st_a).hooks);
    register_hooks(*table, rec_reg(.TRANSPILE, .before, *st_b).hooks);

    diags: [..] Lifecycle_Diagnostic;
    ctx := rec_ctx(.TRANSPILE, *diags);
    array_add(*ctx.plugin_state, *st_a);   // slot 1 absent

    expect(run_mounted_hooks(table, .TRANSPILE, .before, *ctx));
    expect(trace.count == 1);
    expect(trace[0] == "a");
    expect(NULL_TRACE.count == 1);
    expect(NULL_TRACE[0] == "null");
}

test "Lifecycle: an empty contribution registers nothing and consumes no slot" {
    trace: [..] string;
    st_a: Rec_State;
    st_a.trace = *trace;
    st_a.label = "a";

    table: [..] Hook_Registration;
    register_hooks(*table, Lifecycle_Hook.[]);
    expect(table.count == 0);
    register_hooks(*table, rec_reg(.TRANSPILE, .before, *st_a).hooks);
    register_hooks(*table, Lifecycle_Hook.[]);
    expect(table.count == 1);

    // The surviving registration still owns slot 0 — an empty contribution
    // must not shift slot indices.
    diags: [..] Lifecycle_Diagnostic;
    ctx := rec_ctx(.TRANSPILE, *diags);
    array_add(*ctx.plugin_state, *st_a);

    expect(run_mounted_hooks(table, .TRANSPILE, .before, *ctx));
    expect(trace.count == 1);
    expect(trace[0] == "a");
}

test "Lifecycle: merge concatenates tables in order" {
    trace: [..] string;
    st_x: Rec_State;
    st_x.trace = *trace;
    st_x.label = "x";
    st_y: Rec_State;
    st_y.trace = *trace;
    st_y.label = "y";

    table_a: [..] Hook_Registration;
    register_hooks(*table_a, rec_reg(.TRANSPILE, .before, *st_x).hooks);
    table_b: [..] Hook_Registration;
    register_hooks(*table_b, rec_reg(.TRANSPILE, .before, *st_y).hooks);

    merged := merge_hook_tables(table_a, table_b);

    diags: [..] Lifecycle_Diagnostic;
    ctx := rec_ctx(.TRANSPILE, *diags);
    array_add(*ctx.plugin_state, *st_x);
    array_add(*ctx.plugin_state, *st_y);

    expect(run_mounted_hooks(merged, .TRANSPILE, .before, *ctx));
    expect(trace.count == 2);
    expect(trace[0] == "x" && trace[1] == "y");
}

test "Lifecycle: the dispatch sets ctx.stage to the stage being run" {
    // Hooks observe the stage they were mounted on — even when the caller
    // constructed the context with a different stage (the dispatch is the
    // single firing point and makes the field authoritative).
    trace: [..] string;
    st_a: Rec_State;
    st_a.trace = *trace;
    st_a.label = "a";

    table: [..] Hook_Registration;
    register_hooks(*table, rec_reg(.TRANSPILE, .before, *st_a).hooks);

    diags: [..] Lifecycle_Diagnostic;
    ctx := rec_ctx(.CLEAN, *diags);
    array_add(*ctx.plugin_state, *st_a);

    expect(run_mounted_hooks(table, .TRANSPILE, .before, *ctx));
    expect(st_a.last_stage == .TRANSPILE);
}

test "Lifecycle: has_mounted_hook reports the mount's presence" {
    // The at dispatch's replacement query: a hook mounted at one
    // (stage, position) is reported there and nowhere else.
    st_a: Rec_State;

    table: [..] Hook_Registration;
    register_hooks(*table, rec_reg(.TRANSPILE, .before, *st_a).hooks);
    register_hooks(*table, rec_reg(.COMPILE, .at, *st_a).hooks);

    expect(has_mounted_hook(table, .TRANSPILE, .before));
    expect(has_mounted_hook(table, .COMPILE, .at));
    expect(!has_mounted_hook(table, .TRANSPILE, .at));
    expect(!has_mounted_hook(table, .COMPILE, .before));
    expect(!has_mounted_hook(table, .DEP_STRIP, .before));

    empty: [..] Hook_Registration;
    expect(!has_mounted_hook(empty, .COMPILE, .at));
}

// ===========================================================================
// PRESTEP stage state (ticket 057): the source substitution table + drop set
// ===========================================================================
//
// The recording fake pre-step plugin: one hook across the same lifecycle hook
// face — it reads the stage through ctx.prestep and fills the tables through
// the stage-level API (the conflict rules live there). No jaix dependency
// anywhere: the mechanism is plugin-agnostic by contract.

PS_TRACE: [..] string;
PS_SUBSTITUTIONS: [..] Source_Substitution;
PS_DROPS: [..] string;

ps_reset :: () {
    array_reset(*PS_TRACE);
    array_reset(*PS_SUBSTITUTIONS);
    array_reset(*PS_DROPS);
}

// The fake plugin's before hook: fills the scripted rows.
ps_hook_fill :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    array_add(*PS_TRACE, "fill");
    for s: PS_SUBSTITUTIONS {
        if !prestep_add_substitution(ctx, s.original, s.replacement) return false;
    }
    for d: PS_DROPS {
        if !prestep_add_drop(ctx, d) return false;
    }
    return true;
}

// The after hook: records what the before hooks filled (the state channel).
ps_hook_record :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    stage := cast(*Prestep_Stage) ctx.prestep;
    array_add(*PS_TRACE, tprint("after:%1:%2", stage.substitutions.count, stage.drops.count));
    return true;
}

ps_hook_fail :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    array_add(*PS_TRACE, "fail");
    return false;
}

// Adds one conflicting row and returns true on purpose: the ERROR diagnostic
// the stage-level API records must fail the stage on its own — the hook's
// return value cannot smuggle the conflict past the dispatch.
ps_hook_conflict_returns_true :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    ok := prestep_add_substitution(ctx, "src/a.jai", "C:/other/a.jai");
    array_add(*PS_TRACE, ifx ok then "conflict-ok" else "conflict-rejected");
    return true;
}

test "Lifecycle: PRESTEP before hooks fill the substitution table and the drop set" {
    ps_reset();
    array_add(*PS_SUBSTITUTIONS, .{original = "src/a.jai", replacement = "C:/mirror/a.jai"});
    array_add(*PS_SUBSTITUTIONS, .{original = "src/b.jai", replacement = "C:/mirror/b.jai"});
    array_add(*PS_DROPS, "config.toml");

    stage: Prestep_Stage;
    stage.root_dir = "C:/pkg";
    array_add(*stage.member_dirs, "C:/pkg/packages/member-a");

    table: [..] Hook_Registration;
    register_hooks(*table, .[.{stage = .PRESTEP, position = .before, hook = ps_hook_fill}]);
    register_hooks(*table, .[.{stage = .PRESTEP, position = .after, hook = ps_hook_record}]);

    diags: [..] Lifecycle_Diagnostic;
    ctx := rec_ctx(.PRESTEP, *diags);
    ctx.prestep = *stage;

    expect(run_mounted_hooks(table, .PRESTEP, .before, *ctx));
    expect(run_mounted_hooks(table, .PRESTEP, .after, *ctx));
    expect(PS_TRACE.count == 2);
    expect(PS_TRACE[0] == "fill");
    // The after hook observes the before hooks' rows through the same state.
    expect(PS_TRACE[1] == "after:2:1");
    expect(stage.substitutions.count == 2 && stage.drops.count == 1);
    expect(stage.root_dir == "C:/pkg");
    expect(stage.member_dirs.count == 1 && stage.member_dirs[0] == "C:/pkg/packages/member-a");
    replacement, found := prestep_substitution_for(*stage, "src/b.jai");
    expect(found && replacement == "C:/mirror/b.jai");
    expect(prestep_is_dropped(*stage, "config.toml"));
    expect(diags.count == 0);
}

test "Lifecycle: a false-returning PRESTEP hook fails the stage and stops the dispatch" {
    ps_reset();
    table: [..] Hook_Registration;
    register_hooks(*table, .[.{stage = .PRESTEP, position = .before, hook = ps_hook_fail}]);
    register_hooks(*table, .[.{stage = .PRESTEP, position = .after, hook = ps_hook_record}]);

    stage: Prestep_Stage;
    diags: [..] Lifecycle_Diagnostic;
    ctx := rec_ctx(.PRESTEP, *diags);
    ctx.prestep = *stage;

    expect(!run_mounted_hooks(table, .PRESTEP, .before, *ctx));
    // Fail fast: the after hook never fires.
    expect(PS_TRACE.count == 1 && PS_TRACE[0] == "fail");
    expect(diags.count == 0);
}

test "Lifecycle: a conflicting substitution fails the stage through its ERROR diagnostic" {
    // The stage-level table rule (spec §6.2): a duplicate original with a
    // different replacement records an ERROR diagnostic. Even a hook that
    // returns true cannot smuggle the conflicting table past the dispatch —
    // the dispatch's ordinary ERROR check fails the stage.
    ps_reset();
    stage: Prestep_Stage;
    array_add(*stage.substitutions, .{original = "src/a.jai", replacement = "C:/mirror/a.jai"});

    table: [..] Hook_Registration;
    register_hooks(*table, .[.{stage = .PRESTEP, position = .before, hook = ps_hook_conflict_returns_true}]);
    register_hooks(*table, .[.{stage = .PRESTEP, position = .after, hook = ps_hook_record}]);

    diags: [..] Lifecycle_Diagnostic;
    ctx := rec_ctx(.PRESTEP, *diags);
    ctx.prestep = *stage;

    expect(!run_mounted_hooks(table, .PRESTEP, .before, *ctx));
    expect(PS_TRACE.count == 1 && PS_TRACE[0] == "conflict-rejected");
    expect(diags.count == 1);
    expect(diags[0].level == .ERROR);
    expect(diags[0].message == "conflicting source substitution: src/a.jai");
    // The rejected row never entered the table.
    expect(stage.substitutions.count == 1);
}

test "Lifecycle: the prestep table rules absorb duplicates and reject both cross-conflicts" {
    stage: Prestep_Stage;
    diags: [..] Lifecycle_Diagnostic;
    ctx := rec_ctx(.PRESTEP, *diags);
    ctx.prestep = *stage;

    // The same original with the same replacement: a no-op (stacked hooks
    // re-adding an identical row never fail, the row is not duplicated).
    expect(prestep_add_substitution(*ctx, "src/a.jai", "C:/mirror/a.jai"));
    expect(prestep_add_substitution(*ctx, "src/a.jai", "C:/mirror/a.jai"));
    expect(stage.substitutions.count == 1 && diags.count == 0);

    // The same original with a different replacement: stage failure.
    expect(!prestep_add_substitution(*ctx, "src/a.jai", "C:/other/a.jai"));
    expect(stage.substitutions.count == 1);
    expect(diags.count == 1 && diags[0].level == .ERROR);
    expect(diags[0].message == "conflicting source substitution: src/a.jai");

    // A drop of a substituted key: stage failure (one direction).
    array_reset(*diags);
    expect(!prestep_add_drop(*ctx, "src/a.jai"));
    expect(diags.count == 1);
    expect(diags[0].message == "drop conflicts with a source substitution: src/a.jai");
    expect(stage.drops.count == 0);

    // A repeated drop is a no-op; a substitution of a dropped key fails (the
    // other direction).
    array_reset(*diags);
    expect(prestep_add_drop(*ctx, "cfg.toml"));
    expect(prestep_add_drop(*ctx, "cfg.toml"));
    expect(stage.drops.count == 1 && diags.count == 0);
    expect(!prestep_add_substitution(*ctx, "cfg.toml", "C:/mirror/cfg.toml"));
    expect(diags.count == 1);
    expect(diags[0].message == "source substitution conflicts with a drop: cfg.toml");
    expect(stage.substitutions.count == 1);

    // The lookups: misses read as untouched; a null stage is the no-op
    // shape (the undeclared-package convention).
    replacement, found := prestep_substitution_for(*stage, "src/zzz.jai");
    expect(!found && replacement == "");
    expect(!prestep_is_dropped(*stage, "src/zzz.jai"));
    expect(prestep_is_dropped(*stage, "cfg.toml"));
    replacement, found = prestep_substitution_for(null, "src/a.jai");
    expect(!found && replacement == "");
    expect(!prestep_is_dropped(null, "cfg.toml"));
}

test "Lifecycle: the prestep API fails without a prestep slot" {
    // A hook running outside a PRESTEP dispatch (or a host that forgot to
    // fill the slot) must fail loudly, never silently drop the row.
    diags: [..] Lifecycle_Diagnostic;
    ctx := rec_ctx(.PRESTEP, *diags);
    expect(ctx.prestep == null);   // null at construction (the slot protocol)

    expect(!prestep_add_substitution(*ctx, "src/a.jai", "C:/mirror/a.jai"));
    expect(diags.count == 1 && diags[0].level == .ERROR);
    expect(find_index_from_left(diags[0].message, "without prestep state") >= 0);
    expect(!prestep_add_drop(*ctx, "cfg.toml"));
    expect(diags.count == 2);
}

