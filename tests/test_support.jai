// ---------------------------------------------------------------------------
// Test support: the one allowed home for test-program shared declarations
// (the old juice discipline — shared test declarations live only in this
// file; other files keep no test-only declarations at top level). This file
// is not #loaded by src/main.jai, so it stays outside the Build entry
// closure and never reaches the release product. On the test program path
// it is test-free: Test discovery's full-package scan compiles it together
// with the other tests/, so its declarations are program-level shared.
// ---------------------------------------------------------------------------

#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";

// ---------------------------------------------------------------------------
// Path base: the package root every fixture and scratch path derives from.
// The test program executes at compile time in the jai compiler child,
// where the process working directory is the entry file's directory
// (target/transpile), not the invocation cwd. The generated test driver
// declares JUICE_TEST_PACKAGE_ROOT as the absolute package root (C4); the
// test program's intermediate path is target/build/ (C5), so deriving the
// root from Build_Options.intermediate_path no longer works.
// ---------------------------------------------------------------------------
otter_root :: () -> string {
    return JUICE_TEST_PACKAGE_ROOT;
}

// The otter package's target directory and a scratch root under it: tests
// cross the same Target_Layout interface as the production consumers (the
// literal layout is pinned once, in tests/target_layout_tests.jai).
otter_target_dir :: () -> string {
    return package_target_dir(otter_root());
}

otter_scratch :: (name: string) -> string {
    return target_scratch_dir(otter_target_dir(), name);
}

// A crash-recovery backup path under target/recovery — the zone the test
// command never prunes (park_source_file/restore_source_file below).
otter_recovery_path :: (file_name: string) -> string {
    return tprint("%1/%2", target_recovery_dir(otter_target_dir()), file_name);
}

// ---------------------------------------------------------------------------
// Testing-face self-test state (ticket 030) moved into src/module.jai's
// testing section: the published Testing module must be self-contained
// standard Jai, so the self_testing_failures accumulator and the g_self_*
// globals it drives live beside the @test procedures that use them. This
// file keeps no declarations for them (they were only ever consumed by the
// module's self tests).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Recording fake for the manifest evaluator spawn seam: exit_codes are
// returned in call order (exhausted -> 0); when data_output is non-empty
// the fake writes it to the evaluator's output file before returning
// (simulating a successful child), which lets loader tests drive the retry
// loop and the post-spawn parse deterministically — a real child's write
// failure cannot be forced on demand.
// ---------------------------------------------------------------------------
Eval_Spawn_Recorder :: struct {
    calls:           int;
    exit_codes:      [] s32;
    data_output:     string;
    last_eval_src:   string;
    last_eval_out:   string;
    last_modules_dir: string;
}

EVAL_SPAWN: Eval_Spawn_Recorder;

reset_eval_spawn :: () {
    EVAL_SPAWN = .{};
}

test_eval_spawn :: (eval_src: string, eval_out: string, modules_dir: string) -> s32 {
    EVAL_SPAWN.calls += 1;
    EVAL_SPAWN.last_eval_src = eval_src;
    EVAL_SPAWN.last_eval_out = eval_out;
    EVAL_SPAWN.last_modules_dir = modules_dir;
    if EVAL_SPAWN.data_output != "" {
        write_entire_file(eval_out, EVAL_SPAWN.data_output);
    }
    index := EVAL_SPAWN.calls - 1;
    if index >= EVAL_SPAWN.exit_codes.count return 0;
    return EVAL_SPAWN.exit_codes[index];
}

// ---------------------------------------------------------------------------
// CLI E2E support: the real otter executable (built by `jai build.jai` into
// otter/target/juice.exe — the E2E tests spawn it, so the build must run
// before the test command; the verification loop always rebuilds first).
//
// The production modules derivation (spec section 9.3: <exe>/modules, next
// to the running executable) resolves to target/modules during the
// bootstrap window. Ticket 032's publish step retired the seeds: this
// helper publishes the three module artifacts through the production
// generators (the same transform build.jai runs) and retires a stale flat
// Juice.jai seed (the directory module takes over — no flat/directory
// ambiguity at the modules dir, 005 US 14). Ticket 037 adds the fourth
// publication: the verbatim copy of src/test_discovery.jai under
// juice_internal/ (the generated test metaprogram #loads it by absolute
// path — the published artifact the installed layout carries). Ticket 049
// adds the plugin face closure copies: the four JUICE_CORE_LOAD_FILES
// sources land verbatim under juice_internal/plugin_face/, so the published
// juice_core's module-relative #load lines resolve in the relocated modules
// tree the consumers see. Session artifacts under target/ — regenerated
// every run, so the real exe's manifest evaluator children resolve `#import
// "Juice"` and the generated test programs resolve `#import "Testing"`
// against the published faces. Every source is read before any write (a
// missing source publishes nothing), matching the build metaprogram's
// failure ordering.
// ---------------------------------------------------------------------------
otter_exe :: () -> string {
    return target_artifact_path(otter_target_dir(), "juice");
}

ensure_published_modules :: () -> bool {
    target_dir := otter_target_dir();
    modules_dir := target_modules_dir(target_dir);
    source, read_ok := read_entire_file(tprint("%1/src/module.jai", otter_root()));
    if !read_ok return false;
    discovery_source, discovery_read_ok := read_entire_file(tprint("%1/src/test_discovery.jai", otter_root()));
    if !discovery_read_ok return false;
    // The plugin face closure sources join the same pre-write batch (ticket
    // 049): the copies are verbatim, so reading and writing the strings is
    // the whole publication.
    closure_sources: [..] string;
    for file: JUICE_CORE_LOAD_FILES {
        closure_source, closure_read_ok := read_entire_file(tprint("%1/src/%2", otter_root(), file));
        if !closure_read_ok return false;
        array_add(*closure_sources, closure_source);
    }
    if !make_directory_if_it_does_not_exist(juice_module_dir(target_dir), recursive = true) return false;
    juice_text, juice_ok := publish_juice_module(source);
    if !juice_ok return false;
    testing_text, testing_ok := publish_testing_module(source);
    if !testing_ok return false;
    core_text, core_ok := publish_juice_core(source);
    if !core_ok return false;
    if !make_directory_if_it_does_not_exist(juice_internal_dir(modules_dir), recursive = true) return false;
    if !make_directory_if_it_does_not_exist(juice_plugin_face_dir(modules_dir), recursive = true) return false;
    if !write_entire_file(juice_module_path(target_dir), juice_text) return false;
    if !write_entire_file(testing_module_path(target_dir), testing_text) return false;
    if !write_entire_file(juice_core_module_path(target_dir), core_text) return false;
    if !write_entire_file(test_discovery_module_path(modules_dir), discovery_source) return false;
    for file, index: JUICE_CORE_LOAD_FILES {
        if !write_entire_file(juice_plugin_face_file_path(modules_dir, file), closure_sources[index]) return false;
    }
    flat_seed := tprint("%1/Juice.jai", target_modules_dir(target_dir));
    if file_exists(flat_seed) {
        if !file_delete(flat_seed) return false;
    }
    return true;
}

