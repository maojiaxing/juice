#import "Basic";
#import "File";
#import "File_Utilities";

// Clean consumes loaded declarations without asking for artifact plans. These
// cases pin validation at the loader boundary, before any deletion occurs.
declaration_loader_rejects_invalid_name_before_clean :: () {
    root := otter_scratch("schema-loader-invalid-name");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(tprint("%/target", root), recursive = true));
    expect(write_entire_file(tprint("%/target/keep.txt", root), "preserve"));
    expect(write_entire_file(tprint("%/package.jai", root), "#import \"Juice\";\nPACKAGE :: Package.{name = \"bad name\", version = \"1\", modules = .[], executables = .[]};\n"));
    result, output, errors := run_otter_child_at(root, string.["clean"]);
    expect(result.exit_code != 0);
    expect(contains(output, "Package name must match"));
    expect(file_exists(tprint("%/target/keep.txt", root)));
} @test

declaration_loader_rejects_invalid_entry_before_clean :: () {
    root := otter_scratch("schema-loader-invalid-entry");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(tprint("%/target", root), recursive = true));
    expect(write_entire_file(tprint("%/target/keep.txt", root), "preserve"));
    expect(write_entire_file(tprint("%/package.jai", root), "#import \"Juice\";\nPACKAGE :: Package.{name = \"entry\", version = \"1\", modules = .[.{name = \"entry\", entry = \"../outside.jai\"}], executables = .[]};\n"));
    result, output, errors := run_otter_child_at(root, string.["clean"]);
    expect(result.exit_code != 0);
    expect(contains(output, "Product entry must be a package-relative .jai path."));
    expect(file_exists(tprint("%/target/keep.txt", root)));
} @test

declaration_loader_rejects_invalid_default_run_before_clean :: () {
    root := otter_scratch("schema-loader-invalid-default-run");
    delete_directory_full(root);
    defer delete_directory_full(root);
    expect(make_directory_if_it_does_not_exist(tprint("%/target", root), recursive = true));
    expect(write_entire_file(tprint("%/target/keep.txt", root), "preserve"));
    expect(write_entire_file(tprint("%/package.jai", root), "#import \"Juice\";\nPACKAGE :: Package.{name = \"default_run\", version = \"1\", modules = .[], executables = .[], default_run = \"missing\"};\n"));
    result, output, errors := run_otter_child_at(root, string.["clean"]);
    expect(result.exit_code != 0);
    expect(contains(output, "default_run must name a declared executable."));
    expect(file_exists(tprint("%/target/keep.txt", root)));
} @test
