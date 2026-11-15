#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

#if OS == .WINDOWS {
    #import "Windows";
    #import "Windows_Utf8";

    xdg_probe_kernel32 :: #system_library "kernel32";
    GetEnvironmentVariableW :: (name: *u16, buffer: *u16, capacity: u32) -> u32 #foreign xdg_probe_kernel32;
    GetTickCount64 :: () -> u64 #foreign xdg_probe_kernel32;

    get_env :: (name: string) -> string {
        wide_name, name_ok := utf8_to_wide(name,, temp);
        if !name_ok return "";
        capacity := GetEnvironmentVariableW(wide_name, null, 0);
        while capacity > 0 {
            buffer := cast(*u16) talloc(cast(s64) capacity * size_of(u16));
            length := GetEnvironmentVariableW(wide_name, buffer, capacity);
            if length == 0 return "";
            // A concurrent growth returns the required capacity, including
            // the terminator, rather than a readable string length.
            if length >= capacity {
                capacity = length;
                continue;
            }
            utf8_byte_count := WideCharToMultiByte(CP_UTF8, 0, buffer, cast(s32) length, null, 0, null, null);
            if utf8_byte_count <= 0 return "";
            value: string;
            value.data = cast(*u8) talloc(utf8_byte_count + 1);
            value.count = utf8_byte_count;
            written := WideCharToMultiByte(CP_UTF8, 0, buffer, cast(s32) length, value.data, utf8_byte_count, null, null);
            if written != utf8_byte_count return "";
            value.data[value.count] = 0;
            return value;
        }
        return "";
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
        if starts_with(normalized, "//") {
            server_end := find_index_from_left(slice(normalized, 2, normalized.count - 2), "/");
            if server_end <= 0 return false;
            share_start := server_end + 3;
            if share_start >= normalized.count || normalized[share_start] == #char "/" return false;
            return true;
        }
        return normalized.count >= 3 && ascii_is_letter(normalized[0]) && normalized[1] == #char ":" && normalized[2] == #char "/";
    } else {
        return normalized[0] == #char "/";
    }
}

xdg_join :: (root: string, suffix: string) -> string {
    normalized := path_slashes(root);
    while normalized.count > 1 && normalized[normalized.count - 1] == #char "/" normalized.count -= 1;
    if normalized == "/" return tprint("/%1", suffix);
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

xdg_create_write_probe :: (root: string) -> bool {
    #if OS == .WINDOWS {
        for attempt: 0..64 {
            probe := tprint("%1/.juice-write-probe-%2-%3-%4", root, GetCurrentProcessId(), GetTickCount64(), attempt);
            wide_probe, converted := utf8_to_wide(probe,, temp);
            if !converted return false;
            handle := CreateFileW(wide_probe, GENERIC_WRITE, 0, null, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, null);
            if handle == INVALID_HANDLE_VALUE continue;
            content := "juice";
            written: u32;
            write_ok := WriteFile(handle, content.data, cast(u32) content.count, *written, null) != 0 && written == content.count;
            close_ok := CloseHandle(handle) != 0;
            delete_ok := DeleteFileW(wide_probe) != 0;
            return write_ok && close_ok && delete_ok;
        }
        return false;
    } else {
        #import "POSIX";
        probe_template := temp_c_string(tprint("%1/.juice-write-probe-XXXXXX", root));
        descriptor := mkstemp(probe_template);
        if descriptor < 0 return false;
        content := "juice";
        bytes_written := write(descriptor, content.data, cast(u64) content.count);
        close_ok := close(descriptor) == 0;
        delete_ok := unlink(probe_template) == 0;
        return bytes_written == content.count && close_ok && delete_ok;
    }
}

xdg_create_root :: (result: XDG_Directory_Result) -> XDG_Directory_Result {
    if !result.success return result;
    if !path_chain_is_link_free(result.path) return .{path = result.path, warning = result.warning, used_fallback = result.used_fallback};
    if !make_directory_if_it_does_not_exist(result.path, recursive = true) return .{path = result.path, warning = result.warning, used_fallback = result.used_fallback};
    if !xdg_create_write_probe(result.path) return .{path = result.path, warning = result.warning, used_fallback = result.used_fallback};
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