run_otter_child :: (arguments: [] string) -> (Process_Result, string, string) {
    result, output, errors := run_otter_child_at(otter_root(), arguments);
    return result, output, errors;
}

// The E2E fixture spawn: the real otter executable run with the given
// working directory (a fixture package root or a scratch directory). The
// published module faces land first so manifest evaluation resolves the
// Juice module face through the production <exe>/modules derivation.
run_otter_child_at :: (working_dir: string, arguments: [] string) -> (Process_Result, string, string) {
    ensure_published_modules();
    exe := otter_exe();
    args: [..] string;
    array_add(*args, exe);
    for argument: arguments array_add(*args, argument);
    result, output, errors, _ := run_command(..args, working_directory = working_dir, capture_and_return_output = true);
    return result, output, errors;
}

expect_exit :: (name: string, result: Process_Result, want: s32, tag := "child") -> bool {
    if result.type == .EXITED && result.exit_code == want return true;
    print("[%1 %2] exit result %3/%4, want %5\n", tag, name, result.type, result.exit_code, want);
    return false;
}

// Normalize CRLF to LF so expected blocks compare line by line regardless
// of the child process's native line endings.
normalize_crlf :: (s: string) -> string {
    has_cr := false;
    for ch: s {
        if ch == #char "\r" {
            has_cr = true;
            break;
        }
    }
    if !has_cr return s;
    builder: String_Builder;
    cursor := 0;
    i := 0;
    while i < s.count {
        if s[i] == #char "\r" {
            print_to_builder(*builder, "%", slice(s, cursor, i - cursor));
            print_to_builder(*builder, "\n");
            if i + 1 < s.count && s[i+1] == #char "\n" i += 1;
            cursor = i + 1;
        }
        i += 1;
    }
    if cursor < s.count print_to_builder(*builder, "%", slice(s, cursor, s.count - cursor));
    return builder_to_string(*builder);
}

// Output assertion: checks each needle's presence/absence (want).
output_matches :: (name: string, output: string, needles: [] string, want := true, tag := "child") -> bool {
    normalized := normalize_crlf(output);
    for needle: needles {
        found := find_index_from_left(normalized, needle) >= 0;
        if found != want {
            print("[%1 %2] output %3 '%4'\n", tag, name, ifx found then "unexpectedly contains" else "missing", needle);
            print("  output was:\n%\n", output);
            return false;
        }
    }
    return true;
}

// Full-text equality assertion (CRLF-normalized) — the help output contract
// locks the rendered text byte for byte.
child_output_equals :: (name: string, output: string, want: string, tag := "child") -> bool {
    normalized := normalize_crlf(output);
    if normalized == want return true;
    print("[%1 %2] output mismatch, want:\n%3\n  got:\n%4\n", tag, name, want, normalized);
    return false;
}

// Substring assertion (CRLF-normalized) — discovery error lines are locked
// byte for byte without pinning the child's surrounding noise.
child_output_contains :: (name: string, output: string, needle: string, tag := "child") -> bool {
    normalized := normalize_crlf(output);
    if find_index_from_left(normalized, needle) >= 0 return true;
    print("[%1 %2] output missing '%3'\n  output was:\n%4\n", tag, name, needle, output);
    return false;
}

// ---------------------------------------------------------------------------
// Dispatcher test support: the recording handlers and the test registries
// (the old juice dispatch test semantics). Each handler also records the
// arguments it received, which pins the "prerequisites always receive empty
// arguments" contract.
// ---------------------------------------------------------------------------
test_a_calls: s64 = 0;
test_b_calls: s64 = 0;
test_c_calls: s64 = 0;
test_d_calls: s64 = 0;
test_fail_calls: s64 = 0;

test_a_arguments: [..] string;
test_b_arguments: [..] string;
test_c_arguments: [..] string;
test_d_arguments: [..] string;

record_test_arguments :: (recorded: *[..] string, arguments: [] string) {
    array_reset(recorded);
    for argument: arguments array_add(recorded, argument);
}

reset_dispatch_counters :: () {
    test_a_calls = 0;
    test_b_calls = 0;
    test_c_calls = 0;
    test_d_calls = 0;
    test_fail_calls = 0;
    array_reset(*test_a_arguments);
    array_reset(*test_b_arguments);
    array_reset(*test_c_arguments);
    array_reset(*test_d_arguments);
}

test_handler_a :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_a_calls += 1;
    record_test_arguments(*test_a_arguments, arguments);
    return true;
}

test_handler_b :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_b_calls += 1;
    record_test_arguments(*test_b_arguments, arguments);
    return true;
}

test_handler_c :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_c_calls += 1;
    record_test_arguments(*test_c_arguments, arguments);
    return true;
}

test_handler_d :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_d_calls += 1;
    record_test_arguments(*test_d_arguments, arguments);
    return true;
}

test_handler_fail :: (ctx: *Command_Context, arguments: [] string) -> bool {
    test_fail_calls += 1;
    return false;
}

strict_arguments_are_invalid :: (arguments: [] string) -> bool {
    return false;
}

test_arguments_accept_all :: (arguments: [] string) -> bool {
    return true;
}

TEST_REGISTRY_SIMPLE :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], handler = test_handler_a},
    .{name = "b", description = "Command B", usage = "test b", prerequisites = string.[], handler = test_handler_b},
];

TEST_REGISTRY_DUPLICATE :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], handler = test_handler_a},
    .{name = "a", description = "Command A Duplicate", usage = "test a", prerequisites = string.[], handler = test_handler_b},
];

TEST_REGISTRY_MISSING_PREREQ :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.["nonexistent"], handler = test_handler_a},
];

TEST_REGISTRY_INVALID_NAME :: Command.[
    .{name = "", description = "Nameless Command", usage = "test", prerequisites = string.[], handler = test_handler_a},
];

TEST_REGISTRY_INVALID_HANDLER :: Command.[
    .{name = "a", description = "Null Handler Command", usage = "test a", prerequisites = string.[], handler = null},
];

TEST_REGISTRY_CYCLE :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.["b"], handler = test_handler_a},
    .{name = "b", description = "Command B", usage = "test b", prerequisites = string.["a"], handler = test_handler_b},
];

TEST_REGISTRY_DIAMOND :: Command.[
    .{name = "a", description = "Command A", usage = "test a", prerequisites = string.[], handler = test_handler_a},
    .{name = "b", description = "Command B", usage = "test b", prerequisites = string.["a"], handler = test_handler_b},
    .{name = "c", description = "Command C", usage = "test c", prerequisites = string.["a"], handler = test_handler_c},
    .{name = "d", description = "Command D", usage = "test d", prerequisites = string.["b", "c"], validate_arguments = test_arguments_accept_all, handler = test_handler_d},
];

