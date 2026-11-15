#import "Basic";
#import "Testing";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";

#if OS == .WINDOWS {
    #import "Windows";
    #import "Windows_Utf8";
} else {
    #import "POSIX";
}

// ---------------------------------------------------------------------------
// Typed dependency resolution acceptance (spec 0087 decisions 9-15 and 26;
// ticket 0091, acceptance groups A02/A03/A04/A09/A10/A11/A12).
//
// Every case runs the real juice executable on a real temporary package with
// its own isolated XDG content-cache and state roots; every Git case runs a real
// local repository created with git. No internal object is constructed in place
// of the user's declaration.
//
// String discipline: tprint allocates in the temporary allocator, so a path kept
// across further tprint calls must be heap-copied first. The helpers below do
// that (`dr_path`, `dr_scratch`, `dr_write_file`) so a fixture cannot silently
// address a recycled buffer.
// ---------------------------------------------------------------------------

// A fresh directory per case: pick the first unused ordinal instead of deleting a
// previous tree. A recursive delete returns before the filesystem finishes on
// Windows, so reusing a name could remove the tree a case just created.
dr_scratch :: (name: string) -> string {
    root := "";
    for 1..1000000 {
        candidate := copy_string(tprint("%1/target/dep-resolution/%2-%3", otter_root(), name, it));
        if file_exists(candidate) continue;
        root = candidate;
        break;
    }
    make_directory_if_it_does_not_exist(root, recursive = true);
    return root;
}

// Delete a directory and wait until it is really gone: Windows recursive delete
// returns before the filesystem finishes, and a temporary listing race would let a
// following step observe stale content.
dr_delete_wait :: (path: string) -> bool {
    delete_directory_full(path);
    for 0..2000000 {
        if !file_exists(path) return true;
    }
    return false;
}

dr_path :: (base: string, name: string) -> string {
    return copy_string(tprint("%1/%2", base, name));
}

// Write one fixture file. The content is copied before the path is built, so a
// temporary string from the caller's expression chain cannot be recycled by the
// path formatting. Directory names must be at least two characters long: Jai's
// recursive make_directory_if_it_does_not_exist returns success without creating
// a one-character final segment (its start_index == name.count - 1 shortcut).
dr_write_file :: (directory: string, file_name: string, content: string) -> bool {
    content_copy := copy_string(content);
    path := dr_path(directory, file_name);
    make_directory_if_it_does_not_exist(directory, recursive = true);
    return write_entire_file(path, content_copy);
}

// Set one process environment variable; spawned juice children inherit it.
dr_set_process_env :: (name: string, value: string) {
    #if OS == .WINDOWS {
        wide_name, name_ok := utf8_to_wide(name,, temp);
        wide_value, value_ok := utf8_to_wide(value,, temp);
        if name_ok && value_ok SetEnvironmentVariableW(wide_name, wide_value);
    } else {
        setenv(temp_c_string(name), temp_c_string(value), 1);
    }
}

// Remove one process environment variable: a null value deletes it on Windows,
// POSIX has an explicit call.
dr_unset_process_env :: (name: string) {
    #if OS == .WINDOWS {
        wide_name, name_ok := utf8_to_wide(name,, temp);
        if name_ok SetEnvironmentVariableW(wide_name, null);
    } else {
        unsetenv(temp_c_string(name));
    }
}

// The XDG roots a case overrides, saved before the first override so the case
// can put the process back exactly as it found it.
//
// Why this exists: the whole suite runs in one process and later E2E cases
// spawn real juice children, which inherit the parent environment when they are
// spawned. A case that left XDG_CACHE_HOME/XDG_STATE_HOME pointing at its own
// scratch tree made every following child resolve into a directory that the
// next suite run deletes (or into a previous case's stale tree), so unrelated
// E2E cases failed for reasons unrelated to their own behavior. Saving and
// restoring around every case keeps this suite invisible to its neighbors.
//
// `active` makes the save idempotent: a case stores the pair once, so a second
// dr_isolate call in the same body still restores the original values.
Dr_Saved_Environment :: struct {
    active:        bool;
    cache_present: bool;
    cache_value:   string;
    state_present: bool;
    state_value:   string;
}

dr_saved_environment: Dr_Saved_Environment;

// A present-but-empty variable behaves like an absent one for the XDG contract
// (empty and relative values fall back to the platform default), so empty is
// recorded as absent and restored by deletion.
dr_environment_value :: (name: string) -> (string, bool) {
    value := get_env(name);
    return value, value != "";
}

