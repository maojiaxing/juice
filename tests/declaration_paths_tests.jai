#import "Basic";
#import "Testing";
#import "File_Utilities";

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
    if !make_test_link(junction, tprint("%1/real", scratch), true, true) {
        print("SKIP: mklink unavailable (needs developer mode or elevation)\n");
        return;
    }
    expect(!path_chain_is_link_free(tprint("%1/child", junction)));
    expect(path_chain_is_link_free(real));
}

test "Typed cache and state roots honor XDG and platform defaults" {
    scratch := otter_scratch("declaration-xdg-roots");
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
    blocked_result := xdg_create_root(.{path = tprint("%1/child", blocked), success = true});
    expect(!blocked_result.success);
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