TEST_REGISTRY_FAILURE :: Command.[
    .{name = "failing", description = "Failing Command", usage = "test failing", prerequisites = string.[], handler = test_handler_fail},
    .{name = "target", description = "Target Command", usage = "test target", prerequisites = string.["failing"], handler = test_handler_b},
];

TEST_REGISTRY_ARGUMENTS :: Command.[
    .{name = "sideeffect", description = "Side Effect Command", usage = "test sideeffect", prerequisites = string.[], handler = test_handler_a},
    .{name = "strict", description = "Strict Command", usage = "test strict", prerequisites = string.["sideeffect"], validate_arguments = strict_arguments_are_invalid, handler = test_handler_b},
];

// ---------------------------------------------------------------------------
// Record-value encoder for the host-protocol tests (moved out of
// src/manifest.jai by the 2026-10-22 architecture review: production only
// decodes records; the encoder is the tests' inverse for building expected
// record text — the host and the manifest evaluator ship their own generated
// encoders). Only the delimiter, the escape character and line breaks are
// encoded (% | CR LF).
// ---------------------------------------------------------------------------
record_escape_hex_digit :: (n: u8) -> u8 {
    return cast(u8) ifx n < 10 then #char "0" + n else #char "a" + (n - 10);
}

escape_record_value :: (value: string) -> string {
    out: [..] u8;
    for i: 0..value.count-1 {
        c := value[i];
        if c == #char "%" || c == #char "|" || c == #char "\n" || c == #char "\r" {
            array_add(*out, #char "%");
            array_add(*out, record_escape_hex_digit(cast(u8) ((c >> 4) & 0xf)));
            array_add(*out, record_escape_hex_digit(cast(u8) (c & 0xf)));
        } else {
            array_add(*out, c);
        }
    }
    if out.count == 0 return "";
    return copy_string(to_string(out.data, out.count));
}

// ---------------------------------------------------------------------------
// Workspace test support: the recording fakes for the three state machine
// seams (the old juice test_fake_discover/test_fake_resolve/
// test_fake_prepare_dependencies semantics — the discover fake takes the
// seam's third modules_dir parameter, ticket 008's seam-injection
// convention). The fakes record attempts and snapshots so the tests pin
// idempotency, publish-on-success-only, and that preparation consumes the
// discovery snapshot (declared member packages with their declared
// dependencies).
// ---------------------------------------------------------------------------
test_discovery_attempts: s64 = 0;
test_fake_discovery_ok: bool = false;
test_fake_discovery: Juice.Workspace_Discovery;

test_fake_discover :: (root_dir: string, cache_dir: string, modules_dir: string) -> (Juice.Workspace_Discovery, bool) {
    test_discovery_attempts += 1;
    return test_fake_discovery, test_fake_discovery_ok;
}

test_plan_resolution_success: bool = false;
test_resolved_plans: [] Juice.Artifact_Plan;
test_dependency_attempts: s64 = 0;
test_dependency_ok: bool = false;
test_dependency_snapshot: [] Juice.Package;

test_fake_resolve :: (pkg: Juice.Package) -> Artifact_Plan_Result {
    if !test_plan_resolution_success return .{success = false, error_message = copy_string("resolution failure")};
    return .{success = true, plans = test_resolved_plans};
}

test_fake_prepare_dependencies :: (root_dir: string, cache_dir: string, member_packages: [] Juice.Package) -> bool {
    test_dependency_attempts += 1;
    test_dependency_snapshot = member_packages;
    return test_dependency_ok;
}

reset_preparation_test :: () {
    test_discovery_attempts = 0;
    test_fake_discovery_ok = false;
    test_fake_discovery = .{};
    test_plan_resolution_success = false;
    test_resolved_plans = Juice.Artifact_Plan.[];
    test_dependency_attempts = 0;
    test_dependency_ok = false;
    test_dependency_snapshot = Juice.Package.[];
}

// ---------------------------------------------------------------------------
// Workspace discovery E2E support: the member matrix runs through a
// generated driver program — a real jai child #loads the src closure
// (juice_module → path_safety → manifest → workspace → target →
// dependency → transpile family → target_layout, mirroring main.jai:
// workspace.jai's seam defaults reference the target/dependency productions)
// and calls discover_workspace on a fixture, mirroring the manifest
// evaluator child shape (ticket 007 precedent). The generated driver remains
// the real-child harness for the discovery error-text matrix (the build
// command, the production discovery consumer, landed with ticket 011; the
// matrix keeps its own child so it can drive invalid manifests directly) —
// it lets the matrix assert the discovery error text byte for byte (old
// juice test_monorepo semantics).
// ---------------------------------------------------------------------------
workspace_discovery_driver_code :: (fixture_root: string, cache_dir: string) -> string {
    builder: String_Builder;
    append(*builder, "#import \"Basic\";\n");
    append(*builder, "#import \"Compiler\";\n\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/juice_module.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/path_safety.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/manifest.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/workspace.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/target.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/dependency.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/transpile.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/transpile_plugin.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/transpile_cache.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/transpile_front.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/target_layout.jai", otter_root())));
    append(*builder, "\";\n\n");
    append(*builder, "#run {\n");
    append(*builder, "    set_build_options_dc(.{do_output = false});\n");
    append(*builder, "    main();\n");
    append(*builder, "}\n\n");
    append(*builder, "main :: () {\n");
    append(*builder, "    discovery, ok := discover_workspace(\"");
    append(*builder, path_slashes(fixture_root));
    append(*builder, "\", \"");
    append(*builder, path_slashes(cache_dir));
    append(*builder, "\", \"");
    append(*builder, path_slashes(plugin_face_modules_dir()));
    append(*builder, "\");\n");
    append(*builder, "    print(\"discovery-ok=%\\n\", ok);\n");
    append(*builder, "    if !ok return;\n");
    append(*builder, "    print(\"has-package=%\\n\", discovery.has_package);\n");
    append(*builder, "    print(\"root=%1 v=%2\\n\", discovery.root_package.name, discovery.root_package.version);\n");
    append(*builder, "    for dep: discovery.root_package.dependencies print(\"root-dep=%\\n\", dep.name);\n");
    append(*builder, "    for pkg: discovery.member_packages {\n");
    append(*builder, "        print(\"member=%1 deps=%2\\n\", pkg.name, pkg.dependencies.count);\n");
    append(*builder, "        for dep: pkg.dependencies print(\"member-dep=%1:%2\\n\", pkg.name, dep.name);\n");
    append(*builder, "    }\n");
    append(*builder, "}\n");
    return builder_to_string(*builder);
}

run_workspace_discovery_child :: (fixture_name: string) -> (Process_Result, string, string) {
    ensure_published_modules();
    fixture_root := path_slashes(tprint("%1/tests/data/%2", otter_root(), fixture_name));
    cache := path_slashes(otter_scratch(tprint("workspace-e2e-cache/%1", fixture_name)));
    driver := tprint("%1/driver.jai", cache);
    make_directory_if_it_does_not_exist(cache, recursive = true);
    write_entire_file(driver, workspace_discovery_driver_code(fixture_root, cache));
    result, output, errors, _ := run_command("jai", driver, "-import_dir", plugin_face_modules_dir(), "-quiet", working_directory = otter_root(), capture_and_return_output = true);
    return result, output, errors;
}

