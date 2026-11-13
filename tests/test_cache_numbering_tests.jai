#import "Basic";
#import "Testing";

// Exercise the real cache writes across edits to an earlier file. The later
// file's source stays unchanged while its generated test number moves.
transpile_cache_renumbers_unchanged_files :: () {
    root := otter_scratch("test-cache-numbering");
    expect(delete_directory_full(root));
    expect(make_directory_if_it_does_not_exist(root, recursive = true));
    defer delete_directory_full(root);

    first_path := path_slashes(tprint("%1/first.jai", root));
    second_path := path_slashes(tprint("%1/second.jai", root));
    expect(write_entire_file(second_path, "test \"later\" {\n}\n"));
    files := Scan_File.[
        .{rel_path = "first.jai", abs_path = first_path},
        .{rel_path = "second.jai", abs_path = second_path},
    ];
    prepared := test_command_prepared(root);
    first_sources := string.[
        "test \"first\" {\n}\n",
        "test \"first\" {\n}\ntest \"added\" {\n}\n",
        "test \"first\" {\n}\n",
    ];
    expected_names := string.["juice_test_2", "juice_test_3", "juice_test_2"];
    original_cache_path: string;

    for first_source, index: first_sources {
        expect(write_entire_file(first_path, first_source));
        stage: Test_Transpile_Stage;
        stage.prepared = *prepared;
        stage.files = files;
        expect(test_transpile_front(*stage));
        expect(stage.view_paths.count == 2);

        cached_view, read_ok := read_entire_file(stage.view_paths[1]);
        expect(read_ok);
        expect(find_index_from_left(cached_view, tprint("%1 ::", expected_names[index])) >= 0,
               "the cached view must use the current global test number");
        if index == 0 original_cache_path = copy_string(stage.view_paths[1]);
        if index == 1 expect(stage.view_paths[1] != original_cache_path);
        if index == 2 expect(stage.view_paths[1] == original_cache_path);
    }
} @test
