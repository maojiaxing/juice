#import "Basic";
#import "Compiler";

// The version command (002 decision 5, spec section 4.1): two lines — the
// tool's own version and the jai compiler version baked into the executable
// at compile time. Zero prerequisites, zero workspace: the command must work
// anywhere, including outside a package root, so the tool version is a
// hardcoded constant kept in sync with package.jai's PACKAGE.version (the
// manifest declares it; the command cannot read it).
JUICE_VERSION :: "0.1.0";

// The jai compiler version, baked at compile time (002 decision 5): jai has
// no --version flag, and compiler_get_version_info (Compiler.jai:1509) is a
// #compiler intrinsic callable only from compile-time contexts — the #run
// constant form (how_to 080) evaluates it during otter's own build. Spike
// (2026-10-19, AppData/Local/Temp/otter-version-spike): the string return is
// the full banner ("beta 0.2.009, built on 6 February 2025"), not the
// major.minor.micro the Compiler.jai comment promises; the numeric triple
// comes from the filled Version_Info struct — the version command prints
// that triple.
JAI_COMPILER_VERSION :: #run -> string {
    info: Version_Info;
    compiler_get_version_info(*info);
    return tprint("%1.%2.%3", info.major, info.minor, info.micro);
};

VERSION_COMMAND :: Command.{
    name          = "version",
    description   = "Print juice and jai version information",
    usage         = "juice version",
    prerequisites = string.[],
    handler       = version_command,
};

version_command :: (ctx: *Command_Context, arguments: [] string) -> bool {
    if !command_arguments_are_valid(VERSION_COMMAND, arguments) return false;
    print("juice %\n", JUICE_VERSION);
    print("jai %\n", JAI_COMPILER_VERSION);
    return true;
}