// ---------------------------------------------------------------------------
// Target test support: the LIB fixture package construction (old juice
// library_fixture_package semantics — a declared-LIB package pointing at the
// root module.jai layout fixture).
// ---------------------------------------------------------------------------
library_fixture_package :: () -> Juice.Package {
    pkg: Juice.Package;
    pkg.name    = "libdemo";
    pkg.version = "1";
    pkg.dir     = tprint("%1/tests/data/target-lib-module", otter_root());
    pkg.type    = .LIB;
    return pkg;
}

// ---------------------------------------------------------------------------
// Dependency test support: the fetch/link recording fakes for
// fetch_workspace_dependencies (old juice test_fake_fetch/
// test_fake_link_member semantics) and the shim content reader.
// ---------------------------------------------------------------------------
test_fetched_dependency_names: [..] string;
test_linked_member_names: [..] string;
test_fetch_result: bool = false;
test_link_result: bool = false;

test_fake_fetch :: (root_dir: string, cache_dir: string, dep: Juice.Dependency) -> bool {
    array_add(*test_fetched_dependency_names, copy_string(dep.name));
    return test_fetch_result;
}

test_fake_link_member :: (root_dir: string, member: Juice.Package) -> bool {
    array_add(*test_linked_member_names, copy_string(member.name));
    return test_link_result;
}

reset_dependency_recording :: () {
    array_reset(*test_fetched_dependency_names);
    array_reset(*test_linked_member_names);
    test_fetch_result = false;
    test_link_result = false;
}

shim_content_for :: (packages_dir: string, name: string) -> string, bool {
    shim_path := tprint("%1/%2.jai", packages_dir, name);
    if !file_exists(shim_path) return "", false;
    content, ok := read_entire_file(shim_path);
    return content, ok;
}

// ---------------------------------------------------------------------------
// Dependency preparation E2E support: the generated driver child discovers a
// fixture workspace through real jai evaluator children, then runs the real
// dependency preparation against a scratch root (shims land in the scratch
// tree, never in the fixture) and one relative-source fetch. The driver
// first sets its working directory to the otter root — production juice
// anchors relative DEP sources at its process cwd (the package root; it
// never chdirs), and the jai child anchors at the entry file's directory by
// default, so the stand-in sets the same anchor explicitly. The
// workspace-ok fixture carries both member layouts (member_lib:
// src/module.jai, member_extra: module.jai) and the member-to-member DEP
// declaration with a member-relative source that member linking ignores.
// ---------------------------------------------------------------------------
dependency_prep_driver_code :: (fixture_root: string, scratch_root: string, cache_dir: string) -> string {
    builder: String_Builder;
    append(*builder, "#import \"Basic\";\n");
    append(*builder, "#import \"Compiler\";\n\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/juice_module.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/path_safety.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/manifest.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/workspace.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/target.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/dependency.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/transpile.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/transpile_plugin.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/transpile_cache.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/transpile_front.jai", otter_root())));
    append(*builder, "\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(tprint("%1/src/target_layout.jai", otter_root())));
    append(*builder, "\";\n\n");
    append(*builder, "#run {\n");
    append(*builder, "    set_build_options_dc(.{do_output = false});\n");
    append(*builder, "    main();\n");
    append(*builder, "}\n\n");
    append(*builder, "main :: () {\n");
    append(*builder, "    // The jai child anchors relative paths at the entry file's\n");
    append(*builder, "    // directory; production juice anchors at its process cwd (the\n");
    append(*builder, "    // package root — it never chdirs), so the stand-in sets the\n");
    append(*builder, "    // same anchor explicitly.\n");
    append(*builder, "    set_working_directory(\"");
    append(*builder, path_slashes(otter_root()));
    append(*builder, "\");\n");
    append(*builder, "    delete_directory_full(\"");
    append(*builder, path_slashes(scratch_root));
    append(*builder, "\");\n");
    append(*builder, "    discovery, ok := discover_workspace(\"");
    append(*builder, path_slashes(fixture_root));
    append(*builder, "\", \"");
    append(*builder, path_slashes(cache_dir));
    append(*builder, "\", \"");
    append(*builder, path_slashes(plugin_face_modules_dir()));
    append(*builder, "\");\n");
    append(*builder, "    print(\"discovery-ok=%\\n\", ok);\n");
    append(*builder, "    if ok && discovery.has_package {\n");
    append(*builder, "        deps_ok := resolve_and_fetch_dependencies(\"");
    append(*builder, path_slashes(scratch_root));
    append(*builder, "\", \"");
    append(*builder, path_slashes(cache_dir));
    append(*builder, "\", discovery.member_packages);\n");
    append(*builder, "        print(\"deps-ok=%\\n\", deps_ok);\n");
    append(*builder, "    }\n");
    append(*builder, "    rel_ok := fetch_dependency(\"");
    append(*builder, path_slashes(scratch_root));
    append(*builder, "\", \"");
    append(*builder, path_slashes(cache_dir));
    append(*builder, "\", .{name = \"dep_rel\", source = \"tests/data/dep-fixture/shim-pkg\"});\n");
    append(*builder, "    print(\"rel-ok=%\\n\", rel_ok);\n");
    append(*builder, "}\n");
    return builder_to_string(*builder);
}

run_dependency_prep_child :: (fixture_name: string, scratch_root: string) -> (Process_Result, string, string) {
    ensure_published_modules();
    fixture_root := path_slashes(tprint("%1/tests/data/%2", otter_root(), fixture_name));
    cache := path_slashes(otter_scratch(tprint("dependency-e2e-cache/%1", fixture_name)));
    driver := tprint("%1/driver.jai", cache);
    make_directory_if_it_does_not_exist(cache, recursive = true);
    write_entire_file(driver, dependency_prep_driver_code(fixture_root, scratch_root, cache));
    result, output, errors, _ := run_command("jai", driver, "-import_dir", plugin_face_modules_dir(), "-quiet", working_directory = otter_root(), capture_and_return_output = true);
    return result, output, errors;
}

// ---------------------------------------------------------------------------
// Build test support: the recording fakes for the build orchestration seams
// (compile/is_running/handoff — the old juice test_compile_artifact
// semantics; the LNK1104 decision seams have no old juice counterpart, the
// fakes follow the same recording posture) and the compile child spawn fake
// for compile_artifact_plan's seam tests. build_seam_* mirror the old juice
// helpers: a real temp fixture root the revalidation gate probes over the
// real filesystem.
// ---------------------------------------------------------------------------
test_compile_count: s64;
test_compiled_plan: Juice.Artifact_Plan;
test_compiled_driver_root: string;
test_compiled_entry: string;
test_compile_success: bool;