// Point both typed roots at the case's own scratch tree. Absolute paths are
// required: a relative XDG value is a fallback with a warning and would leak the
// case into the machine's real roots. The caller pairs this with
// `defer dr_restore_env();`.
dr_isolate :: (scratch: string) {
    if !dr_saved_environment.active {
        cache_value, cache_present := dr_environment_value("XDG_CACHE_HOME");
        state_value, state_present := dr_environment_value("XDG_STATE_HOME");
        dr_saved_environment = .{
            active        = true,
            cache_present = cache_present,
            cache_value   = copy_string(cache_value),
            state_present = state_present,
            state_value   = copy_string(state_value),
        };
    }
    cache := dr_path(scratch, "xdg-cache");
    state := dr_path(scratch, "xdg-state");
    dr_set_process_env("XDG_CACHE_HOME", cache);
    dr_set_process_env("XDG_STATE_HOME", state);
    make_directory_if_it_does_not_exist(cache, recursive = true);
    make_directory_if_it_does_not_exist(state, recursive = true);
}

// Restore the environment a case found. Every case calls this through `defer`
// immediately after dr_isolate: a failing `expect` returns from the test body at
// once (the Testing contract), so only a scope defer is guaranteed to run.
// Tests execute one at a time (Testing_run) and no child is spawned after the
// defer, so one saved slot per process is enough.
dr_restore_env :: () {
    if !dr_saved_environment.active return;
    if dr_saved_environment.cache_present {
        dr_set_process_env("XDG_CACHE_HOME", dr_saved_environment.cache_value);
    } else {
        dr_unset_process_env("XDG_CACHE_HOME");
    }
    if dr_saved_environment.state_present {
        dr_set_process_env("XDG_STATE_HOME", dr_saved_environment.state_value);
    } else {
        dr_unset_process_env("XDG_STATE_HOME");
    }
    dr_saved_environment.active = false;
}

dr_package_source :: (name: string, body: string) -> string {
    body_copy := copy_string(body);
    return tprint("#import \"Juice\";\n\nPACKAGE :: Package.{\n    version = \"0.1.0\",\n    name    = \"%1\",\n%2};\n", name, body_copy);
}

// A single-export provider: the fixed auto-discovery candidate `module.jai`
// carries the export, so the declaration needs no module list.
dr_write_module_provider :: (directory: string, name: string, module_body: string) -> bool {
    declaration := dr_package_source(name, "");
    if !dr_write_file(directory, "package.jai", declaration) return false;
    return dr_write_file(directory, "module.jai", module_body);
}

dr_write_app :: (directory: string, declaration_body: string, main_source: string) -> bool {
    declaration := dr_package_source("app", declaration_body);
    if !dr_write_file(directory, "package.jai", declaration) return false;
    return dr_write_file(dr_path(directory, "src"), "main.jai", main_source);
}

dr_git :: (arguments: [] string) -> (Process_Result, string) {
    command: [..] string;
    array_add(*command, "git");
    for argument: arguments array_add(*command, argument);
    result, output, errors, timed_out := run_command(..command, capture_and_return_output = true);
    return result, trim(output);
}

dr_git_init :: (repository: string) -> bool {
    if !make_directory_if_it_does_not_exist(repository, recursive = true) return false;
    result, _ := dr_git(string.["init", "-q", "-b", "main", repository]);
    if result.exit_code != 0 return false;
    dr_git(string.["-C", repository, "config", "user.email", "juice@example.test"]);
    dr_git(string.["-C", repository, "config", "user.name", "Juice Test"]);
    return true;
}

dr_git_commit_all :: (repository: string, message: string) -> string {
    dr_git(string.["-C", repository, "add", "-A"]);
    result, _ := dr_git(string.["-C", repository, "commit", "-qm", message]);
    if result.exit_code != 0 return "";
    return copy_string(dr_git_head(repository));
}

dr_git_head :: (repository: string) -> string {
    _, head := dr_git(string.["-C", repository, "rev-parse", "HEAD"]);
    return head;
}

// The immediate subdirectories of one directory. visit_files reports files only
// unless directories are requested explicitly, and file_list uses that default,
// so a listing built on file_list silently returns no directories at all.
dr_subdirectories :: (path: string) -> [..] string {
    Collect :: struct {
        directories: [..] string;
    }
    collect: Collect;
    visitor :: (info: *File_Visit_Info, collect: *Collect) {
        if !info.is_directory return;
        array_add(*collect.directories, copy_string(info.full_name));
    }
    if !is_directory(path) return collect.directories;
    visit_files(path, false, *collect, visitor, visit_files = false, visit_directories = true, visit_symlinks = false, follow_directory_symlinks = false);
    return collect.directories;
}

