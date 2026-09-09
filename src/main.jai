#import "Basic";
#import "System";

#import "Juice";

#load "xdg.jai";
#load "path_safety.jai";
#load "manifest.jai";
#load "workspace.jai";
#load "target.jai";
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
    command := ifx args.count > 1 then args[1] else "build";
    command_arguments: [..] string;
    if args.count > 2 {
        for i: 2..args.count-1 array_add(*command_arguments, args[i]);
    }

    driver: Build_Driver;
    driver.root_dir     = get_working_directory();
    driver.packages_dir = tprint("%1/.packages", driver.root_dir);

    // 初始化 XDG 路径
    driver.cache_dir    = tprint("%1/juice", get_cache_home());
    driver.data_dir     = tprint("%1/juice", get_data_home());
    driver.config_dir   = tprint("%1/juice", get_config_home());

    ctx: Command_Context;
    ctx.driver = *driver;
    ctx.arguments = command_arguments;

    if !dispatch_command(command, *ctx, command_arguments) exit(1);
}
