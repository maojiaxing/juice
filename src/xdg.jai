#import "Basic";
#import "String";

#if OS == .WINDOWS {
    #import "Windows";

    kernel32 :: #system_library "kernel32";
    GetEnvironmentVariableA :: (lpName: *u8, lpBuffer: *u8, nSize: u32) -> u32 #foreign kernel32;

    get_env :: (name: string) -> string {
        c_name := temp_c_string(name);
    needed := GetEnvironmentVariableA(c_name, null, 0);
    if needed == 0 return "";

    buf := cast(*u8) talloc(needed);
    len := GetEnvironmentVariableA(c_name, buf, needed);
    if len == 0 return "";

    return to_string(buf, len);
    }
} else {
    #import "POSIX";

    get_env :: (name: string) -> string {
        c_name := temp_c_string(name);
        c_val := getenv(c_name);
        if !c_val return "";
        return to_string(c_val);
    }
}

get_user_home_directory :: () -> string {
	#if OS == .WINDOWS {
		user_profile := get_env("USERPROFILE");

		if user_profile && user_profile != "" {
			return user_profile;
		}

        return "C:/";
	} else {
        home := get_env("HOME");
        if home && home != "" return home;
        return "/tmp";
    }
}

get_config_home :: () -> string {
	#if OS == .WINDOWS {
		app_data := get_env("APPDATA");
		if app_data && app_data != "" return app_data;
        return tprint("%1/AppData/Roaming", get_user_home_directory());
	} else {
        config_home := get_env("XDG_CONFIG_HOME");
        if config_home && config_home != "" {
        	return config_home;
        }
        return tprint("%1/.config", get_user_home_directory());
    }
}

get_data_home :: () -> string {
	#if OS == .WINDOWS {
        local_app_data := get_env("LOCALAPPDATA");
        if local_app_data && local_app_data != "" return local_app_data;
        return tprint("%1/AppData/Local", get_user_home_directory());
    } else {
        data_home := get_env("XDG_DATA_HOME");
        if data_home && data_home != "" return data_home;
        return tprint("%1/.local/share", get_user_home_directory());
    }
}

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