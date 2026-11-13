#import "Basic";
#import "Testing";

// ---------------------------------------------------------------------------
// Help command tests: the in-process behavior of the help handler (zero
// prerequisites, zero side effects — it runs without a workspace). The
// rendered output text is locked by the E2E blocks in e2e_cli_tests.jai,
// which spawn the real executable.
// ---------------------------------------------------------------------------

test "Help: the overview runs with no arguments" {
    ctx: Command_Context;
    expect(help_command(*ctx, string.[]));
}

test "Help: a known command is accepted" {
    ctx: Command_Context;
    expect(help_command(*ctx, string.["build"]));
}

test "Help: an unknown command is rejected" {
    ctx: Command_Context;
    expect(!help_command(*ctx, string.["nope"]));
}

test "Help: extra arguments are rejected" {
    ctx: Command_Context;
    expect(!help_command(*ctx, string.["build", "extra"]));
}

test "Help: the declaration carries the spec shape" {
    expect(HELP_COMMAND.name == "help");
    expect(HELP_COMMAND.description == "Show command help");
    expect(HELP_COMMAND.usage == "juice help [command]");
    expect(HELP_COMMAND.prerequisites.count == 0);
    expect(HELP_COMMAND.handler == help_command);
    expect(HELP_COMMAND.validate_arguments == help_arguments_are_valid);
}
