#import "Basic";
#import "Testing";

// ---------------------------------------------------------------------------
// Workspace tests: the phase machine matrix runs with the recording seam
// fakes (in-process, no children — old juice workspace.jai inline test
// semantics); the member path gate is pure; the discovery member matrix
// spawns a generated jai driver child per fixture and asserts the discovery
// error text byte for byte (old juice test_monorepo semantics — the build
// command, discovery's production consumer, lands with ticket 011, so the
// driver stands in for the exe until then).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Validation matrix: the member path validity gate is testable in-process —
// empty, absolute (including volume designators) and ".."-escaping
// components are rejected, "." components and plain relative paths pass
// (passing "." lets the bad-duplicate fixture's "member_lib/." spelling
// reach the duplicate branch).
// ---------------------------------------------------------------------------

test "Workspace member path validity gate" {
    expect(!workspace_relative_path_is_valid(""));
    expect(!workspace_relative_path_is_valid("/abs"));
    expect(!workspace_relative_path_is_valid("C:/abs"));
    expect(!workspace_relative_path_is_valid("../escape"));
    expect(!workspace_relative_path_is_valid("a/../b"));
    expect(workspace_relative_path_is_valid("."));
    expect(workspace_relative_path_is_valid("member_lib"));
    expect(workspace_relative_path_is_valid("member_lib/."));
    expect(workspace_relative_path_is_valid("a/b"));
}

// ---------------------------------------------------------------------------
// The phase machine: EMPTY -> DISCOVERED -> PREPARED, idempotency, and
// publish-only-on-full-success (the recording fakes live in
// tests/test_support.jai).
// ---------------------------------------------------------------------------

test "Discovery publishes workspace state once" {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = true;
    test_fake_discovery.root_package.name = "demo";
    test_fake_discovery.root_package.version = "1";
    state: Workspace_State;
    expect(ensure_workspace_discovered("", "", *state, test_fake_discover));
    expect(state.phase == .DISCOVERED && test_discovery_attempts == 1);
    expect(ensure_workspace_discovered("", "", *state, test_fake_discover));
    expect(state.phase == .DISCOVERED && test_discovery_attempts == 1);
}

test "Discovery without a package stays empty" {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = false;
    state: Workspace_State;
    expect(!ensure_workspace_discovered("", "", *state, test_fake_discover));
    expect(state.phase == .EMPTY && test_discovery_attempts == 1);
}

test "Preparation without targets skips dependencies" {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = true;
    test_fake_discovery.root_package.name = "demo";
    test_fake_discovery.root_package.version = "1";
    test_plan_resolution_success = true;
    test_resolved_plans = Juice.Artifact_Plan.[];
    state: Workspace_State;
    expect(ensure_workspace_discovered("", "", *state, test_fake_discover));
    expect(prepare_workspace("", "", *state, test_fake_resolve, test_fake_prepare_dependencies));
    expect(state.phase == .PREPARED && test_dependency_attempts == 0);
    prepared := get_prepared_workspace(*state);
    expect(prepared != null && !prepared.dependencies_prepared && prepared.artifact_plans.count == 0);
}

// The dependency preparation consumes the discovery snapshot: the declared
// member packages — with their declared dependencies — flow into the
// prepare_dependencies seam verbatim (members are referenced only through
// declared DEP records; the dependency layer links them by declared name).
test "Preparation with targets prepares the declared member snapshot" {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = true;
    test_fake_discovery.root_package.name = "demo";
    test_fake_discovery.root_package.version = "1";
    test_fake_discovery.member_packages = Juice.Package.[
        .{name = "root", dir = "root"},
        .{name = "member", dir = "root/member", dependencies = Juice.Dependency.[.{name = "member-lib"}]},
    ];
    test_plan_resolution_success = true;
    test_resolved_plans = Juice.Artifact_Plan.[.{target = .{name = "demo"}}];
    test_dependency_ok = true;
    state: Workspace_State;
    expect(ensure_workspace_discovered("", "", *state, test_fake_discover));
    expect(prepare_workspace("", "", *state, test_fake_resolve, test_fake_prepare_dependencies));
    expect(state.phase == .PREPARED && test_dependency_attempts == 1);
    expect(test_dependency_snapshot.count == 2 && test_dependency_snapshot[1].name == "member");
    expect(test_dependency_snapshot[1].dependencies.count == 1 && test_dependency_snapshot[1].dependencies[0].name == "member-lib");
    prepared := get_prepared_workspace(*state);
    expect(prepared != null && prepared.dependencies_prepared);
}

