COMMAND_REGISTRY :: Command.[
    .{
        name          = "prepare-workspace",
        description   = "Internal: Load package manifest and resolve dependencies",
        usage         = "juice prepare-workspace",
        prerequisites = string.[],
        visible       = false,
        handler       = prepare_workspace_command,
    },
    .{
        name          = "build",
        description   = "Build all targets in the workspace",
        usage         = "juice build",
        prerequisites = string.["prepare-workspace"],
        visible       = true,
        handler       = build_command,
    },
    .{
        name          = "run",
        description   = "Build and run an executable target",
        usage         = "juice run [target]",
        prerequisites = string.["build"],
        visible       = true,
        handler       = run_command_handler,
    },
    .{
        name          = "clean",
        description   = "Remove build outputs and dependencies",
        usage         = "juice clean",
        prerequisites = string.[],
        visible       = true,
        handler       = clean_command,
    },
];