test_compile_artifact :: (root_dir: string, plan: Juice.Artifact_Plan, entry: string) -> bool {
    test_compile_count += 1;
    test_compiled_plan = plan;
    test_compiled_driver_root = root_dir;
    test_compiled_entry = entry;
    return test_compile_success;
}

// A minimal COMPILE at recording hook (ticket 027): replaces the built-in
// compile loop so orchestration tests never spawn the real compiler (the
// built-in loop itself is tested directly through build_compile_loop's
// internal seam). Captures the COMPILE stage state the dispatch hands over
// — the entries the TRANSPILE stage chose.
test_compile_at_calls: s64;
test_compile_at_entries: [..] string;

test_compile_at_hook :: (ctx: *Lifecycle_Context, state: *void) -> bool {
    test_compile_at_calls += 1;
    stage := cast(*Build_Compile_Stage) ctx.artifact_paths;
    array_reset(*test_compile_at_entries);
    for e: stage.entries array_add(*test_compile_at_entries, copy_string(e));
    return true;
}

test_compile_at_table :: () -> [..] Hook_Registration {
    table: [..] Hook_Registration;
    register_hooks(*table, .[.{stage = .COMPILE, position = .at, hook = test_compile_at_hook}]);
    return table;
}

test_is_running_result: bool = false;
test_is_running_checked: [..] string;

test_artifact_is_running :: (artifact_path: string) -> bool {
    array_add(*test_is_running_checked, copy_string(artifact_path));
    return test_is_running_result;
}

test_handoff_calls: s64;
test_handoff_plan: Juice.Artifact_Plan;
test_handoff_success: bool;

test_artifact_handoff :: (plan: Juice.Artifact_Plan) -> bool {
    test_handoff_calls += 1;
    test_handoff_plan = plan;
    return test_handoff_success;
}

reset_build_seam :: () {
    test_compile_count = 0;
    test_compiled_plan = .{};
    test_compiled_driver_root = "";
    test_compiled_entry = "";
    test_compile_success = true;
    test_compile_at_calls = 0;
    array_reset(*test_compile_at_entries);
    test_is_running_result = false;
    array_reset(*test_is_running_checked);
    test_handoff_calls = 0;
    test_handoff_plan = .{};
    test_handoff_success = true;
}

// Fake compile child spawn for compile_artifact_plan's seam tests: records
// the metaprogram path and returns the canned exit code; when
// test_spawn_artifact is non-empty, the fake writes it (simulating a
// successful compiler product) so the artifact check and the target
// directory creation can be driven deterministically.
test_spawn_calls: s64;
test_spawn_metaprogram_path: string;
test_spawn_exit_code: s32;
test_spawn_artifact: string;

test_spawn_build_compiler :: (metaprogram_path: string) -> Process_Result {
    test_spawn_calls += 1;
    test_spawn_metaprogram_path = metaprogram_path;
    if test_spawn_artifact != "" {
        make_directory_if_it_does_not_exist(path_strip_filename(test_spawn_artifact), recursive = true);
        write_entire_file(test_spawn_artifact, "fake artifact\n");
    }
    return .{exit_code = test_spawn_exit_code};
}

reset_compile_seam :: () {
    test_spawn_calls = 0;
    test_spawn_metaprogram_path = "";
    test_spawn_exit_code = 0;
    test_spawn_artifact = "";
}

// A prepared workspace over a real temp fixture root: the revalidation gate
// probes real files even in seam tests (the same posture as the old juice
// helpers).
build_seam_plan :: (root: string, main_file: string) -> Juice.Artifact_Plan {
    plan: Juice.Artifact_Plan;
    plan.target = .{name = "app", main_file = main_file, source_path = tprint("%1/%2", root, main_file)};
    plan.target_dir = package_target_dir(root);
    plan.artifact_path = target_artifact_path(plan.target_dir, "app");
    return plan;
}

build_seam_prepared :: (root: string, plan: Juice.Artifact_Plan) -> Juice.Prepared_Workspace {
    prepared: Juice.Prepared_Workspace;
    prepared.discovery.root_dir = root;
    // The plan must live in a heap-backed array: a static literal here would
    // leave the slice pointing at this frame's stack.
    plans: [..] Juice.Artifact_Plan;
    array_add(*plans, plan);
    prepared.artifact_plans = plans;
    return prepared;
}

build_seam_write :: (root: string, rel: string, content: string) -> bool {
    path := tprint("%1/%2", root, rel);
    if !make_directory_if_it_does_not_exist(path_strip_filename(path), recursive = true) return false;
    return write_entire_file(path, content);
}

// ---------------------------------------------------------------------------
// Missing-source test support (ticket 053, review fix F2): the missing-source
// scenarios park a package source under the target/recovery zone and must
// never leave the only copy in memory. park_source_file writes and verifies
// the backup on disk BEFORE removing the original, so a test process killed
// mid-run leaves the source recoverable at backup_path; restore_source_file
// copies it back, verifies the restored bytes and removes the backup. Both
// return false on any unchecked step so the caller's expect() turns a failed
// restore into a test failure. Backups are session artifacts under the
// caller's target/recovery path (unique per test); the test command's
// scratch prune never touches that zone.
// ---------------------------------------------------------------------------
park_source_file :: (source_path: string, backup_path: string) -> bool {
    source, read_ok := read_entire_file(source_path);
    if !read_ok return false;
    if !make_directory_if_it_does_not_exist(path_strip_filename(backup_path), recursive = true) return false;
    if file_exists(backup_path) {
        if !file_delete(backup_path) return false;
    }
    if !write_entire_file(backup_path, source) return false;
    backup, backup_ok := read_entire_file(backup_path);
    if !backup_ok || backup != source return false;
    return file_delete(source_path);
}

restore_source_file :: (source_path: string, backup_path: string) -> bool {
    backup, backup_ok := read_entire_file(backup_path);
    if !backup_ok return false;
    if !write_entire_file(source_path, backup) return false;
    restored, restored_ok := read_entire_file(source_path);
    if !restored_ok || restored != backup return false;
    return file_delete(backup_path);
}

// ---------------------------------------------------------------------------
// Clean test support: the recording fakes for the validate/delete seams (the
// old juice test_clean_* semantics). deleted_too_early flags a delete that
// started before every path was validated, pinning the validate-all-then-
// delete contract; expected_validations is the count the delete fake checks
// against.
// ---------------------------------------------------------------------------
test_clean_validated: [..] string;
test_clean_deleted: [..] string;
test_clean_invalid_path: string;
test_clean_failed_delete: string;
test_clean_expected_validations: s64;
test_clean_deleted_too_early: bool;

reset_clean_test :: (expected_validations: s64) {
    array_reset(*test_clean_validated);
    array_reset(*test_clean_deleted);
    test_clean_invalid_path = "";
    test_clean_failed_delete = "";
    test_clean_expected_validations = expected_validations;
    test_clean_deleted_too_early = false;
}