// force_dependencies makes a 0-plans (LIB) package prepare dependencies too
// — Test's test program references dependencies through import shims; the
// default (false) semantics are unchanged (pinned by "Preparation without
// targets skips dependencies" above).
test "Preparation without targets forces dependencies on request" {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = true;
    test_fake_discovery.root_package.name = "demo";
    test_fake_discovery.root_package.version = "1";
    test_fake_discovery.member_packages = Juice.Package.[.{name = "root", dir = "root"}, .{name = "member", dir = "root/member"}];
    test_plan_resolution_success = true;
    test_resolved_plans = Juice.Artifact_Plan.[];
    test_dependency_ok = true;
    state: Workspace_State;
    expect(ensure_workspace_discovered("", "", *state, test_fake_discover));
    expect(prepare_workspace("", "", *state, test_fake_resolve, test_fake_prepare_dependencies, true));
    expect(state.phase == .PREPARED && test_dependency_attempts == 1);
    prepared := get_prepared_workspace(*state);
    expect(prepared != null && prepared.dependencies_prepared);
    expect(prepared.artifact_plans.count == 0);
}

// A failed prepare publishes nothing: the state stays DISCOVERED (retryable)
// and get_prepared_workspace exposes no partial result. The retry after the
// failure succeeds and publishes.
test "Resolution failure publishes no prepared workspace" {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = true;
    test_fake_discovery.root_package.name = "demo";
    test_fake_discovery.root_package.version = "1";
    test_plan_resolution_success = false;
    state: Workspace_State;
    expect(ensure_workspace_discovered("", "", *state, test_fake_discover));
    expect(!prepare_workspace("", "", *state, test_fake_resolve, test_fake_prepare_dependencies));
    expect(state.phase == .DISCOVERED && get_prepared_workspace(*state) == null);
    test_plan_resolution_success = true;
    test_resolved_plans = Juice.Artifact_Plan.[];
    expect(prepare_workspace("", "", *state, test_fake_resolve, test_fake_prepare_dependencies) && state.phase == .PREPARED);
}

test "Dependency failure publishes no prepared workspace" {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = true;
    test_fake_discovery.root_package.name = "demo";
    test_fake_discovery.root_package.version = "1";
    test_plan_resolution_success = true;
    test_resolved_plans = Juice.Artifact_Plan.[.{target = .{name = "demo"}}];
    test_dependency_ok = false;
    state: Workspace_State;
    expect(ensure_workspace_discovered("", "", *state, test_fake_discover));
    expect(!prepare_workspace("", "", *state, test_fake_resolve, test_fake_prepare_dependencies));
    expect(state.phase == .DISCOVERED && test_dependency_attempts == 1 && get_prepared_workspace(*state) == null);
}

test "Preparation requires discovery" {
    reset_preparation_test();
    state: Workspace_State;
    expect(!prepare_workspace("", "", *state, test_fake_resolve, test_fake_prepare_dependencies));
    expect(state.phase == .EMPTY && test_dependency_attempts == 0);
}

// The command-side preparation entry: one idempotent call chains the two
// phases and hands back the prepared result directly, null = failure already
// printed. The guard duty is absorbed by this entry — failures print the
// concrete error (e.g. "No package.jai found"), not a generic "requires
// workspace preparation".
test "Prepared workspace ensure fails on an empty state" {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = false;
    state: Workspace_State;
    expect(ensure_workspace_prepared("", "", *state, test_fake_discover, test_fake_resolve, test_fake_prepare_dependencies) == null);
    expect(state.phase == .EMPTY && test_discovery_attempts == 1);
}

test "Prepared workspace ensure hands back the prepared result" {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = true;
    test_fake_discovery.root_package.name = "demo";
    test_fake_discovery.root_package.version = "1";
    test_plan_resolution_success = true;
    test_resolved_plans = Juice.Artifact_Plan.[];
    state: Workspace_State;
    prepared := ensure_workspace_prepared("", "", *state, test_fake_discover, test_fake_resolve, test_fake_prepare_dependencies);
    expect(prepared != null && state.phase == .PREPARED);
    expect(!prepared.dependencies_prepared && prepared.artifact_plans.count == 0);
}

test "Prepared workspace ensure is idempotent" {
    reset_preparation_test();
    test_fake_discovery_ok = true;
    test_fake_discovery.has_package = true;
    test_fake_discovery.root_package.name = "demo";
    test_fake_discovery.root_package.version = "1";
    test_plan_resolution_success = true;
    test_resolved_plans = Juice.Artifact_Plan.[];
    state: Workspace_State;
    first := ensure_workspace_prepared("", "", *state, test_fake_discover, test_fake_resolve, test_fake_prepare_dependencies);
    expect(first != null);
    second := ensure_workspace_prepared("", "", *state, test_fake_discover, test_fake_resolve, test_fake_prepare_dependencies);
    expect(second == first && test_discovery_attempts == 1);
}

