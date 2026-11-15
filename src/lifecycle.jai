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
// The derived view below is the published plugin face's own path/registration
// surface, so the file-system checks it performs (retained-source presence,
// derived writes) use the compiler's standard modules directly instead of the
// tool-side path helpers — the plugin face closure is exactly the four files
// publication.jai publishes, and File/File_Utilities/String are compiler
// modules every consumer has.
#import "File";
#import "File_Utilities";
#import "String";

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

// One registered auxiliary source (spec 0087 decision 24, ticket 0092): the
// logical package-relative path imports, diagnostics and test attribution
// keep, plus the physical file inside the consuming package's private derived
// directory. The logical path is never an absolute path and never escapes the
// package root; the physical path is only ever read.
Generated_Source :: struct {
    logical_path:  string;
    physical_path: string;
}

// The PRESTEP stage's observable state (spec §6.1 "可观测状态" + spec 0087
// decision 24's derived view, ticket 0092). The command fills
// root_dir/member_dirs and the two derived-view roots before dispatching; the
// before hooks fill the substitution table, the drop set and the generated
// auxiliary sources; the command consumes them after the stage:
// - build: a substituted entry compiles the replacement path directly
//   (closure probing and strip views are skipped); a dropped entry fails
//   the build with a diagnostic; other plans are untouched;
// - test: a substituted file's EXPAND source comes from the replacement
//   while rel_path, numbering and path_mapping keep the original; a dropped
//   file never enters the test program.
// A stage without hook plugins keeps every table empty — the no-op shape.
//
// The derived view (ticket 0092) is the redirect surface of the whole stage:
// package_root is the read-only source root the logical paths resolve
// against, derived_root is the consuming package's private derived directory
// (the only place physical outputs may land). Both are empty in the
// pre-ticket-0092 in-process callers; the extra checks below apply when they
// are set, so the production commands (which always set them) get the strict
// contract.
Prestep_Stage :: struct {
    root_dir:      string;                    // the root package dir
    member_dirs:   [..] string;               // workspace member package dirs
                                              // (the root itself excluded)
    substitutions: [..] Source_Substitution;  // append-only (root package only)
    drops:         [..] string;               // dropped package-relative paths
    generated:     [..] Generated_Source;     // registered auxiliary sources
    package_root:  string;                    // logical path base (read-only)
    derived_root:  string;                    // private derived output root
    target_root:   string;                    // the package's target/ tree
    // Whether the third-party plugin contract is enforced on this stage. The
    // generated plugin host sets it (its values are third-party code, so every
    // physical output must stay inside the consuming package's private target
    // areas); juice's own in-process build hooks leave it false, so the trusted
    // build seam keeps its established freedom (their replacements come from
    // the tool's own pre-step plugins, which the tests pin).
    enforce_private_output: bool = false;
}

// The logical package-relative path is usable when it is non-empty, relative,
// "/"-separated, free of "."/".." segments and ends in ".jai" when required.
// The check is self-contained (the published plugin face does not load the
// path-safety module): reject anything that could address a file outside the
// package root instead of normalizing it, so a plugin cannot smuggle an escape
// through a spelling difference.
derived_logical_path_ok :: (path: string, require_jai: bool) -> bool {
    if path.count == 0 return false;
    if path[0] == #char "/" || path[0] == #char "\\" return false;
    if path.count > 1 && path[1] == #char ":" return false;   // drive letter
    if find_index_from_left(path, "\\") >= 0 return false;    // "/" only
    if ends_with(path, "/") return false;
    if require_jai && !ends_with(path, ".jai") return false;
    start := 0;
    while start <= path.count {
        slash := find_index_from_left(slice(path, start, path.count - start), "/");
        end := ifx slash >= 0 then start + slash else path.count;
        segment := slice(path, start, end - start);
        if segment.count == 0 return false;
        if segment == "." || segment == ".." return false;
        if slash < 0 break;
        start = end + 1;
    }
    return true;
}