test_validate_clean_path :: (path: string) -> bool {
    array_add(*test_clean_validated, path);
    return path != test_clean_invalid_path;
}

test_delete_clean_path :: (path: string) -> bool {
    if test_clean_validated.count != test_clean_expected_validations test_clean_deleted_too_early = true;
    array_add(*test_clean_deleted, path);
    return path != test_clean_failed_delete;
}

// Creates a directory/file link with mklink. Returns false when the machine
// refuses link creation (needs developer mode or elevation) — junction tests
// follow the SKIP convention on such machines (the old juice helper).
make_test_link :: (link: string, target: string, directory: bool, junction: bool) -> bool {
    args: [..] string;
    array_add(*args, "cmd");
    array_add(*args, "/c");
    array_add(*args, "mklink");
    if junction {
        array_add(*args, "/J");
    } else if directory {
        array_add(*args, "/D");
    }
    // Backslashes throughout: cmd's builtin mklink parses forward-slash
    // path segments as option switches (same reason rmdir calls do).
    array_add(*args, path_backslashes(link));
    array_add(*args, path_backslashes(target));
    result := run_command(..args);
    return result.exit_code == 0;
}

// ---------------------------------------------------------------------------
// Run test support: the recording launch seam (the old juice test_launch_*
// semantics — run_prepared_workspace's launch seam).
// ---------------------------------------------------------------------------
test_launch_count: s64;
test_launched_plan: Juice.Artifact_Plan;
test_launched_root: string;
test_launch_success: bool;

test_launch_artifact :: (plan: Juice.Artifact_Plan, package_root: string) -> bool {
    test_launch_count += 1;
    test_launched_plan = plan;
    test_launched_root = package_root;
    return test_launch_success;
}

reset_run_seam :: () {
    test_launch_count = 0;
    test_launched_plan = .{};
    test_launched_root = "";
    test_launch_success = true;
}

// ---------------------------------------------------------------------------
// Test command seam support (ticket 018): recording collect/spawn fakes for
// test_prepared_workspace's seams (the build compile seam posture — the
// production handlers use the real scan and the real jai invocation; tests
// cross the same interface with recording fakes) plus the file inspection
// helper for the written driver/metaprogram products.
// ---------------------------------------------------------------------------
test_test_collect_calls: s64;
test_test_collect_files: [] Scan_File;
test_test_collect_ok: bool;

test_collect_test_files :: (prepared: *Juice.Prepared_Workspace) -> ([] Scan_File, bool) {
    test_test_collect_calls += 1;
    return test_test_collect_files, test_test_collect_ok;
}

test_test_spawn_calls: s64;
test_test_spawn_path: string;
test_test_spawn_import_dirs: [..] string;
test_test_spawn_exit_code: s32;

test_spawn_test_compiler :: (metaprogram_path: string, import_dirs: [] string) -> Process_Result {
    test_test_spawn_calls += 1;
    test_test_spawn_path = metaprogram_path;
    // The child's module search path (ticket 045): the metaprogram's own
    // top-level plugin imports resolve through it before #run exists.
    array_reset(*test_test_spawn_import_dirs);
    for dir: import_dirs array_add(*test_test_spawn_import_dirs, copy_string(dir));
    return .{exit_code = test_test_spawn_exit_code};
}

reset_test_command_seam :: () {
    test_test_collect_calls = 0;
    test_test_collect_files = Scan_File.[];
    test_test_collect_ok = true;
    test_test_spawn_calls = 0;
    test_test_spawn_path = "";
    array_reset(*test_test_spawn_import_dirs);
    test_test_spawn_exit_code = 0;
}

// A prepared workspace over a root string — the test command consumes only
// the discovery snapshot (root dir + member packages), so seam tests build
// the state directly (the build_seam_prepared posture).
test_command_prepared :: (root: string) -> Juice.Prepared_Workspace {
    prepared: Juice.Prepared_Workspace;
    prepared.discovery.root_dir = root;
    return prepared;
}

file_contains :: (path: string, needle: string) -> bool {
    content, ok := read_entire_file(path);
    if !ok return false;
    return find_index_from_left(content, needle) >= 0;
}

// The `package_view_paths` array embedded in a generated test runner text,
// in emission order. The generated statement is one line:
// `package_view_paths: [] string = string.["a", "b"];`. The paths in that
// array are plain quoted strings (never escaped), so splitting on the quote
// character yields them at the odd indices. The driver source's own #load
// lines are escaped inside an add_build_string literal and are deliberately
// not parsed here — the generated mapping is the contract the tests read.
test_program_package_view_paths :: (text: string) -> [..] string {
    out: [..] string;
    marker := "package_view_paths: [] string = string.[";
    start := find_index_from_left(text, marker);
    if start < 0 return out;
    start += marker.count;
    body_length := find_index_from_left(advance(text, start), "];");
    if body_length < 0 return out;
    parts := split(slice(text, start, body_length), "\"");
    for part, index: parts {
        if index % 2 == 1 array_add(*out, copy_string(part));
    }
    return out;
}

// ---------------------------------------------------------------------------
// Test metaprogram E2E support (ticket 017, single-face shape since ticket
// 035): the @test fixture child — the production generator faces assemble
// the driver and the test metaprogram from a fixture's src files, both land
// under the cache directory, and a real jai child compiles the metaprogram
// (the test program really compiles and the injected #run really executes).
// The per-fixture file lists are explicit — deterministic discovery order
// without a directory scan (the scan_walk collection lands with the test
// command, ticket 018). The jai child anchors its #run working directory at
// the metaprogram's own directory (target/test-metaprogram-e2e/<fixture>/);
// the generated driver's own #run re-anchors at the fixture root (the 009
// deviation 2 discipline).
//
// The driver imports the published Testing face like every production test
// program (ticket 035); the raw published Testing.jai carries self-test
// blocks that raw imports cannot compile, so the production strip-view
// helper lands the import target beside the cache products and the
// metaprogram prepends its directory to the import path.
// ---------------------------------------------------------------------------
test_program_fixture_files :: (fixture_name: string) -> [] string {
    if fixture_name == "test-fixture" {
        return string.["src/tests_a.jai", "src/tests_b.jai"];
    }
    return string.["src/failing.jai"];
}

