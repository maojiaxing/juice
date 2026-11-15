#import "Basic";
#import "Testing";
#import "File_Utilities";
#import "Thread"(LOAD_THREAD_GROUP = false);

#if OS == .WINDOWS {
    declaration_test_kernel32 :: #system_library "kernel32";
    SetEnvironmentVariableW :: (name: *u16, value: *u16) -> s32 #foreign declaration_test_kernel32;
}

test "Package-relative paths normalize internal parent segments" {
    result := normalize_package_relative_path("src/../module.jai");
    expect(result.success);
    expect(result.path == "module.jai");
}

test "Package-relative paths reject escapes and volume-relative inputs" {
    expect(!normalize_package_relative_path("../outside.jai").success);
    expect(!normalize_package_relative_path("src/../../outside.jai").success);
    expect(!normalize_package_relative_path("C:outside.jai").success);
    expect(!normalize_package_relative_path("//server/share/file.jai").success);
}

test "Path safety rejects a linked ancestor, not just a linked leaf" {
    scratch := otter_scratch("declaration-path-link");
    delete_directory_full(scratch);
    defer delete_directory_full(scratch);
    real := tprint("%1/real/child", scratch);
    expect(make_directory_if_it_does_not_exist(real, recursive = true));
    junction := tprint("%1/alias", scratch);
    #if OS == .WINDOWS {
        link_ok := make_test_link(junction, tprint("%1/real", scratch), true, true);
    } else {
        link_ok := run_command("ln", "-s", tprint("%1/real", scratch), junction).exit_code == 0;
    }
    if !link_ok {
        print("SKIP: symbolic link creation unavailable\\n");
        return;
    }
    expect(!path_chain_is_link_free(tprint("%1/child", junction)));
    expect(path_chain_is_link_free(real));
}

test "Typed cache and state roots honor XDG and platform defaults" {
    // Verify the public return types without calling getters against the user environment.
    cache_getter: () -> Content_Cache_Root_Result = get_juice_content_cache_root;
    state_getter: () -> Resolution_State_Root_Result = get_juice_resolution_state_root;
    scratch := otter_scratch("declaration-xdg-roots");
    delete_directory_full(scratch);
    defer delete_directory_full(scratch);
    expect(make_directory_if_it_does_not_exist(scratch, recursive = true));
    xdg := tprint("%1/custom-xdg", scratch);
    cache := resolve_juice_content_cache_root(xdg, "", "");
    state := resolve_juice_resolution_state_root(tprint("%1/state-xdg", scratch), "", "");
    expect(cache.success && cache.path == tprint("%1/juice", xdg));
    expect(state.success && state.path == tprint("%1/juice", tprint("%1/state-xdg", scratch)));
    relative_cache := resolve_juice_content_cache_root("relative-cache", tprint("%1/local", scratch), tprint("%1/home", scratch));
    relative_state := resolve_juice_resolution_state_root("relative-state", tprint("%1/local", scratch), tprint("%1/home", scratch));
    expect(relative_cache.success && relative_cache.warning && relative_cache.used_fallback);
    expect(relative_state.success && relative_state.warning && relative_state.used_fallback);
    #if OS == .WINDOWS {
        expect(relative_cache.path == tprint("%1/juice/cache", tprint("%1/local", scratch)));
        expect(relative_state.path == tprint("%1/juice/state", tprint("%1/local", scratch)));
    } else {
        expect(relative_cache.path == tprint("%1/.cache/juice", tprint("%1/home", scratch)));
        expect(relative_state.path == tprint("%1/.local/state/juice", tprint("%1/home", scratch)));
    }
    expect(!resolve_juice_content_cache_root("relative", "", "").success);
    expect(!resolve_juice_resolution_state_root("relative", "", "").success);

    blocked := tprint("%1/blocked", scratch);
    expect(write_entire_file(blocked, "regular file"));
    blocked_path := tprint("%1/child", blocked);
    blocked_result := xdg_create_root(.{path = blocked_path, success = true, warning = true});
    expect(!blocked_result.success);
    expect(blocked_result.path == blocked_path && blocked_result.warning && !blocked_result.used_fallback);
    blocked_content, read_ok := read_entire_file(blocked);
    expect(read_ok && blocked_content == "regular file");
}

test "XDG absolute roots require a real volume or complete UNC share" {
    expect(xdg_join("/", "juice") == "/juice");
    #if OS == .WINDOWS {
        expect(xdg_path_is_absolute("C:/cache"));
        expect(xdg_path_is_absolute("z:\\cache"));
        expect(xdg_path_is_absolute("//server/share"));
        expect(xdg_path_is_absolute("//server/share/cache"));
        expect(!xdg_path_is_absolute("1:/cache"));
        expect(!xdg_path_is_absolute("_:/cache"));
        expect(!xdg_path_is_absolute("C:cache"));
        expect(!xdg_path_is_absolute("/cache"));
        expect(!xdg_path_is_absolute("//"));
        expect(!xdg_path_is_absolute("//server"));
        expect(!xdg_path_is_absolute("//server/"));
        expect(!xdg_path_is_absolute("///share"));
    } else {
        expect(xdg_path_is_absolute("/cache"));
        expect(!xdg_path_is_absolute("C:/cache"));
    }
}