// Whether a physical path is inside the private derived root ("" = the root is
// not set, so the containment check is inert — the pre-ticket-0092 caller
// shape). Both sides are compared with "/" separators.
derived_path_within_root :: (derived_root: string, candidate: string) -> bool {
    if derived_root.count == 0 return true;
    root := path_slashes_local(derived_root);
    while root.count > 0 && root[root.count - 1] == #char "/" root.count -= 1;
    path := path_slashes_local(candidate);
    // Dot segments are resolved before the comparison, so `<derived>/../..` is
    // never "inside" by string luck: the candidate is first reduced to the path
    // the filesystem would actually open.
    reduced, reduced_ok := derived_collapse_dot_segments(path);
    if !reduced_ok return false;
    path = reduced;
    if path.count <= root.count + 1 return false;
    if !starts_with_local(path, root) return false;
    if path[root.count] != #char "/" return false;
    // A component that is a link can move the real file anywhere, so a path with
    // a linked component below the root is not trusted. The root itself may live
    // under links (the caller chose it); only the part below it must be plain.
    below := slice(path, root.count + 1, path.count - root.count - 1);
    return derived_relative_chain_is_link_free(root, below);
}

// Reduce "." and ".." segments lexically. ".." past the first segment is LOST
// (an absolute path cannot climb above its root), so an escape attempt collapses
// to a path outside the derived root instead of resolving to it.
derived_collapse_dot_segments :: (path: string) -> (string, bool) {
    if path.count == 0 return "", false;
    absolute := path[0] == #char "/";
    segments: [..] string;
    start := 0;
    for i: 0..path.count {
        is_separator := i == path.count || path[i] == #char "/";
        if !is_separator continue;
        segment := slice(path, start, i - start);
        start = i + 1;
        if segment == "" || segment == "." continue;
        if segment == ".." {
            if segments.count == 0 {
                if absolute return "", false;
                return "", false;
            }
            segments.count -= 1;
            continue;
        }
        array_add(*segments, segment);
    }
    builder: String_Builder;
    if absolute append(*builder, #char "/");
    for segment, index: segments {
        if index > 0 append(*builder, #char "/");
        append(*builder, segment);
    }
    return builder_to_string(*builder), true;
}

// Every component of one relative path below the root must be a real directory
// or a real file, never a link or a junction (decision 8: the physical identity
// is checked, not just the spelling). The probe stays inside the published
// face's own closure: one non-recursive directory listing per component, read
// through File_Utilities, instead of the tool-internal path module.
derived_relative_chain_is_link_free :: (root: string, relative: string) -> bool {
    builder: String_Builder;
    append(*builder, root);
    start := 0;
    for i: 0..relative.count {
        is_separator := i == relative.count || relative[i] == #char "/";
        if !is_separator continue;
        segment := slice(relative, start, i - start);
        start = i + 1;
        if segment == "" continue;
        parent := builder_to_string(*builder);
        if derived_entry_is_link(parent, segment) return false;
        append(*builder, #char "/");
        append(*builder, segment);
    }
    return true;
}

// Whether `directory/name` is a symbolic link or a Windows junction. A missing
// entry is not a link (the caller creates it); a listing failure is treated as
// a link so an unreadable parent can never be trusted.
derived_entry_is_link :: (directory: string, name: string) -> bool {
    Probe :: struct {
        name:      string;
        found:     bool;
        is_link:   bool;
        any_entry: bool;
    }
    probe: Probe;
    probe.name = name;
    visitor :: (info: *File_Visit_Info, probe: *Probe) {
        probe.any_entry = true;
        if info.short_name != probe.name return;
        probe.found = true;
        if info.is_symlink probe.is_link = true;
    }
    visit_files(directory, false, *probe, visitor, visit_files = true, visit_directories = true, visit_symlinks = true, follow_directory_symlinks = false);
    if probe.found return probe.is_link;
    return false;
}

// "/"-normalization and prefix test for the published face's self-contained
// path checks (the path_safety module is not part of the plugin face closure).
path_slashes_local :: (path: string) -> string {
    out: [..] u8;
    for i: 0..path.count-1 {
        c := path[i];
        array_add(*out, ifx c == #char "\\" then #char "/" else c);
    }
    if out.count == 0 return "";
    return to_string(out.data, out.count);
}

starts_with_local :: (path: string, prefix: string) -> bool {
    if prefix.count > path.count return false;
    for i: 0..prefix.count-1 {
        if path[i] != prefix[i] return false;
    }
    return true;
}

// The physical derived landing path of one logical path: the private root plus
// the logical relative path. Returns "" when the logical path is unusable, so a
// caller can never build an escaping target from an unchecked string.
derived_physical_path :: (derived_root: string, logical_path: string) -> string {
    if derived_root.count == 0 return "";
    if !derived_logical_path_ok(logical_path, false) return "";
    root := path_slashes_local(derived_root);
    while root.count > 0 && root[root.count - 1] == #char "/" root.count -= 1;
    return tprint("%1/%2", root, logical_path);
}

// Whether the package already has a retained source at this logical path (the
// file the derived view would shadow). An empty package_root means the check is
// inert (the pre-ticket-0092 caller shape).
derived_covers_retained_source :: (stage: *Prestep_Stage, logical_path: string) -> bool {
    if stage.package_root.count == 0 return false;
    root := path_slashes_local(stage.package_root);
    while root.count > 0 && root[root.count - 1] == #char "/" root.count -= 1;
    return file_exists(tprint("%1/%2", root, logical_path));
}

// Add one substitution row to the stage (spec §6.2 stage-level rules):
// - the same original with the same replacement is a no-op (stacked hooks
//   re-adding an identical row never fail);
// - the same original with a different replacement is a stage failure — the
//   table cannot answer which replacement wins;
// - an original already in the drop set is a stage failure — a file cannot
//   be both replaced and excluded;
// - a substitution of a logical path that is not a normal package-relative
//   ".jai" path is a failure (spec 0087 decision 24: the logical path stays
//   the package's own path, so an absolute path or an escape is rejected);
// - with the derived view active (package_root/derived_root set) the original
//   must be a retained package source (substitute maps an EXISTING logical
//   input, it never invents one) and the replacement must live inside the
//   package's private derived root — the source tree and any shared checkout
//   stay read-only;
// - a logical path already registered as an auxiliary source is a conflict.
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
        // Decision 24: a repeated substitution for one logical input fails, even
        // when the two rows agree on the replacement — the second registration
        // cannot know what the first one already wrote.
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("duplicate source substitution: %", original)});
        return false;
    }
    for dropped: stage.drops {
        if dropped != original continue;
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("source substitution conflicts with a drop: %", original)});
        return false;
    }
    for generated: stage.generated {
        if generated.logical_path != original continue;
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("source substitution conflicts with an auxiliary source: %", original)});
        return false;
    }
    if !derived_logical_path_ok(original, true) {
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("substitution original is not a package-relative source path: %", original)});
        return false;
    }
    if stage.package_root.count > 0 && !derived_covers_retained_source(stage, original) {
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("substitution original is not a retained package source: %", original)});
        return false;
    }
    if stage.enforce_private_output && stage.derived_root.count > 0 {
        // Spec 0087 decision 24: every physical output of a third-party plugin
        // lands inside the consuming package's private target areas — its
        // derived root, or a plugin-owned area under the same package's
        // target/ tree. The package sources and any shared checkout are never
        // writable, so a path outside both is the read-only violation.
        inside_derived := derived_path_within_root(stage.derived_root, replacement);
        inside_target := stage.target_root.count > 0 && derived_path_within_root(stage.target_root, replacement);
        if !inside_derived && !inside_target {
            array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("substitution replacement is outside the package's private derived area: %", replacement)});
            return false;
        }
    }
    array_add(*stage.substitutions, .{original = original, replacement = replacement});
    return true;
}