// Every checkout directory under the case's content cache; the leaf names are
// commit ids.
dr_content_directories :: (scratch: string) -> [..] string {
    directories: [..] string;
    root := dr_path(scratch, "xdg-cache/juice/content");
    for source: dr_subdirectories(root) {
        for entry: dr_subdirectories(source) array_add(*directories, copy_string(entry));
    }
    return directories;
}

dr_content_has_commit :: (scratch: string, commit: string) -> bool {
    for directory: dr_content_directories(scratch) {
        if get_filename(directory) == commit return true;
    }
    return false;
}

// The recorded resolution state of the case (all context files concatenated).
dr_state_text :: (scratch: string) -> string {
    text := "";
    root := dr_path(scratch, "xdg-state/juice/contexts");
    names := file_list(root, recursive = true);
    for name: names {
        if !ends_with(name, "resolution.state") continue;
        content, ok := read_entire_file(name);
        if ok text = tprint("%\n%", text, content);
    }
    return text;
}

// Import shims are package-private: the package's own modules land in its
// target/packages, its dependency import names in target/imports. No other
// package searches either directory.
dr_has_shim :: (package_dir: string, shim_name: string) -> bool {
    name := tprint("%.jai", shim_name);
    return file_exists(dr_path(packages_dir(package_dir), name)) || file_exists(dr_path(dependency_imports_dir(package_dir), name));
}

// One build of the fixture app. A failure prints the child's own stdout/stderr
// before the caller's `expect` aborts the case: without that, a nonzero exit is
// indistinguishable between a resolver defect and a transient child failure
// (for example git or the filesystem), and the reason is lost with the test's
// scratch tree. This only adds observation; the returned code is unchanged.
dr_build_app :: (app: string) -> s32 {
    result, output, errors := run_otter_child_at(app, string.["build"]);
    if result.exit_code != 0 {
        print("[dr_build_app] build failed in %\n--- stdout ---\n%\n--- stderr ---\n%\n", app, output, errors);
    }
    return result.exit_code;
}

// The same observation for `update`: a nonzero exit there is reported with the
// child's own output so an intermittent failure names its cause instead of
// disappearing with the scratch tree.
dr_update_app :: (app: string) -> (Process_Result, string, string) {
    result, output, errors := run_otter_child_at(app, string.["update"]);
    if result.exit_code != 0 {
        print("[dr_update_app] update failed in %\n--- stdout ---\n%\n--- stderr ---\n%\n", app, output, errors);
    }
    return result, output, errors;
}

dr_run_app :: (app: string) -> (s32, string) {
    result, output, errors := run_command(dr_path(dr_path(app, "target"), "app.exe"), capture_and_return_output = true);
    if result.exit_code != 0 {
        print("[dr_run_app] run failed in %\n--- stdout ---\n%\n--- stderr ---\n%\n", app, output, errors);
    }
    return result.exit_code, output;
}

// ===========================================================================
// A02/A03 explicit sources and module selection
// ===========================================================================

// A PATH source selects the declared provider module under a consumer alias. The
// consumer imports the alias; the provider's own export name does not resolve in
// the consumer, so the alias is the only door.
dependency_resolution_path_source_alias :: () {
    scratch := dr_scratch("path-alias");
    dr_isolate(scratch);
    defer dr_restore_env();
    expect(dr_write_module_provider(dr_path(scratch, "provider"), "provider", "Provider_Value :: 7;\n"));
    app := dr_path(scratch, "app");
    expect(dr_write_app(app, "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"prov\", source = .{kind = .PATH, path = \"../provider\"}, modules = .[.{alias = \"Lib\"}]},\n    ],\n",
        "#import \"Basic\";\n#import \"Lib\";\n\nmain :: () { print(\"value=%\\n\", Provider_Value); }\n"));

    expect(dr_build_app(app) == 0);
    exit_code, run_output := dr_run_app(app);
    expect(exit_code == 0 && contains(run_output, "value=7"));

    // The provider's export name is not the consumer's import name here: a
    // direct import of the export fails, the alias is the declared door.
    expect(dr_write_file(app, "src/main.jai", "#import \"Basic\";\n#import \"provider\";\n\nmain :: () { print(\"value=%\\n\", Provider_Value); }\n"));
    alias_result, alias_output, alias_errors := run_otter_child_at(app, string.["build"]);
    expect(alias_result.exit_code != 0);
    expect(contains(alias_output, "Unable to find a module called 'provider'") || contains(alias_errors, "Unable to find a module called 'provider'"));
} @test

