#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

#if OS == .WINDOWS {
    #import "Windows";

    kernel32 :: #system_library "kernel32";
    GetEnvironmentVariableA :: (lpName: *u8, lpBuffer: *u8, nSize: u32) -> u32 #foreign kernel32;

    get_env :: (name: string) -> string {
        c_name := temp_c_string(name);
        needed := GetEnvironmentVariableA(c_name, null, 0);
        if needed == 0 return "";

        buf := cast(*u8) talloc(needed + 1);
        len := GetEnvironmentVariableA(c_name, buf, needed + 1);
        return ifx len == 0 then "" else to_string(buf, len);
    }
} else {
    #import "POSIX";

    get_env :: (name: string) -> string {
        c_name := temp_c_string(name);
        c_val := getenv(c_name);
        return ifx !c_val then "" else to_string(c_val);
    }
}

// A resolved, typed root. warning is true only when an XDG variable was
// present but relative and the platform default was selected instead.
XDG_Directory_Result :: struct {
    path:          string;
    success:       bool;
    warning:       bool;
    used_fallback: bool;
}

Content_Cache_Root_Result :: struct {
    path:          string;
    success:       bool;
    warning:       bool;
    used_fallback: bool;
}

Resolution_State_Root_Result :: struct {
    path:          string;
    success:       bool;
    warning:       bool;
    used_fallback: bool;
}

xdg_path_is_absolute :: (path: string) -> bool {
    if path == "" return false;
    normalized := path_slashes(path);
    #if OS == .WINDOWS {
        if starts_with(normalized, "//") return true;
        return normalized.count >= 3 && normalized[1] == #char ":" && normalized[2] == #char "/";
    } else {
        return normalized[0] == #char "/";
    }
}

xdg_join :: (root: string, suffix: string) -> string {
    normalized := path_slashes(root);
    while normalized.count > 1 && normalized[normalized.count - 1] == #char "/" normalized.count -= 1;
    return tprint("%1/%2", normalized, suffix);
}

resolve_juice_content_cache_root :: (xdg_cache_home: string, local_app_data: string, home: string) -> XDG_Directory_Result {
    if xdg_cache_home != "" && xdg_path_is_absolute(xdg_cache_home) {
        return .{path = xdg_join(xdg_cache_home, "juice"), success = true};
    }

    result: XDG_Directory_Result;
    result.warning = xdg_cache_home != "";
    result.used_fallback = true;
    #if OS == .WINDOWS {
        if !xdg_path_is_absolute(local_app_data) return result;
        result.path = xdg_join(local_app_data, "juice/cache");
    } else {
        if !xdg_path_is_absolute(home) return result;
        result.path = xdg_join(home, ".cache/juice");
    }
    result.success = true;
    return result;
}

resolve_juice_resolution_state_root :: (xdg_state_home: string, local_app_data: string, home: string) -> XDG_Directory_Result {
    if xdg_state_home != "" && xdg_path_is_absolute(xdg_state_home) {
        return .{path = xdg_join(xdg_state_home, "juice"), success = true};
    }

    result: XDG_Directory_Result;
    result.warning = xdg_state_home != "";
    result.used_fallback = true;
    #if OS == .WINDOWS {
        if !xdg_path_is_absolute(local_app_data) return result;
        result.path = xdg_join(local_app_data, "juice/state");
    } else {
        if !xdg_path_is_absolute(home) return result;
        result.path = xdg_join(home, ".local/state/juice");
    }
    result.success = true;
    return result;
}

xdg_create_root :: (result: XDG_Directory_Result) -> XDG_Directory_Result {
    if !result.success return result;
    if !path_chain_is_link_free(result.path) return .{path = result.path, warning = result.warning, used_fallback = result.used_fallback};
    if !make_directory_if_it_does_not_exist(result.path, recursive = true) return .{path = result.path, warning = result.warning, used_fallback = result.used_fallback};

    // An existing configured root must be usable, not merely present. Never
    // overwrite a pre-existing probe name and never switch to another root.
    probe := tprint("%1/.juice-write-probe", result.path);
    if file_exists(probe) return .{path = result.path, warning = result.warning, used_fallback = result.used_fallback};
    if !write_entire_file(probe, "juice") return .{path = result.path, warning = result.warning, used_fallback = result.used_fallback};
    if !file_delete(probe) return .{path = result.path, warning = result.warning, used_fallback = result.used_fallback};
    if !path_chain_is_link_free(result.path) return .{path = result.path, warning = result.warning, used_fallback = result.used_fallback};
    return result;
}

// These are the only new filesystem-facing roots. They create the selected
// directory and never switch to cwd, a system root or a temporary directory.
get_juice_content_cache_root :: () -> Content_Cache_Root_Result {
    #if OS == .WINDOWS {
        root := xdg_create_root(resolve_juice_content_cache_root(get_env("XDG_CACHE_HOME"), get_env("LOCALAPPDATA"), get_env("HOME")));
    } else {
        root := xdg_create_root(resolve_juice_content_cache_root(get_env("XDG_CACHE_HOME"), "", get_env("HOME")));
    }
    return .{path = root.path, success = root.success, warning = root.warning, used_fallback = root.used_fallback};
}

get_juice_resolution_state_root :: () -> Resolution_State_Root_Result {
    #if OS == .WINDOWS {
        root := xdg_create_root(resolve_juice_resolution_state_root(get_env("XDG_STATE_HOME"), get_env("LOCALAPPDATA"), get_env("HOME")));
    } else {
        root := xdg_create_root(resolve_juice_resolution_state_root(get_env("XDG_STATE_HOME"), "", get_env("HOME")));
    }
    return .{path = root.path, success = root.success, warning = root.warning, used_fallback = root.used_fallback};
}

get_user_home_directory :: () -> string {
    #if OS == .WINDOWS {
        user_profile := get_env("USERPROFILE");
        if user_profile && user_profile != "" return user_profile;
        return "C:/";
    } else {
        home := get_env("HOME");
        if home && home != "" return home;
        return "/tmp";
    }
}

// Legacy base-home helper. Existing callers append their own /juice suffix;
// new code must use the typed content/state root getters above.
get_cache_home :: () -> string {
    #if OS == .WINDOWS {
        local_app_data := get_env("LOCALAPPDATA");
        if local_app_data && local_app_data != "" return local_app_data;
        return tprint("%1/AppData/Local", get_user_home_directory());
    } else {
        cache_home := get_env("XDG_CACHE_HOME");
        if cache_home && cache_home != "" return cache_home;
        return tprint("%1/.cache", get_user_home_directory());
    }
}