// Add one dropped package-relative path to the stage: a repeated drop is a
// no-op; a path already in the substitution table is a stage failure (the
// same rule as the reverse order in prestep_add_substitution); a logical path
// registered as an auxiliary source is a conflict (an input cannot be excluded
// and re-introduced under the same logical path). With the derived view
// active the path must be a package-relative "".jai" input (a declared drop
// only ever names a compilable input). Failures record an ERROR diagnostic and
// return false.
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
    for generated: stage.generated {
        if generated.logical_path != original continue;
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("drop conflicts with an auxiliary source: %", original)});
        return false;
    }
    array_add(*stage.drops, original);
    return true;
}

// Write a source text into the private derived area at a logical path and
// return the physical landing path ("" + false = a plugin error). The view owns
// the path: the logical path is validated and only ever composed onto the
// private derived root, so a plugin cannot write into the package sources, a
// shared Git checkout or anywhere else (spec 0087 decision 24: 源与共享检出只读,
// 物理输出限于消费工程私有派生区). The parents are created on demand; a creation
// or write failure is a plugin error.
prestep_write_derived :: (ctx: *Lifecycle_Context, logical_path: string, contents: string) -> (string, bool) {
    if ctx.prestep == null {
        array_add(ctx.diagnostics, .{level = .ERROR, message = "derived write without prestep state"});
        return "", false;
    }
    stage := cast(*Prestep_Stage) ctx.prestep;
    if stage.derived_root.count == 0 {
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("no private derived area for the derived source: %", logical_path)});
        return "", false;
    }
    if !derived_logical_path_ok(logical_path, true) {
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("derived source path is not a package-relative .jai path: %", logical_path)});
        return "", false;
    }
    physical := derived_physical_path(stage.derived_root, logical_path);
    if physical == "" || !derived_path_within_root(stage.derived_root, physical) {
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("could not derive a private landing path for: %", logical_path)});
        return "", false;
    }
    last_slash := -1;
    for i: 0..physical.count-1 {
        if physical[i] == #char "/" last_slash = i;
    }
    if last_slash > 0 {
        parent := slice(physical, 0, last_slash);
        if !make_directory_if_it_does_not_exist(parent, recursive = true) {
            array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("could not create the private derived directory: %", parent)});
            return "", false;
        }
    }
    if !write_entire_file(physical, contents) {
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("could not write the derived source: %", physical)});
        return "", false;
    }
    return physical, true;
}