run_test_program_child :: (fixture_name: string) -> (Process_Result, string, string) {
    ensure_published_modules();
    fixture_root := path_slashes(tprint("%1/tests/data/%2", otter_root(), fixture_name));
    cache := path_slashes(otter_scratch(tprint("test-metaprogram-e2e/%1", fixture_name)));
    make_directory_if_it_does_not_exist(cache, recursive = true);
    metaprogram := tprint("%1/metaprogram.jai", cache);

    files := test_program_fixture_files(fixture_name);

    // The published Testing face is test-free (the definition source's
    // self-tests are cut at publication), so the modules directory itself is
    // the import root — no strip view.
    testing_view_dir := plugin_face_modules_dir();
    if !file_exists(tprint("%1/Testing.jai", testing_view_dir)) return .{exit_code = -1}, "published Testing module missing", "";

    driver_options: Test_Driver_Options;
    driver_options.package_root = fixture_root;
    driver_files: [..] string;
    for file: files array_add(*driver_files, tprint("%1/%2", fixture_root, file));
    driver_options.source_files = driver_files;

    metaprogram_options: Test_Metaprogram_Options;
    metaprogram_options.workspace_name    = "Juice Test Program";
    metaprogram_options.intermediate_path = cache;
    metaprogram_options.testing_view_dir  = testing_view_dir;
    metaprogram_options.driver_source     = generate_test_driver(driver_options);
    metaprogram_options.discovery_source  = path_slashes(tprint("%1/src/test_discovery.jai", otter_root()));
    view_paths: [..] string;
    pairs: [..] Test_Path_Pair;
    for file: files {
        array_add(*view_paths, tprint("%1/%2", fixture_root, file));
        array_add(*pairs, .{ view = tprint("%1/%2", fixture_root, file), original = file });
    }
    metaprogram_options.package_view_paths = view_paths;
    metaprogram_options.path_pairs = pairs;
    write_entire_file(metaprogram, generate_test_metaprogram(metaprogram_options));

    result, output, errors, _ := run_command("jai", metaprogram, "-quiet", working_directory = otter_root(), capture_and_return_output = true);
    return result, output, errors;
}

// ---------------------------------------------------------------------------
// Plugin scan E2E support (ticket 025): the juice_core module the plugin
// face consumers import by name (the fixture plugin modules and the
// generated driver — every scope shares one type identity; a #load
// duplicate in two scopes would create incompatible duplicate types,
// spike-pinned), published through the ticket 030 production generator
// (ticket 032 retired the hand-rolled stand-in: ensure_published_modules
// lands all four artifacts), and the generated driver child exercising the
// whole chain: production scan of the fixture -> registration file
// (production codegen, landed via the production path helper) -> real jai
// compile of driver + registration + fixture modules -> merged registry
// execution (transpile face + hooks).
// ---------------------------------------------------------------------------

// The jai compiler child spawn path (the pinned dev-layout constant — the
// test program's own compile runs the same compiler).
JAI_COMPILER_PATH :: "C:/Users/maojiaxing/DevTools/jai/bin/jai.exe";

// The published modules directory (target/modules — the published faces'
// home, ticket 032; the juice_core seed's former home).
plugin_face_modules_dir :: () -> string {
    return target_modules_dir(otter_target_dir());
}

// The E2E driver: imports the face by name, loads the registration file,
// assembles the scanned registry, merges it and resolves the declaration
// configs (ticket 056 — the pipeline/hook/lint landing point), runs the
// resolved transpile pipeline on a marked source and fires the resolved hook
// table on both mounted stages (slot_options fills plugin_state). The
// printed lines are the child-output pins. `marker` is the bare IDENT the
// transpile source carries ("fixture_mark" for the good fixture, "bad_mark"
// for the bad fixture's line-fidelity rejection); `configs` are the
// declarations the resolver consumes (the fixture's plugin ids).
plugin_scan_driver_code :: (registration_path: string, marker: string, configs: [] Plugin_Config) -> string {
    builder: String_Builder;
    append(*builder, "#import \"Basic\";\n");
    append(*builder, "#import \"Compiler\";\n");
    append(*builder, "#import \"juice_core\";\n");
    append(*builder, "#load \"");
    append(*builder, path_slashes(registration_path));
    append(*builder, "\";\n\n");
    append(*builder, "#run { set_build_options_dc(.{do_output = false}); main(); }\n\n");
    append(*builder, "plugin_configs: [] Plugin_Config = Plugin_Config.[");
    for config, index: configs {
        if index > 0 append(*builder, ", ");
        print_to_builder(*builder, ".{ id = %1, version = %2, options = Option_Row.[] }", quote_jai_string(config.id), quote_jai_string(config.version));
    }
    append(*builder, "];\n\n");
    append(*builder, "main :: () {\n");
    append(*builder, "    plugins := get_scanned_plugins();\n");
    append(*builder, "    print(\"plugins=%\\n\", plugins.count);\n");
    append(*builder, "    merged := merge_plugins(plugins);\n");
    append(*builder, "    print(\"merged-ok=%\\n\", merged.ok);\n");
    append(*builder, "    print(\"merge-diags=%\\n\", merged.diagnostics.count);\n");
    append(*builder, "    for d: merged.diagnostics print(\"merge-diag=%\\n\", d.message);\n");
    append(*builder, "    resolved := resolve_plugin_configs(merged.registry, plugin_configs);\n");
    append(*builder, "    print(\"resolved-ok=%\\n\", resolved.ok);\n");
    append(*builder, "    print(\"resolve-diags=%\\n\", resolved.diagnostics.count);\n");
    append(*builder, "    for d: resolved.diagnostics print(\"resolve-diag=%\\n\", d.message);\n");
    append(*builder, "    print(\"pipeline=%\\n\", resolved.pipeline.count);\n");
    append(*builder, "    for p: resolved.pipeline print(\"pipeline-name=%\\n\", p.name);\n");
    append(*builder, "    print(\"lint=%\\n\", resolved.lint_plugins.count);\n");
    append(*builder, "    print(\"hook-regs=%\\n\", resolved.hook_table.count);\n\n");
    append(*builder, "    entries := get_scanned_hook_entries();\n");
    append(*builder, "    print(\"hook-entries=%\\n\", entries.count);\n");
    append(*builder, "    for e: entries {\n");
    append(*builder, "        print(\"hook-entry=%1-%2\\n\", stage_name(e.stage), ifx e.position == .before then \"before\" else \"after\");\n");
    append(*builder, "    }\n\n");
    append(*builder, "    tctx: Transpile_Context;\n");
    append(*builder, "    tctx.mode = .EXPAND;\n");
    append(*builder, "    tctx.path = \"src/a.jai\";\n");
    append(*builder, "    tctx.next_test_number = 1;\n");
    append(*builder, "    tctx.plugins = resolved.pipeline;\n");
    append(*builder, "    tresult := transpile_source(\"x := ");
    append(*builder, marker);
    append(*builder, ";\\n\", tctx);\n");
    append(*builder, "    print(\"transpile-diags=%\\n\", tresult.diagnostics.count);\n");
    append(*builder, "    for d: tresult.diagnostics print(\"transpile-diag=%\\n\", d.message);\n");
    append(*builder, "    print(\"transpile-view=%\\n\", tresult.view);\n\n");
    append(*builder, "    diags: [..] Lifecycle_Diagnostic;\n");
    append(*builder, "    lctx: Lifecycle_Context;\n");
    append(*builder, "    lctx.diagnostics = *diags;\n");
    append(*builder, "    for slot: resolved.slot_options array_add(*lctx.plugin_state, slot);\n");
    append(*builder, "    print(\"before-ran=%\\n\", run_mounted_hooks(resolved.hook_table, .TRANSPILE, .before, *lctx));\n");
    append(*builder, "    print(\"before-diag=%\\n\", ifx diags.count > 0 then diags[diags.count - 1].message else \"none\");\n");
    append(*builder, "    print(\"after-ran=%\\n\", run_mounted_hooks(resolved.hook_table, .COMPILE, .after, *lctx));\n");
    append(*builder, "    print(\"after-diag=%\\n\", ifx diags.count > 0 then diags[diags.count - 1].message else \"none\");\n");
    append(*builder, "}\n");
    return builder_to_string(*builder);
}

