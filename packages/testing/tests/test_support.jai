#import "Basic";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";

// No root test support or juice implementation sources are used here. The
// generated ordinary module shim gives every child import the member entry.
testing_source_quote :: (value: string) -> string {
    escaped := replace(value, "\\", "/");
    escaped = replace(escaped, "\"", "\\\"");
    return tprint("\"%\"", escaped);
}

run_testing_behavior_child :: () -> (Process_Result, string, string) {
    package_root := replace(JUICE_TEST_PACKAGE_ROOT, "\\", "/");
    scratch := tprint("%/target/tests/testing-behavior", package_root);
    if is_directory(scratch) delete_directory(scratch);
    if !make_directory_if_it_does_not_exist(scratch, recursive = true) {
        return .{}, "", "could not create behavior test directory";
    }
    defer delete_directory(scratch);
    fixture_path := tprint("%/tests/data/scenarios.jai", package_root);
    module_source := tprint("%/src/module.jai", package_root);
    shim := tprint("#load %;\n", testing_source_quote(module_source));
    if !write_entire_file(tprint("%/Testing.jai", scratch), shim) {
        return .{}, "", "could not write child Testing shim";
    }
    driver_source := tprint(
        "#import \"Basic\";\n#import \"Compiler\";\n#import \"Testing\";\n#load %1;\n#run {\n    set_build_options_dc(.{do_output = false});\n    exercise_testing(%1);\n}\nmain :: () {}\n",
        testing_source_quote(fixture_path));
    driver_path := tprint("%/driver.jai", scratch);
    if !write_entire_file(driver_path, driver_source) {
        return .{}, "", "could not write child driver";
    }
    result, output, errors, _ := run_command("jai", driver_path, "-import_dir", scratch, "-quiet",
        working_directory = scratch, capture_and_return_output = true);
    return result, replace(output, "\r\n", "\n"), errors;
}

// Find the actual macro invocation, including its exact 1-based column.
// Keeping this outside Testing means the test does not reuse its mapping code.
testing_fixture_coordinates :: (source: string, needle: string) -> (line: s64, column: s64) {
    position := find_index_from_left(source, needle);
    if position < 0 return 0, 0;
    line := 1;
    column := 1;
    for index: 0..position-1 {
        if source[index] == #char "\n" {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    return line, column;
}