// Register one auxiliary Jai source (spec 0087 decision 24's explicit
// `generated` channel): the plugin supplies the logical package-relative path
// and the source text, the view owns the physical landing path under the
// package's private derived root. Rules — each failure records an ERROR
// diagnostic and returns false, nothing is overwritten by order:
// - the logical path must be a normal package-relative ".jai" path and the
//   derived view must be active (no private area = plugin error);
// - the same logical path registered twice is a conflict, even with identical
//   text (two plugins must not silently agree on one output);
// - a logical path that is already a retained package source is a conflict —
//   an auxiliary file never shadows the package's own content and never turns
//   itself into a public entry (changing an existing input is what substitute
//   is for);
// - a logical path that is substituted or dropped is a conflict (the same
//   input would have two providers).
prestep_add_generated :: (ctx: *Lifecycle_Context, logical_path: string, contents: string) -> bool {
    if ctx.prestep == null {
        array_add(ctx.diagnostics, .{level = .ERROR, message = "derived source registration without prestep state"});
        return false;
    }
    stage := cast(*Prestep_Stage) ctx.prestep;
    if stage.derived_root.count == 0 {
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("no private derived area for the auxiliary source: %", logical_path)});
        return false;
    }
    if !derived_logical_path_ok(logical_path, true) {
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("auxiliary source path is not a package-relative .jai path: %", logical_path)});
        return false;
    }
    for generated: stage.generated {
        if generated.logical_path != logical_path continue;
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("duplicate auxiliary source path: %", logical_path)});
        return false;
    }
    if derived_covers_retained_source(stage, logical_path) {
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("auxiliary source would cover a retained package source: %", logical_path)});
        return false;
    }
    for s: stage.substitutions {
        if s.original != logical_path continue;
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("auxiliary source conflicts with a source substitution: %", logical_path)});
        return false;
    }
    for dropped: stage.drops {
        if dropped != logical_path continue;
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("auxiliary source conflicts with a drop: %", logical_path)});
        return false;
    }
    physical, written := prestep_write_derived(ctx, logical_path, contents);
    if !written return false;
    array_add(*stage.generated, .{logical_path = logical_path, physical_path = physical});
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

// Register an auxiliary source that was ALREADY materialized (the PRESTEP
// host writes its own derived files and reports them): the same validation as
// prestep_add_generated applies, but no write is queued. The reported physical
// path must be inside the package's private derived area — a plugin that
// reports a file elsewhere is the read-only violation (spec 0087 decision 24:
// 源与共享检出只读).
prestep_register_generated :: (ctx: *Lifecycle_Context, logical_path: string, physical_path: string) -> bool {
    if ctx.prestep == null {
        array_add(ctx.diagnostics, .{level = .ERROR, message = "derived source registration without prestep state"});
        return false;
    }
    stage := cast(*Prestep_Stage) ctx.prestep;
    if stage.derived_root.count == 0 {
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("no private derived area for the auxiliary source: %", logical_path)});
        return false;
    }
    if !derived_logical_path_ok(logical_path, true) {
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("auxiliary source path is not a package-relative .jai path: %", logical_path)});
        return false;
    }
    if !derived_path_within_root(stage.derived_root, physical_path) {
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("auxiliary source is outside the package's private derived area: %", physical_path)});
        return false;
    }
    for generated: stage.generated {
        if generated.logical_path != logical_path continue;
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("duplicate auxiliary source path: %", logical_path)});
        return false;
    }
    if derived_covers_retained_source(stage, logical_path) {
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("auxiliary source would cover a retained package source: %", logical_path)});
        return false;
    }
    for s: stage.substitutions {
        if s.original != logical_path continue;
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("auxiliary source conflicts with a source substitution: %", logical_path)});
        return false;
    }
    for dropped: stage.drops {
        if dropped != logical_path continue;
        array_add(ctx.diagnostics, .{level = .ERROR, message = tprint("auxiliary source conflicts with a drop: %", logical_path)});
        return false;
    }
    array_add(*stage.generated, .{logical_path = logical_path, physical_path = physical_path});
    return true;
}