// A source is qualified explicitly: a directory without a package declaration
// fails even when a package of the same name exists elsewhere. There is no
// package-name search and no registry fallback.
dependency_resolution_rejects_implicit_name_search :: () {
    scratch := dr_scratch("no-name-search");
    dr_isolate(scratch);
    defer dr_restore_env();
    expect(dr_write_module_provider(dr_path(dr_path(scratch, "elsewhere"), "provider"), "provider", "Provider_Value :: 7;\n"));
    empty_source := dr_path(scratch, "not-a-package");
    expect(make_directory_if_it_does_not_exist(empty_source, recursive = true));
    app := dr_path(scratch, "app");
    expect(dr_write_app(app, "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"prov\", source = .{kind = .PATH, path = \"../not-a-package\"}, modules = .[.{}]},\n    ],\n",
        "#import \"Basic\";\n\nmain :: () { print(\"unused\\n\"); }\n"));

    result, output, errors := run_otter_child_at(app, string.["build"]);
    expect(result.exit_code != 0);
    expect(contains(output, "Dependency provider") || contains(errors, "Dependency provider"));
    expect(!dr_has_shim(app, "provider"));
} @test

// Flat module selection: an omitted modules list means the provider's single
// export; an ambiguous provider fails; an explicitly empty list is a capability
// mismatch rather than "take everything".
dependency_resolution_module_selection_rules :: () {
    scratch := dr_scratch("module-selection");
    dr_isolate(scratch);
    defer dr_restore_env();

    two := dr_path(scratch, "two-exports");
    expect(dr_write_file(two, "package.jai", dr_package_source("two_exports", "    modules = .[.{name = \"First\", entry = \"first.jai\"}, .{name = \"Second\", entry = \"second.jai\"}],\n")));
    expect(dr_write_file(two, "first.jai", "First_Value :: 1;\n"));
    expect(dr_write_file(two, "second.jai", "Second_Value :: 2;\n"));

    app := dr_path(scratch, "app");
    expect(dr_write_app(app, "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"two\", source = .{kind = .PATH, path = \"../two-exports\"}, modules = .[.{}]},\n    ],\n",
        "#import \"Basic\";\n\nmain :: () { print(\"unused\\n\"); }\n"));
    ambiguous_result, ambiguous_output, ambiguous_errors := run_otter_child_at(app, string.["build"]);
    expect(ambiguous_result.exit_code != 0);
    expect(contains(ambiguous_output, "ambiguous") || contains(ambiguous_errors, "ambiguous"));

    // Naming one export resolves it.
    expect(dr_write_file(app, "package.jai", dr_package_source("app", "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"two\", source = .{kind = .PATH, path = \"../two-exports\"}, modules = .[.{name = \"Second\"}]},\n    ],\n")));
    expect(dr_build_app(app) == 0);
    expect(dr_has_shim(app, "Second"));

    // An explicitly empty module list selects nothing; the declaration itself is
    // rejected (capability mismatch), so nothing is resolved or written.
    expect(dr_write_file(app, "package.jai", dr_package_source("app", "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"two\", source = .{kind = .PATH, path = \"../two-exports\"}, modules = .[]},\n    ],\n")));
    empty_result, empty_output, empty_errors := run_otter_child_at(app, string.["build"]);
    expect(empty_result.exit_code != 0);
    empty_combined := tprint("%\n%", empty_output, empty_errors);
    expect(contains(empty_combined, "modules cannot be empty") || contains(empty_combined, "empty module list"));
} @test