test "Windows environment paths retain Unicode across size changes" {
    #if OS == .WINDOWS {
        name := tprint("JUICE_TEST_DECLARATION_UNICODE_%1", GetCurrentProcessId());
        wide_name := utf8_to_wide(name,, temp);
        expect(get_env(name) == "");
        defer SetEnvironmentVariableW(wide_name, null);
        for value: string.["C:/缓存/状态/𐐀", "C:/短", "C:/更长的缓存路径/状态目录/𐐨/juice"] {
            expect(SetEnvironmentVariableW(wide_name, utf8_to_wide(value,, temp)) != 0);
            expect(get_env(name) == value);
        }
        Environment_Worker :: struct {
            thread: Thread;
            name: *u16;
            short_value: *u16;
            long_value: *u16;
            success: bool = true;
        }
        resize_environment :: (thread: *Thread) -> s64 {
            worker := cast(*Environment_Worker) thread;
            for 0..999 {
                if SetEnvironmentVariableW(worker.name, worker.short_value) == 0 worker.success = false;
                if SetEnvironmentVariableW(worker.name, worker.long_value) == 0 worker.success = false;
            }
            return 0;
        }
        short_value := "C:/短";
        long_value := "C:/更长的缓存路径/状态目录/𐐨/juice";
        worker: Environment_Worker;
        worker.name = wide_name;
        worker.short_value = utf8_to_wide(short_value,, temp);
        worker.long_value = utf8_to_wide(long_value,, temp);
        expect(thread_init(*worker.thread, resize_environment));
        thread_start(*worker.thread);
        valid := true;
        for 0..999 {
            value := get_env(name);
            if value != short_value && value != long_value valid = false;
        }
        thread_is_done(*worker.thread, -1);
        thread_deinit(*worker.thread);
        expect(worker.success);
        expect(valid);
        expect(SetEnvironmentVariableW(wide_name, null) != 0);
        expect(get_env(name) == "");
    } else {
        print("SKIP: Windows wide environment API is platform-specific\n");
    }
}

test "Concurrent write probes are independent and never reuse a fixed name" {
    scratch := otter_scratch("declaration-xdg-probes");
    delete_directory_full(scratch);
    defer delete_directory_full(scratch);
    expect(make_directory_if_it_does_not_exist(scratch, recursive = true));
    fixed_probe := tprint("%1/.juice-write-probe", scratch);
    expect(write_entire_file(fixed_probe, "user-owned content"));
    Probe_Worker :: struct { thread: Thread; root: string; success: bool = true; };
    probe_worker :: (thread: *Thread) -> s64 {
        worker := cast(*Probe_Worker) thread;
        for 0..31 {
            result := xdg_create_root(.{path = worker.root, success = true});
            if !result.success || result.path != worker.root worker.success = false;
        }
        return 0;
    }
    workers: [8] Probe_Worker;
    for i: 0..workers.count-1 {
        workers[i].root = scratch;
        expect(thread_init(*workers[i].thread, probe_worker));
        thread_start(*workers[i].thread);
    }
    for i: 0..workers.count-1 {
        thread_is_done(*workers[i].thread, -1);
        thread_deinit(*workers[i].thread);
    }
    for worker: workers expect(worker.success);
    files := file_list(scratch);
    expect(files.count == 1 && paths_equal(files[0], fixed_probe));
    content, read_ok := read_entire_file(fixed_probe);
    expect(read_ok && content == "user-owned content");
}

test "Declaration names use their ASCII grammar and compare without rewriting" {
    expect(package_name_is_valid("alpha-beta.2_name"));
    expect(package_name_is_valid("CON"));
    expect(!package_name_is_valid("-alpha"));
    expect(!package_name_is_valid("alpha/beta"));
    expect(declaration_identifier_is_valid("_module2"));
    expect(!declaration_identifier_is_valid("module-name"));
    expect(ascii_names_equal("Export_Name", "export_name"));
    expect(!ascii_names_equal("Export", "exports"));

    upper_unicode_bytes: [2] u8;
    upper_unicode_bytes[0] = 0xc3;
    upper_unicode_bytes[1] = 0x84;
    lower_unicode_bytes: [2] u8;
    lower_unicode_bytes[0] = 0xc3;
    lower_unicode_bytes[1] = 0xa4;
    expect(!ascii_names_equal(to_string(upper_unicode_bytes.data, 2), to_string(lower_unicode_bytes.data, 2)));
}
