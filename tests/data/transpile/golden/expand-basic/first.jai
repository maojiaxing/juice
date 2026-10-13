#import "Basic";
#import "Compiler";

#run {
    set_build_options_dc(.{do_output = false});
    workspace := compiler_create_workspace("Juice Test Program");
    if !workspace return;
    options := get_build_options(workspace);
    options.output_type = .NO_OUTPUT;
    options.intermediate_path = "<abs>/target";
    import_paths: [..] string;
    array_add(*import_paths, .. options.import_path);
    array_add(*import_paths, "<abs>/modules");
    options.import_path = import_paths;
    set_build_options(options, workspace);
    compiler_begin_intercept(workspace);
    add_build_file("<abs>/target/transpile/driver.jai", workspace);
    while true {
        msg := compiler_wait_for_message();
        if !msg continue;
        if msg.workspace == workspace {
            if msg.kind == {
                case .ERROR;
                case .COMPLETE;
                    break;
            }
        }
    }
    compiler_end_intercept(workspace);
}