// The physical file registered as an auxiliary source at this logical path;
// ("", false) when nothing was registered THIS round. Only the current
// registrations answer — the derived directory is never scanned, so a file an
// earlier run left behind can never be consumed (spec 0087 decision 24).
prestep_generated_for :: (stage: *Prestep_Stage, logical_path: string) -> (string, bool) {
    if stage == null return "", false;
    for generated: stage.generated {
        if generated.logical_path == logical_path return generated.physical_path, true;
    }
    return "", false;
}

// The physical source a compile input must be read from: the substitution's
// replacement first, then this round's auxiliary registration, else the
// original path itself ("", false = read the package's own file).
prestep_derived_source_for :: (stage: *Prestep_Stage, logical_path: string) -> (string, bool) {
    replacement, substituted := prestep_substitution_for(stage, logical_path);
    if substituted return replacement, true;
    physical, generated := prestep_generated_for(stage, logical_path);
    if generated return physical, true;
    return "", false;
}

// Whether any file of the closure is a derived input of THIS round.
prestep_closure_is_derived :: (stage: *Prestep_Stage, closure_paths: [] string) -> bool {
    if stage == null return false;
    for path: closure_paths {
        _, derived := prestep_derived_source_for(stage, path);
        if derived return true;
    }
    return false;
}

// Materialize one closure's derived inputs into the private derived root at their
// OWN logical paths, so a verbatim (test-free) compile reads the derived text and
// every relative `#load` beside it still resolves. Returns the derived entry path,
// or "" when nothing in the closure is derived (the caller then compiles the
// package's own entry, byte-for-byte as before).
//
// This is what makes one substitution anywhere in the closure reach the compile:
// the closure is the logical input graph of the run, not just its entry.
prestep_materialize_closure :: (
    stage: *Prestep_Stage,
    entry_logical: string,
    closure_paths: [] string,
    read_text: #type (state: *void, logical_path: string) -> (string, bool),
    read_state: *void
) -> (string, string, bool) {
    // (derived entry path, error message, ok). The second result is "" unless the
    // materialization failed; the caller reports it through its own stage sink, so
    // this procedure stays usable from the command front and from the host.
    if stage == null return "", "", true;
    if !prestep_closure_is_derived(stage, closure_paths) return "", "", true;
    // A derived input with no private root to land in is a contradiction, not a
    // reason to compile the original source: the pre-step said this input's
    // content is replaced, and silently ignoring that would ship the wrong build
    // (the 0098 review's "substitution must reach the whole closure" rule).
    if stage.derived_root.count == 0 {
        return "", "the pre-step registered a derived input but no private derived root exists", false;
    }
    for path: closure_paths {
        text, read_ok := read_text(read_state, path);
        if !read_ok return "", tprint("could not read the closure input: %", path), false;
        physical := derived_physical_path(stage.derived_root, path);
        if physical == "" || !derived_path_within_root(stage.derived_root, physical) {
            return "", tprint("could not derive a private landing path for: %", path), false;
        }
        last_slash := -1;
        for i: 0..physical.count-1 {
            if physical[i] == #char "/" last_slash = i;
        }
        if last_slash > 0 {
            parent := slice(physical, 0, last_slash);
            if !make_directory_if_it_does_not_exist(parent, recursive = true) {
                return "", tprint("could not create the private derived directory: %", parent), false;
            }
        }
        if !write_entire_file(physical, text) {
            return "", tprint("could not write the derived closure input: %", physical), false;
        }
    }
    entry_physical := derived_physical_path(stage.derived_root, entry_logical);
    if entry_physical == "" return "", tprint("could not derive the entry path: %", entry_logical), false;
    return entry_physical, "", true;
}

// The derived-source probe as a plain procedure over an explicit stage, so a
// caller can pass it to a closure probe (Jai has no closures, so the stage
// travels as the argument instead of being captured).
prestep_derived_probe :: (stage: *Prestep_Stage, logical_path: string) -> (string, bool) {
    replacement, derived := prestep_derived_source_for(stage, logical_path);
    if !derived return "", false;
    return replacement, true;
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