// One actual module may be selected once per consumer, whatever the reference
// name, alias or spelling; a final import name may not shadow the consumer's own
// module or a standard compiler module.
dependency_resolution_module_identity_and_name_conflicts :: () {
    scratch := dr_scratch("identity");
    dr_isolate(scratch);
    defer dr_restore_env();
    expect(dr_write_module_provider(dr_path(scratch, "provider"), "provider", "Provider_Value :: 7;\n"));
    app := dr_path(scratch, "app");
    // The package's own module is an import name of the package (story 37), so
    // the shadowing diagnostics below are checked while that name is registered
    // and resolving: one selection plus the own module compiles.
    expect(dr_write_app(app, "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    modules = .[.{name = \"AppMod\", entry = \"src/appmod.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"one\", source = .{kind = .PATH, path = \"../provider\"}, modules = .[.{alias = \"First\"}]},\n    ],\n",
        "#import \"Basic\";\n#import \"AppMod\";\n#import \"First\";\n\nmain :: () { print(\"%1 %2\\n\", App_Module, Provider_Value); }\n"));
    expect(dr_write_file(dr_path(app, "src"), "appmod.jai", "App_Module :: 1;\n"));
    expect(dr_build_app(app) == 0);
    own_exit, own_output := dr_run_app(app);
    expect(own_exit == 0 && contains(own_output, "1 7"));

    expect(dr_write_app(app, "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    modules = .[.{name = \"AppMod\", entry = \"src/appmod.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"one\", source = .{kind = .PATH, path = \"../provider\"}, modules = .[.{alias = \"First\"}]},\n        .{name = \"two\", source = .{kind = .PATH, path = \"../provider\"}, modules = .[.{alias = \"Second\"}]},\n    ],\n",
        "#import \"Basic\";\n\nmain :: () { print(\"unused\\n\"); }\n"));
    expect(dr_write_file(dr_path(app, "src"), "appmod.jai", "App_Module :: 1;\n"));

    duplicate_result, duplicate_output, duplicate_errors := run_otter_child_at(app, string.["build"]);
    expect(duplicate_result.exit_code != 0);
    expect(contains(duplicate_output, "selected more than once") || contains(duplicate_errors, "selected more than once"));

    // A dependency alias that shadows the package's own module.
    expect(dr_write_file(app, "package.jai", dr_package_source("app", "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    modules = .[.{name = \"AppMod\", entry = \"src/appmod.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"one\", source = .{kind = .PATH, path = \"../provider\"}, modules = .[.{alias = \"AppMod\"}]},\n    ],\n")));
    shadow_result, shadow_output, shadow_errors := run_otter_child_at(app, string.["build"]);
    expect(shadow_result.exit_code != 0);
    expect(contains(shadow_output, "shadows a module of the consuming package") || contains(shadow_errors, "shadows a module of the consuming package"));

    // A dependency alias that shadows a standard compiler module.
    expect(dr_write_file(app, "package.jai", dr_package_source("app", "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"one\", source = .{kind = .PATH, path = \"../provider\"}, modules = .[.{alias = \"Basic\"}]},\n    ],\n")));
    standard_result, standard_output, standard_errors := run_otter_child_at(app, string.["build"]);
    expect(standard_result.exit_code != 0);
    expect(contains(standard_output, "standard compiler module") || contains(standard_errors, "standard compiler module"));
} @test

// ===========================================================================
// A04 transitive visibility and cycles
// ===========================================================================

// A provider resolves its own dependency (Netlib -> Cipher). The consumer may use
// Netlib, and Netlib's own sources use Cipher and its own sibling export, but the
// consumer cannot import Cipher directly: provider-internal modules stay private.
dependency_resolution_transitive_visibility :: () {
    scratch := dr_scratch("transitive");
    dr_isolate(scratch);
    defer dr_restore_env();

    expect(dr_write_module_provider(dr_path(scratch, "cipher"), "cipher", "Cipher_Value :: 11;\n"));

    netlib := dr_path(scratch, "netlib");
    expect(dr_write_file(netlib, "package.jai", dr_package_source("netlib", "    modules = .[.{name = \"Netlib\", entry = \"entry.jai\"}, .{name = \"Net_Internal\", entry = \"internal.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"cipher_dep\", source = .{kind = .PATH, path = \"../cipher\"}, modules = .[.{alias = \"Cipher\"}]},\n    ],\n")));
    expect(dr_write_file(netlib, "entry.jai", "#import \"Cipher\";\n#import \"Net_Internal\";\n\nNet_Value :: Cipher_Value + Internal_Value;\n"));
    expect(dr_write_file(netlib, "internal.jai", "Internal_Value :: 5;\n"));

    app := dr_path(scratch, "app");
    expect(dr_write_app(app, "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"netlib\", source = .{kind = .PATH, path = \"../netlib\"}, modules = .[.{name = \"Netlib\"}]},\n    ],\n",
        "#import \"Basic\";\n#import \"Netlib\";\n\nmain :: () { print(\"net=%\\n\", Net_Value); }\n"));
    expect(dr_build_app(app) == 0);
    exit_code, run_output := dr_run_app(app);
    expect(exit_code == 0 && contains(run_output, "net=16"));

    // The transitive module is not a direct import of the consumer.
    expect(dr_write_file(app, "src/main.jai", "#import \"Basic\";\n#import \"Cipher\";\n\nmain :: () { print(\"%\\n\", Cipher_Value); }\n"));
    leak_result, leak_output, leak_errors := run_otter_child_at(app, string.["build"]);
    expect(leak_result.exit_code != 0);
    expect(contains(leak_output, "Unable to find a module called 'Cipher'") || contains(leak_errors, "Unable to find a module called 'Cipher'"));
} @test

