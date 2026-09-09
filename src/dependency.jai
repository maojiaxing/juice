#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";
#import "Process";

#import "Juice";

Source_Type :: enum {
    LOCAL_PATH;
    GIT_URL;
}

detect_source_type :: (source: string) -> Source_Type {
    if source == "" return .LOCAL_PATH;
    if starts_with(source, "file://") return .LOCAL_PATH;

    git_schemas :: string.[
        "https://", "http://", "git://", "ssh://", "git+https://", "git+ssh://"
    ];
    for schema: git_schemas {
        if starts_with(source, schema) return .GIT_URL;
    }

    if starts_with(source, "git@") && contains(source, ":") return .GIT_URL;
    if ends_with(source, ".git") return .GIT_URL;
    return .LOCAL_PATH;
}

clean_local_path :: (source: string) -> string {
    if starts_with(source, "file://") return advance(source, 7);
    return source;
}

File_Search_Context :: struct {
    target_name: string;
    results:     [..] string;
}

file_search_visitor :: (info: *File_Visit_Info, user_data: *File_Search_Context) {
    if info.short_name == user_data.target_name {
        array_add(*user_data.results, copy_string(info.full_name));
    }
}

find_files_recursive :: (dir: string, filename: string) -> [..] string {
    ctx: File_Search_Context;
    ctx.target_name = filename;
    visit_files(dir, true, *ctx, file_search_visitor, visit_directories = false);
    return ctx.results;
}

find_package_in_repo :: (driver: *Build_Driver, repo_dir: string, target_pkg_name: string) -> string, bool {
    manifest_files := find_files_recursive(repo_dir, "package.jai");
    defer array_free(manifest_files);

    for manifest_path: manifest_files {
        pkg_dir := get_directory_path(manifest_path);
        pkg, ok := load_package_manifest(driver, pkg_dir);
        if ok && pkg.name == target_pkg_name return pkg_dir, true;
    }
    return "", false;
}

// Dependency preparation consumes already validated discovery paths. It does
// not rediscover the workspace and is never called by Clean.
resolve_and_fetch_dependencies :: (driver: *Build_Driver, member_paths: [] string) -> bool {
    make_directory_if_it_does_not_exist(driver.packages_dir, recursive = true);

    for member_path: member_paths {
        pkg, ok := load_package_manifest(driver, member_path);
        if !ok continue;

        for dep: pkg.dependencies {
            if is_workspace_member(driver, member_paths, dep.name) continue;
            if !fetch_dependency(driver, dep) {
                print("[juice ERROR] Failed to fetch dependency: %1\n", dep.name);
                return false;
            }
        }
    }
    return true;
}

fetch_dependency :: (driver: *Build_Driver, dep: Dependency) -> bool {
    source_type := detect_source_type(dep.source);

    if source_type == {
        case .LOCAL_PATH;
            clean_path := clean_local_path(dep.source);
            target_link := tprint("%1/%2", driver.packages_dir, dep.name);
            return link_directory(clean_path, target_link);

        case .GIT_URL;
            git_cache_base := tprint("%1/git_repos", driver.cache_dir);
            repo_cache_dir := get_git_repo_cache_path(git_cache_base, dep.source, dep.version);

            if !ensure_git_repo_cloned(dep.source, dep.version, repo_cache_dir) return false;

            target_name := ifx dep.package != "" then dep.package else dep.name;
            sub_pkg_dir, found := find_package_in_repo(driver, repo_cache_dir, target_name);
            if !found {
                print("[juice ERROR] Package '%1' not found in Git repo %2!\n", target_name, dep.source);
                return false;
            }

            local_pkg_link := tprint("%1/%2", driver.packages_dir, dep.name);
            return link_directory(sub_pkg_dir, local_pkg_link);
    }
    return false;
}

get_directory_path :: (file_path: string) -> string {
    if file_path == "" return "";

    last_slash := -1;
    for i: 0..file_path.count-1 {
        ch := file_path[i];
        if ch == #char "/" || ch == #char "\\" last_slash = i;
    }

    if last_slash == -1 return ".";
    if last_slash == 0 return "/";
    return slice(file_path, 0, last_slash);
}

is_workspace_member :: (driver: *Build_Driver, member_paths: [] string, name: string) -> bool {
    for member_path: member_paths {
        pkg, ok := load_package_manifest(driver, member_path);
        if ok && pkg.name == name return true;
    }
    return false;
}

get_git_repo_cache_path :: (base_dir: string, url: string, version: string) -> string {
    builder: String_Builder;
    for i: 0..url.count-1 {
        ch := url[i];
        if (ch >= #char "a" && ch <= #char "z") ||
           (ch >= #char "A" && ch <= #char "Z") ||
           (ch >= #char "0" && ch <= #char "9") {
            append(*builder, ch);
        } else {
            append(*builder, #char "_");
        }
    }

    if version != "" print_to_builder(*builder, "_%", version);
    sanitized := builder_to_string(*builder);
    return tprint("%1/%2", base_dir, sanitized);
}

ensure_git_repo_cloned :: (url: string, version: string, dst_dir: string) -> bool {
    if file_exists(dst_dir) {
        res_fetch := run_command("git", "-C", dst_dir, "fetch", "--all");
        if res_fetch.exit_code != 0 return false;
    } else {
        res_clone := run_command("git", "clone", url, dst_dir);
        if res_clone.exit_code != 0 return false;
    }

    if version != "" {
        res_checkout := run_command("git", "-C", dst_dir, "checkout", version);
        if res_checkout.exit_code != 0 return false;
    }
    return true;
}

link_directory :: (src: string, dst: string) -> bool {
    dst_parent := get_directory_path(dst);
    if dst_parent != "" make_directory_if_it_does_not_exist(dst_parent, recursive = true);

    if file_exists(dst) delete_directory_full(dst);

    #if OS == .WINDOWS {
        res := run_command("cmd", "/c", "mklink", "/J", dst, src);
        return res.exit_code == 0;
    } else {
        res := run_command("ln", "-s", src, dst);
        return res.exit_code == 0;
    }
}

delete_directory_full :: (path: string) -> bool {
    if !file_exists(path) return true;
    #if OS == .WINDOWS {
        res := run_command("cmd", "/c", "rmdir", "/S", "/Q", path);
        return res.exit_code == 0;
    } else {
        res := run_command("rm", "-rf", path);
        return res.exit_code == 0;
    }
}
