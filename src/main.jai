#import "Basic";
#import "System";
#import "Juice";
#import "Hash_Table";

#load "xdg.jai";
#load "manifest.jai";
#load "dependency.jai";
#load "builder.jai";

#load "commands/command.jai";
#load "commands/prepare.jai";
#load "commands/build.jai";
#load "commands/run.jai";
#load "commands/clean.jai";
#load "commands/registry.jai";

#load "dispatcher.jai";

main :: () {
    auto_release_temp();

    args := get_command_line_arguments();
    command_name := ifx args.count > 1 then args[1] else "build";
    command_args := ifx args.count > 2 then array_view(args, 2, args.count - 2) else string.[];

    driver: Build_Driver;
    driver.root_dir     = get_working_directory();
    driver.packages_dir = tprint("%1/.packages", driver.root_dir);
    driver.bin_dir      = tprint("%1/bin", driver.root_dir);

    driver.cache_dir    = tprint("%1/juice", get_cache_home());
    driver.data_dir     = tprint("%1/juice", get_data_home());
    driver.config_dir   = tprint("%1/juice", get_config_home());

    cmd_context: Command_Context;
    cmd_context.driver             = *driver;
    cmd_context.arguments          = command_args;
    cmd_context.workspace_prepared = false;

    success := dispatch_command(command_name, *cmd_context, command_args);

    if !success exit(1);
}
