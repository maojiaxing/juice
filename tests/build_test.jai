#import "Basic";
#import "Compiler";
#import "File";

#run {
    set_build_options_dc(.{do_output = false});

    workspace := compiler_create_workspace("Dispatcher Tests");
    if !workspace return;

    options := get_build_options(workspace);
    options.output_executable_name = "test_dispatcher";
    options.output_path = "../bin";

    make_directory_if_it_does_not_exist(options.output_path);

    import_paths: [..] string;
    array_add(*import_paths, .. options.import_path);
    array_add(*import_paths, "../modules");
    options.import_path = import_paths;

    set_optimization(*options, .DEBUG);
    set_build_options(options, workspace);

    compiler_begin_intercept(workspace);
    add_build_file("test_dispatcher.jai", workspace);

    has_errors := false;
    while true {
        msg := compiler_wait_for_message();
        if !msg continue;

        if msg.workspace == workspace {
            if msg.kind == {
                case .ERROR;
                    has_errors = true;
                case .COMPLETE;
                    break;
            }
        }
    }

    compiler_end_intercept(workspace);

    if !has_errors {
        print("[Test Build] ✅ Test build succeeded! Binary -> %/%\n",
              options.output_path, options.output_executable_name);
    } else {
        print("[Test Build] ❌ Test build failed.\n");
    }
}
