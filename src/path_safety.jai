#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

#if OS == .WINDOWS {
    #import "Windows";
    #import "Windows_Utf8";
}

Path_Entry_Check :: struct {
    exists:       bool;
    is_directory: bool;
    is_symlink:   bool;
    is_junction:  bool;
    had_error:    bool;
}

path_slashes :: (path: string) -> string {
    result := copy_string(path);
    for i: 0..result.count-1 {
        if result[i] == #char "\\" result[i] = #char "/";
    }
    return result;
}

paths_equal :: (left: string, right: string) -> bool {
    a := path_slashes(left);
    b := path_slashes(right);
    #if OS == .WINDOWS {
        return equal_nocase(a, b);
    } else {
        return a == b;
    }
}

path_entry_visitor :: (info: *File_Visit_Info, user_data: *Path_Entry_Check) {
    user_data.exists = true;
    user_data.is_directory = info.is_directory;
    user_data.is_symlink = info.is_symlink;
}

// File_Utilities exposes symlinks while enumerating a parent directory. This
// also sees dangling links, unlike file_exists(), which follows the link.
lexical_absolute_path :: (path: string) -> string {
    normalized := path_slashes(path);
    if !path_is_absolute_portable(normalized) {
        normalized = tprint("%1/%2", path_slashes(get_working_directory()), normalized);
    }
    parsed := parse_path(normalized, reduce = true);
    return path_slashes(path_to_string(parsed));
}

inspect_path_entry :: (path: string) -> Path_Entry_Check {
    result: Path_Entry_Check;
    if path == "" return result;

    absolute := lexical_absolute_path(path);

    parent := path_strip_filename(absolute);
    if parent == "" parent = ".";
    while parent.count > 1 && (parent[parent.count - 1] == #char "/" || parent[parent.count - 1] == #char "\\") {
        parent.count -= 1;
    }
    found_name := path_slashes(absolute);

    Scan_Context :: struct {
        path: string;
        result: *Path_Entry_Check;
    }
    scan: Scan_Context;
    scan.path = found_name;
    scan.result = *result;

    visit :: (info: *File_Visit_Info, scan: *Scan_Context) {
        if paths_equal(info.full_name, scan.path) {
            scan.result.exists = true;
            scan.result.is_directory = info.is_directory;
            scan.result.is_symlink = info.is_symlink;
        }
    }

    visited := visit_files(parent, false, *scan, visit, visit_files = true, visit_directories = true, visit_symlinks = true, follow_directory_symlinks = false);
    if !visited && !result.exists result.had_error = true;

    #if OS == .WINDOWS {
        if result.exists {
            attributes := GetFileAttributesW(utf8_to_wide(absolute,, temp));
            if attributes != INVALID_FILE_ATTRIBUTES {
                result.is_junction = (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0 && !result.is_symlink;
            }
        }
    }

    return result;
}

path_is_symlink :: (path: string) -> bool {
    entry := inspect_path_entry(path);
    return entry.is_symlink || entry.is_junction;
}

path_exists_as_directory :: (path: string) -> bool {
    entry := inspect_path_entry(path);
    return entry.exists && entry.is_directory && !entry.is_symlink && !entry.is_junction;
}

path_exists_as_regular_file :: (path: string) -> bool {
    entry := inspect_path_entry(path);
    return entry.exists && !entry.is_directory && !entry.is_symlink && !entry.is_junction;
}

path_is_absolute_portable :: (path: string) -> bool {
    if path == "" return false;
    if path[0] == #char "/" || path[0] == #char "\\" return true;
    // A volume designator is not portable, including C:foo.
    for i: 0..path.count-1 {
        if path[i] == #char ":" return true;
    }
    return false;
}

path_has_escape_component :: (path: string) -> bool {
    normalized := path_slashes(path);
    parts := split(normalized, "/");
    for part: parts {
        if part == ".." return true;
    }
    return false;
}

path_is_portable_filename :: (name: string) -> bool {
    if name == "" || name == "." || name == ".." return false;
    if name[name.count - 1] == #char "." || name[name.count - 1] == #char " " return false;
    for ch: name {
        if ch < 32 return false;
        if ch == #char "/" || ch == #char "\\" || ch == #char ":" return false;
        if ch == #char "*" || ch == #char "?" || ch == #char "\"" return false;
        if ch == #char "<" || ch == #char ">" || ch == #char "|" return false;
    }
    // These names are reserved by Windows and therefore are not portable.
    upper := to_upper_copy(name);
    if upper == "CON" || upper == "PRN" || upper == "AUX" || upper == "NUL" return false;
    if starts_with(upper, "COM") || starts_with(upper, "LPT") {
        if upper.count == 4 && upper[3] >= #char "1" && upper[3] <= #char "9" return false;
    }
    return true;
}

path_is_portable_relative_jai :: (path: string) -> bool {
    if path == "" || path_is_absolute_portable(path) return false;
    if path_has_escape_component(path) return false;
    if !ends_with_nocase(path, ".jai") return false;
    return true;
}

path_is_within :: (root: string, candidate: string) -> bool {
    root_abs, root_ok := get_absolute_path(root);
    if !root_ok return false;
    candidate_abs, candidate_ok := get_absolute_path(candidate);
    if !candidate_ok candidate_abs = lexical_absolute_path(candidate);
    root_norm := path_slashes(root_abs);
    candidate_norm := path_slashes(candidate_abs);
    if root_norm == "" || candidate_norm == "" return false;
    if paths_equal(root_norm, candidate_norm) return true;
    if !ends_with(root_norm, "/") root_norm = tprint("%1/", root_norm);
    if candidate_norm.count <= root_norm.count return false;
    prefix := slice(candidate_norm, 0, root_norm.count);
    return paths_equal(prefix, root_norm);
}

normalize_existing_path :: (path: string) -> string, bool {
    absolute, ok := get_absolute_path(path);
    if !ok return "", false;
    return path_slashes(absolute), true;
}