// ---------------------------------------------------------------------------
// Discovery member matrix: one generated driver child per fixture, asserting
// the concrete error message byte for byte (old juice test_monorepo
// semantics). The error fixtures never reach a manifest load except the
// root/member-manifest branches, which evaluate through real jai children
// with the bootstrap modules directory injected.
// ---------------------------------------------------------------------------

test "E2E: discovery rejects an invalid root manifest" {
    result, output, _ := run_workspace_discovery_child("workspace-bad-root-manifest");
    expect(expect_exit("bad-root-manifest", result, 0, "discovery child"));
    expect(output_matches("bad-root-manifest", output, string.[
        "[juice ERROR] Existing package.jai is invalid.",
        "discovery-ok=false",
    ]));
}

test "E2E: discovery rejects a member path with escape components" {
    result, output, _ := run_workspace_discovery_child("workspace-bad-escape");
    expect(expect_exit("bad-escape", result, 0, "discovery child"));
    expect(output_matches("bad-escape", output, string.[
        "[juice ERROR] Invalid workspace member path: ../outside",
        "discovery-ok=false",
    ]));
}

// Verified by measurement in old juice: a member directory that does not
// exist hits the not-a-safe-real-directory branch — normalize_existing_path
// never verifies existence, and the inspection finding !exists takes the
// same branch.
test "E2E: discovery rejects a member directory that does not exist" {
    result, output, _ := run_workspace_discovery_child("workspace-bad-missing-dir");
    expect(expect_exit("bad-missing-dir", result, 0, "discovery child"));
    expect(output_matches("bad-missing-dir", output, string.[
        "[juice ERROR] Workspace member is not a safe real directory: ghost_member",
        "discovery-ok=false",
    ]));
}

test "E2E: discovery rejects a member without a manifest" {
    result, output, _ := run_workspace_discovery_child("workspace-bad-no-manifest");
    expect(expect_exit("bad-no-manifest", result, 0, "discovery child"));
    expect(output_matches("bad-no-manifest", output, string.[
        "[juice ERROR] Workspace member lacks package.jai:",
        "discovery-ok=false",
    ]));
}

test "E2E: discovery rejects an invalid member manifest" {
    result, output, _ := run_workspace_discovery_child("workspace-bad-invalid-manifest");
    expect(expect_exit("bad-invalid-manifest", result, 0, "discovery child"));
    expect(output_matches("bad-invalid-manifest", output, string.[
        "[juice ERROR] Workspace member manifest is invalid:",
        "discovery-ok=false",
    ]));
}

// "member_lib/." differs textually from "member_lib" but normalizes to the
// same directory (a measured spelling).
test "E2E: discovery rejects duplicate member paths" {
    result, output, _ := run_workspace_discovery_child("workspace-bad-duplicate");
    expect(expect_exit("bad-duplicate", result, 0, "discovery child"));
    expect(output_matches("bad-duplicate", output, string.[
        "[juice ERROR] Duplicate workspace member path: member_lib/.",
        "discovery-ok=false",
    ]));
}

// Edge case: the root lists "." as a member — normalization makes it equal
// to the root, which entered the member list first, hitting the duplicate
// branch (pins old juice's behavior).
test "E2E: discovery rejects the root listed as its own member" {
    result, output, _ := run_workspace_discovery_child("workspace-edge-self");
    expect(expect_exit("edge-self", result, 0, "discovery child"));
    expect(output_matches("edge-self", output, string.[
        "[juice ERROR] Duplicate workspace member path: .",
        "discovery-ok=false",
    ]));
}

// The dependency declaration face: the root references both members through
// declared DEP records, member_extra declares its member_lib dependency in
// its own manifest, and the discovery snapshot carries every declared
// package with its declared dependencies (root first, then member
// declaration order) — the dependency layer (ticket 009) links members by
// these declared names.
test "E2E: discovery loads the declared member snapshot" {
    result, output, _ := run_workspace_discovery_child("workspace-ok");
    expect(expect_exit("workspace-ok", result, 0, "discovery child"));
    expect(output_matches("workspace-ok", output, string.[
        "discovery-ok=true",
        "has-package=true",
        "root=ws_root v=0.1.0",
        "root-dep=member_lib",
        "root-dep=member_extra",
        "member=ws_root deps=2",
        "member=member_lib deps=0",
        "member=member_extra deps=1",
        "member-dep=member_extra:member_lib",
    ]));
}
