#import "Basic";
#import "Testing";

// ---------------------------------------------------------------------------
// CLI E2E tests: the real otter executable (otter/target/juice.exe, built
// by `jai build.jai`) is spawned in-process and driven over the argv
// surface — the help output contract (overview text locked byte for byte,
// per-command
// usage lines), unknown-command rejection, the test command's guard and
// package requirement (the real run lives on the @test fixtures in
// test_command_tests.jai — running it at the otter root would compile the
// whole repository), and the run/version argument guards (plan-time
// rejection, exit code 1). The exe must be built before the test run; the
// verification loop always builds first.
// ---------------------------------------------------------------------------

// The rendered overview (print_usage): the registry in declaration order,
// "  %-12  %" formatting.
EXPECTED_HELP_OVERVIEW :: "Usage: juice [command] [args]\n\nAvailable commands:\n  build         Build all targets in the root package\n  run           Build and run an executable target\n  clean         Remove Juice outputs and local dependency links\n  test          Run unit tests in the root package\n  version       Print juice and jai version information\n  help          Show command help\n";

test "E2E: help prints the six-command overview" {
    result, output, _ := run_otter_child(string.["help"]);
    expect(expect_exit("help overview", result, 0));
    expect(child_output_equals("help overview", output, EXPECTED_HELP_OVERVIEW));
}

test "E2E: help <command> prints the usage line" {
    result, output, _ := run_otter_child(string.["help", "build"]);
    expect(expect_exit("help build", result, 0));
    expect(child_output_equals("help build", output, "juice build\n"));

    result, output, _ = run_otter_child(string.["help", "run"]);
    expect(expect_exit("help run", result, 0));
    expect(child_output_equals("help run", output, "juice run [target]\n"));
}

test "E2E: help rejects an unknown command" {
    result, output, _ := run_otter_child(string.["help", "nope"]);
    expect(expect_exit("help unknown", result, 1));
    expect(output_matches("help unknown", output, string.["[juice ERROR] Unknown command: 'nope'"]));
}

test "E2E: help rejects extra arguments" {
    result, output, _ := run_otter_child(string.["help", "build", "extra"]);
    expect(expect_exit("help extra args", result, 1));
    expect(output_matches("help extra args", output, string.["[juice ERROR] Usage: juice help [command]"]));
}

test "E2E: an unknown command errors and prints the overview" {
    result, output, _ := run_otter_child(string.["frobnicate"]);
    expect(expect_exit("unknown command", result, 1));
    expect(output_matches("unknown command", output, string.[
        "[juice ERROR] Unknown command: 'frobnicate'",
        "Available commands:",
    ]));
}

test "E2E: the test command guards and requires a package" {
    // The real test command (ticket 018) at a scratch root without a
    // package.jai fails discovery before any collection — running it at the
    // otter root would compile the whole repository, so the real run lives
    // on the small @test fixtures in test_command_tests.jai.
    scratch := otter_scratch("e2e-cli-test-scratch");
    delete_directory_full(scratch);
    defer delete_directory_full(scratch);
    expect(make_directory_if_it_does_not_exist(scratch, recursive = true));

    result, output, _ := run_otter_child_at(scratch, string.["test"]);
    expect(expect_exit("test guard", result, 1));
    expect(output_matches("test guard", output, string.["[juice ERROR] No package.jai found in current directory."]));

    // The argument guard rejects at plan time, before any handler runs.
    result, output, _ = run_otter_child(string.["test", "one", "two"]);
    expect(expect_exit("test args", result, 1));
    expect(output_matches("test args", output, string.["[juice ERROR] Usage: juice test [pattern]"]));

    result, output, _ = run_otter_child(string.["build", "unexpected"]);
    expect(expect_exit("build args", result, 1));
    expect(output_matches("build args", output, string.["[juice ERROR] Usage: juice build"]));
}

test "E2E: run and version reject extra arguments" {
    // plan_command validates the requested command's arguments before any
    // prerequisite executes, so the run guard rejects at plan time without
    // triggering a build.
    result, output, _ := run_otter_child(string.["run", "extra", "more"]);
    expect(expect_exit("run args", result, 1));
    expect(output_matches("run args", output, string.["[juice ERROR] Usage: juice run [target]"]));

    result, output, _ = run_otter_child(string.["version", "extra"]);
    expect(expect_exit("version args", result, 1));
    expect(output_matches("version args", output, string.["[juice ERROR] Usage: juice version"]));
}

test "E2E: no command defaults to build" {
    // The default build command is real since ticket 011 — running it at
    // the otter root would compile the repository. A scratch directory
    // without a package.jai fails discovery before any compile, which
    // proves the default command without an expensive build.
    scratch := otter_scratch("e2e-cli-scratch");
    delete_directory_full(scratch);
    defer delete_directory_full(scratch);
    expect(make_directory_if_it_does_not_exist(scratch, recursive = true));

    result, output, _ := run_otter_child_at(scratch, string.[]);
    expect(expect_exit("default command", result, 1));
    expect(output_matches("default command", output, string.["[juice ERROR] No package.jai found in current directory."]));
}