// A package-level dependency cycle fails and reports the complete chain.
dependency_resolution_package_cycle_reports_chain :: () {
    scratch := dr_scratch("cycle");
    dr_isolate(scratch);
    defer dr_restore_env();

    package_a := dr_path(scratch, "alpha");
    package_b := dr_path(scratch, "beta");
    expect(dr_write_file(package_a, "package.jai", dr_package_source("alpha", "    dependencies = Dependency.[\n        .{name = \"beta\", source = .{kind = .PATH, path = \"../beta\"}, modules = .[.{}]},\n    ],\n")));
    expect(dr_write_file(package_a, "module.jai", "Alpha_Value :: 1;\n"));
    expect(dr_write_file(package_b, "package.jai", dr_package_source("beta", "    dependencies = Dependency.[\n        .{name = \"alpha\", source = .{kind = .PATH, path = \"../alpha\"}, modules = .[.{}]},\n    ],\n")));
    expect(dr_write_file(package_b, "module.jai", "Beta_Value :: 2;\n"));

    app := dr_path(scratch, "app");
    expect(dr_write_app(app, "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"alpha\", source = .{kind = .PATH, path = \"../alpha\"}, modules = .[.{}]},\n    ],\n",
        "#import \"Basic\";\n\nmain :: () { print(\"unused\\n\"); }\n"));

    result, output, errors := run_otter_child_at(app, string.["build"]);
    expect(result.exit_code != 0);
    combined := tprint("%\n%", output, errors);
    expect(contains(combined, "cycle"));
    // The complete chain: app -> alpha -> beta -> alpha.
    expect(contains(combined, "app -> alpha -> beta -> alpha"));
} @test

// ===========================================================================
// A02 workspace sources
// ===========================================================================

// A WORKSPACE source must select a member of the declaring package's own
// workspace; a same-named package outside the workspace never replaces it, and a
// non-member directory is rejected.
dependency_resolution_workspace_source_membership :: () {
    scratch := dr_scratch("workspace-source");
    dr_isolate(scratch);
    defer dr_restore_env();

    workspace := dr_path(scratch, "ws");
    expect(dr_write_module_provider(dr_path(workspace, "member"), "member", "Member_Value :: 9;\n"));
    expect(dr_write_module_provider(dr_path(dr_path(scratch, "outside"), "member"), "member", "Member_Value :: 999;\n"));

    app := dr_path(workspace, "app");
    expect(dr_write_file(workspace, "package.jai", "#import \"Juice\";\n\nPACKAGE :: Package.{\n    version = \"0.1.0\",\n    name    = \"ws_root\",\n\n    workspace = .{\n        members = string.[\"member\", \"app\"],\n    },\n};\n"));
    expect(dr_write_app(app, "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"member\", source = .{kind = .WORKSPACE}, modules = .[.{path = \"member\", alias = \"Member\"}]},\n    ],\n",
        "#import \"Basic\";\n#import \"Member\";\n\nmain :: () { print(\"member=%\\n\", Member_Value); }\n"));

    expect(dr_build_app(app) == 0);
    exit_code, run_output := dr_run_app(app);
    expect(exit_code == 0 && contains(run_output, "member=9"));

    // A directory that is not a workspace member does not qualify.
    expect(dr_write_file(app, "package.jai", dr_package_source("app", "    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n    dependencies = Dependency.[\n        .{name = \"member\", source = .{kind = .WORKSPACE}, modules = .[.{path = \"../outside/member\"}]},\n    ],\n")));
    outside_result, outside_output, outside_errors := run_otter_child_at(app, string.["build"]);
    expect(outside_result.exit_code != 0);
    outside_combined := tprint("%\n%", outside_output, outside_errors);
    expect(contains(outside_combined, "not a workspace member") || contains(outside_combined, "WORKSPACE path escapes"));
} @test

// ===========================================================================
// A04 own-module imports (story 37, decision 11)
// ===========================================================================