// The full-chain child: production scan of the fixture -> registration file
// (production codegen, landed via the production path helper) -> published
// module faces (juice_core among them) -> driver -> real jai compile +
// execute. The registration and the driver land under target/plugins/
// <fixture>/ (session artifacts). `marker` feeds the driver's transpile
// source and `configs` the resolver declarations (see
// plugin_scan_driver_code).
run_plugin_scan_child :: (fixture_name: string, marker: string, configs: [] Plugin_Config) -> (Process_Result, string, string) {
    fixture_root := path_slashes(tprint("%1/tests/data/%2", otter_root(), fixture_name));
    scan := scan_plugin_package(fixture_root);
    if !scan.ok return .{exit_code = -1}, "scan failed", "";
    target_dir := otter_target_dir();
    registration_path := plugin_registration_path(target_dir, fixture_name);
    landing_dir := path_strip_filename(registration_path);
    if !make_directory_if_it_does_not_exist(landing_dir, recursive = true) return .{exit_code = -1}, "landing dir failed", "";
    if !write_entire_file(registration_path, generate_plugin_registration(scan.hits)) return .{exit_code = -1}, "registration write failed", "";
    if !ensure_published_modules() return .{exit_code = -1}, "module publish failed", "";
    driver := tprint("%1/driver.jai", landing_dir);
    if !write_entire_file(driver, plugin_scan_driver_code(registration_path, marker, configs)) return .{exit_code = -1}, "driver write failed", "";
    result, output, errors, _ := run_command(JAI_COMPILER_PATH, driver, "-import_dir", plugin_face_modules_dir(), "-import_dir", path_slashes(tprint("%1/tests/data", otter_root())), "-import_dir", fixture_root, "-quiet", working_directory = otter_root(), capture_and_return_output = true);
    return result, output, errors;
}

// ---------------------------------------------------------------------------
// Lint observation E2E support (ticket 042): the generated test metaprogram
// with a plugin registration loaded. The full chain, production faces only:
// scan_plugin_package over the registration fixture -> generate_plugin_
// registration -> the production test driver + metaprogram generators with
// plugin_registration / package_root set -> a real jai child compiling the
// test program. registration_fixture and test_fixture are separate
// parameters so the merge-failure scenario pairs a rejected plugin set with
// any test program. The registration module names resolve through the
// fixture parent directory (tests/data) and the registration fixture root
// (stem modules); the child runs with its working directory at the test
// fixture root — the production package-root anchor. compiler_report opens
// the reported file on disk to print the source line, so the generated text
// itself anchors at package_root before the workspace exists (the jai child
// otherwise starts at the metaprogram's own directory, and the driver's own
// #run chdir runs too late for collection-time reports).
// ---------------------------------------------------------------------------
run_plugin_lint_child :: (registration_fixture: string, test_fixture: string, test_files: [] string, pattern := "", configs: [] Plugin_Config = .[]) -> (Process_Result, string, string) {
    registration_root := path_slashes(tprint("%1/tests/data/%2", otter_root(), registration_fixture));
    scan := scan_plugin_package(registration_root);
    if !scan.ok return .{exit_code = -1}, "scan failed", "";
    ensure_published_modules();

    // The declaration configs the generated program resolves against. The
    // default is the fixture's own plugin identity (the lint fixture names
    // its plugin after the package at version 1.0.0); the merge-failure
    // scenario never reaches the resolver, so its config content is moot.
    resolved_configs := configs;
    if resolved_configs.count == 0 {
        default_configs: [..] Plugin_Config;
        array_add(*default_configs, .{id = registration_fixture, version = "1.0.0"});
        resolved_configs = default_configs;
    }

    cache := path_slashes(otter_scratch(tprint("plugin-lint-e2e/%1", registration_fixture)));
    delete_directory_full(cache);
    make_directory_if_it_does_not_exist(cache, recursive = true);
    registration := tprint("%1/registration.jai", cache);
    write_entire_file(registration, generate_plugin_registration(scan.hits));

    fixture_root := path_slashes(tprint("%1/tests/data/%2", otter_root(), test_fixture));
    // The published Testing face is test-free (the definition source's
    // self-tests are cut at publication), so the modules directory itself is
    // the import root — no strip view.
    testing_view_dir := plugin_face_modules_dir();
    if !file_exists(tprint("%1/Testing.jai", testing_view_dir)) return .{exit_code = -1}, "published Testing module missing", "";

    metaprogram := tprint("%1/metaprogram.jai", cache);
    driver_options: Test_Driver_Options;
    driver_options.package_root = fixture_root;
    driver_files: [..] string;
    for file: test_files array_add(*driver_files, tprint("%1/%2", fixture_root, file));
    driver_options.source_files = driver_files;

    metaprogram_options: Test_Metaprogram_Options;
    metaprogram_options.workspace_name      = "Juice Test Program";
    metaprogram_options.intermediate_path   = cache;
    metaprogram_options.testing_view_dir    = testing_view_dir;
    metaprogram_options.driver_source       = generate_test_driver(driver_options);
    metaprogram_options.discovery_source    = path_slashes(tprint("%1/src/test_discovery.jai", otter_root()));
    metaprogram_options.plugin_registration = registration;
    metaprogram_options.package_root        = fixture_root;
    metaprogram_options.pattern             = pattern;
    metaprogram_options.plugin_configs      = resolved_configs;
    // The test source imports the fixture's imported module by name (the
    // isolation fixture); the inner workspace resolves it through the
    // fixture root.
    metaprogram_options.import_dirs = string.[fixture_root];
    view_paths: [..] string;
    pairs: [..] Test_Path_Pair;
    for file: test_files {
        array_add(*view_paths, tprint("%1/%2", fixture_root, file));
        array_add(*pairs, .{ view = tprint("%1/%2", fixture_root, file), original = file });
    }
    metaprogram_options.package_view_paths = view_paths;
    metaprogram_options.path_pairs = pairs;
    write_entire_file(metaprogram, generate_test_metaprogram(metaprogram_options));

    result, output, errors, _ := run_command(JAI_COMPILER_PATH, metaprogram,
        "-import_dir", plugin_face_modules_dir(),
        "-import_dir", path_slashes(tprint("%1/tests/data", otter_root())),
        "-import_dir", registration_root,
        "-quiet", working_directory = fixture_root, capture_and_return_output = true);
    return result, output, errors;
}