// A package's own declared public module is importable by its public name
// inside that package: by its program and by another of its own modules. The
// import name belongs to the package that declares it, so using the package's
// own public surface needs no dependency selection (story 37, decision 11).
dependency_resolution_own_module_public_import :: () {
    scratch := dr_scratch("own-module");
    dr_isolate(scratch);
    defer dr_restore_env();

    app := dr_path(scratch, "calcapp");
    declaration_body := "    modules = .[.{name = \"calc\", entry = \"calc.jai\"}, .{name = \"more\", entry = \"more.jai\"}],\n    executables = .[.{name = \"app\", entry = \"src/main.jai\"}],\n";
    main_source := "#import \"Basic\";\n#import \"calc\";\n#import \"more\";\n\nmain :: () { print(\"calc=%1 more=%2\\n\", Calc_Value, More_Value); }\n";
    expect(dr_write_app(app, declaration_body, main_source));
    expect(dr_write_file(app, "calc.jai", "Calc_Value :: 41;\n"));
    // A second public module of the same package references the first by its
    // public name: the same shim must resolve inside the package's own sources.
    expect(dr_write_file(app, "more.jai", "#import \"calc\";\n\nMore_Value :: Calc_Value + 1;\n"));

    expect(dr_build_app(app) == 0);
    exit_code, run_output := dr_run_app(app);
    expect(exit_code == 0 && contains(run_output, "calc=41 more=42"));
    // The own-module shims are package-private, in the package's own target/.
    expect(dr_has_shim(app, "calc") && dr_has_shim(app, "more"));

    // run compiles through the same import path.
    run_result, run_output_child, run_errors := run_otter_child_at(app, string.["run", "app"]);
    expect(expect_exit("own-module-run", run_result, 0));
    expect(output_matches("own-module-run", tprint("%\n%", run_output_child, run_errors), .["calc=41 more=42"]));
} @test

// The same rule holds for a selected workspace member, and importing names stay
// package-scoped: two members may declare the same public module name, each
// resolving to its own module, and one member's own module never becomes an
// import name of another member (decision 11).
dependency_resolution_own_module_workspace_members :: () {
    scratch := dr_scratch("own-module-workspace");
    dr_isolate(scratch);
    defer dr_restore_env();

    workspace := dr_path(scratch, "ws");
    expect(dr_write_file(workspace, "package.jai", "#import \"Juice\";\n\nPACKAGE :: Package.{\n    workspace = .{members = string.[\"members/*\"]},\n};\n"));

    // Two members, each declaring a module called `helper` with a different
    // value: importing names are package-scoped, not workspace-global.
    one := dr_path(workspace, "members/one");
    one_declaration := "#import \"Juice\";\n\nPACKAGE :: Package.{\n    version = \"1\",\n    name    = \"one\",\n    modules = .[.{name = \"helper\", entry = \"helper.jai\"}],\n    executables = .[.{name = \"one\", entry = \"src/main.jai\"}],\n};\n";
    one_main := "#import \"Basic\";\n#import \"helper\";\n\nmain :: () { print(\"one helper=%\\n\", Helper_Value); }\n";
    expect(dr_write_file(one, "package.jai", one_declaration));
    expect(dr_write_file(one, "helper.jai", "Helper_Value :: 5;\n"));
    expect(build_seam_write(dr_path(one, "src"), "main.jai", one_main));
    two := dr_path(workspace, "members/two");
    two_declaration := "#import \"Juice\";\n\nPACKAGE :: Package.{\n    version = \"1\",\n    name    = \"two\",\n    modules = .[.{name = \"helper\", entry = \"helper.jai\"}],\n    executables = .[.{name = \"two\", entry = \"src/main.jai\"}],\n};\n";
    two_main := "#import \"Basic\";\n#import \"helper\";\n\nmain :: () { print(\"two helper=%\\n\", Helper_Value); }\n";
    expect(dr_write_file(two, "package.jai", two_declaration));
    expect(dr_write_file(two, "helper.jai", "Helper_Value :: 500;\n"));
    expect(build_seam_write(dr_path(two, "src"), "main.jai", two_main));

    // Both members declare `helper`; each build resolves its own, so the shared
    // command never maps one import name to two different modules.
    workspace_result, workspace_output, workspace_errors := run_otter_child_at(workspace, string.["build", "--workspace"]);
    workspace_combined := tprint("%\n%", workspace_output, workspace_errors);
    expect(expect_exit("own-module-workspace-build", workspace_result, 0));
    expect(output_matches("own-module-workspace-build", workspace_combined, .["Compiling Target 'one'", "Compiling Target 'two'"]));
    expect(output_matches("own-module-workspace-build", workspace_combined, .["two different modules"], want = false));
    // Each member's own-module shims live in that member's own target/.
    expect(dr_has_shim(dr_path(workspace, "members/one"), "helper"));
    expect(dr_has_shim(dr_path(workspace, "members/two"), "helper"));

    // Each program read its own member's module.
    one_result, one_output, one_errors := run_otter_child_at(workspace, string.["run", "-p", "one"]);
    expect(expect_exit("own-module-workspace-run-one", one_result, 0));
    expect(output_matches("own-module-workspace-run-one", tprint("%\n%", one_output, one_errors), .["one helper=5"]));
    two_result, two_output, two_errors := run_otter_child_at(workspace, string.["run", "-p", "two"]);
    expect(expect_exit("own-module-workspace-run-two", two_result, 0));
    expect(output_matches("own-module-workspace-run-two", tprint("%\n%", two_output, two_errors), .["two helper=500"]));

    // Another member's own module is not an import name of this member.
    sibling_consumer := "#import \"Basic\";\n#import \"sibling_only\";\n\nmain :: () { print(\"%\\n\", Sibling_Value); }\n";
    expect(build_seam_write(dr_path(workspace, "members/one/src"), "main.jai", sibling_consumer));
    expect(dr_write_file(dr_path(workspace, "members/two"), "package.jai", "#import \"Juice\";\n\nPACKAGE :: Package.{\n    version = \"1\",\n    name    = \"two\",\n    modules = .[.{name = \"helper\", entry = \"helper.jai\"}, .{name = \"sibling_only\", entry = \"sibling_only.jai\"}],\n    executables = .[.{name = \"two\", entry = \"src/main.jai\"}],\n};\n"));
    expect(dr_write_file(dr_path(workspace, "members/two"), "sibling_only.jai", "Sibling_Value :: 1;\n"));
    sibling_result, sibling_output, sibling_errors := run_otter_child_at(workspace, string.["build", "-p", "one"]);
    expect(sibling_result.exit_code != 0);
    sibling_combined := tprint("%\n%", sibling_output, sibling_errors);
    expect(contains(sibling_combined, "Unable to find a module called 'sibling_only'"));
} @test

// The test command compiles the package's test program through the same import
// path, so a test source uses the package's own public modules by name too.
dependency_resolution_own_module_in_test_source :: () {
    scratch := dr_scratch("own-module-test");
    dr_isolate(scratch);
    defer dr_restore_env();

    tested := dr_path(scratch, "tested");
    // The module entry lives under the package's own modules/ directory: the
    // test scan #loads every package file outside root target/, modules/ and
    // tests/data/, so a module the test program also imports must not sit in
    // that scanned set (the same rule any #load of a package file obeys).
    expect(dr_write_file(tested, "package.jai", dr_package_source("tested", "    modules = .[.{name = \"subject\", entry = \"modules/subject.jai\"}],\n")));
    expect(build_seam_write(tested, "modules/subject.jai", "Subject_Value :: 3;\n"));
    expect(build_seam_write(tested, "tests/subject_test.jai", "#import \"Testing\";\n#import \"subject\";\n\nown_module_bound :: () {\n    expect(Subject_Value == 3);\n} @test\n"));

    result, output, errors := run_otter_child_at(tested, string.["test"]);
    combined := tprint("%\n%", output, errors);
    expect(expect_exit("own-module-test", result, 0));
    expect(output_matches("own-module-test", combined, .["[test] own_module_bound", "1 passed, 0 failed"]));

    // The same holds for a selected workspace member, whose test program is
    // compiled with that member as the package being tested.
    workspace := dr_path(scratch, "ws");
    workspace_declaration := "#import \"Juice\";\n\nPACKAGE :: Package.{\n    workspace = .{members = string.[\"members/*\"]},\n};\n";
    expect(dr_write_file(workspace, "package.jai", workspace_declaration));
    member := dr_path(workspace, "members/tested");
    member_declaration := dr_package_source("member_tested", "    modules = .[.{name = \"subject\", entry = \"modules/subject.jai\"}],\n");
    expect(build_seam_write(member, "package.jai", member_declaration));
    expect(build_seam_write(member, "modules/subject.jai", "Subject_Value :: 7;\n"));
    member_test := "#import \"Testing\";\n#import \"subject\";\n\nmember_own_module_bound :: () {\n    expect(Subject_Value == 7);\n} @test\n";
    expect(build_seam_write(member, "tests/member_own_test.jai", member_test));

    member_result, member_output, member_errors := run_otter_child_at(workspace, string.["test", "-p", "member_tested"]);
    member_combined := tprint("%\n%", member_output, member_errors);
    expect(expect_exit("own-module-member-test", member_result, 0));
    expect(output_matches("own-module-member-test", member_combined, .["[test] member_own_module_bound", "1 passed, 0 failed"]));
} @test
