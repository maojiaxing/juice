#import "Basic";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";

// Dependency resolution state (spec 0087 decisions 13-15): the Git selections
// a resolution context has already made, kept apart from the shared source
// content cache. Two roots, two questions:
//   content cache: which Git object contents are available anywhere on this
//                  machine (shared by every consumer),
//   state:         which commit each consumer's declaring package selected for
//                  a source selector (private to one consumer context).
// Clearing content never clears state, so a later ordinary resolution can
// restore exactly the recorded commit; a corrupt state file is an error, not an
// absent record. The state file is written atomically after a complete graph
// succeeds, so a failed resolution preserves the previous selections.
//
// The layout below is internal, not a published contract: only the observable
// behavior (documented in GLOSSARY.md: resolved revision, resolution context,
// source content cache, dependency resolution state) is promised.

Resolution_Mode :: enum {
    // Ordinary build/run/test: reuse a recorded selection; resolve only when
    // no record exists; restore missing content for the recorded commit.
    NORMAL;
    // Explicit update: re-resolve every Git source in the complete graph,
    // online only.
    UPDATE;
    // Offline: no network access at all. Recorded selections with complete
    // content work; a full commit id with content already present may
    // establish a new record.
    OFFLINE;
}

Resolution_Environment :: struct {
    content_cache_root: string;
    state_root:         string;
    mode:               Resolution_Mode;
}

// One preparation request: everything dependency preparation may consult,
// passed explicitly instead of read from global mutable state. The workspace
// layer builds it from its discovery snapshot; the resolver consumes it.
Dependency_Preparation_Request :: struct {
    discovery:      Workspace_Discovery;
    invocation_dir: string;
    cache_dir:      string;
    modules_dir:    string = "";
    environment:    Resolution_Environment;
    // The command's validated package selection (ticket 0093). A successful
    // selection means only these packages' graphs are resolved; an unset
    // (zero) selection keeps the location default, which is what the workspace
    // seam and the function-level tests use.
    selection:      Package_Selection;
    // When set, the consumer's import names are written here instead of into the
    // consumer package's own target/imports. A plugin provider is resolved
    // through this override: the provider may be a read-only Git checkout, and
    // every derived output belongs to the CONSUMING project (decision 24).
    shim_root_override: string = "";
}

// One recorded Git selection. declaring_key identifies the declaring package
// inside the consumer context (a local package directory or a provider package
// inside a Git checkout) and is independent of the dependency reference name,
// its alias and its module list. The selector spelling is recorded so a changed
// selector is a new record instead of a silent reuse.
Resolved_Selection :: struct {
    declaring_key: string;
    url:           string;
    branch:        string;
    tag:           string;
    rev:           string;
    commit:        string;
}

Resolution_State :: struct {
    present:    bool;
    corrupt:    bool;
    error:      string;
    selections: [] Resolved_Selection;
}

RESOLUTION_STATE_HEADER :: "juice-resolution-state 1";

// FNV-1a over the bytes; only used for stable directory names and the content
// cache's source key, never for identity comparisons.
hash_text_fnv1a :: (text: string) -> u64 {
    hash: u64 = 14695981039346656037;
    for byte: text {
        hash ^= cast(u64) byte;
        hash *= 1099511628211;
    }
    return hash;
}

u64_hex :: (value: u64) -> string {
    hex_digits :: "0123456789abcdef";
    builder: String_Builder;
    for nibble: 0..15 {
        shift := cast(u64) (15 - nibble) * 4;
        digit := (value >> shift) & 15;
        append(*builder, hex_digits[cast(s64) digit]);
    }
    return builder_to_string(*builder);
}

// A filesystem-safe, human-readable key: alphanumeric bytes survive, every
// other byte becomes "_", and a short hash keeps distinct inputs distinct.
resolution_sanitized_key :: (text: string, limit := 40) -> string {
    builder: String_Builder;
    written := 0;
    for byte: text {
        if written >= limit break;
        alphanumeric := (byte >= #char "a" && byte <= #char "z") || (byte >= #char "A" && byte <= #char "Z") || (byte >= #char "0" && byte <= #char "9");
        append(*builder, ifx alphanumeric then byte else #char "_");
        written += 1;
    }
    digest := u64_hex(hash_text_fnv1a(text));
    print_to_builder(*builder, "-%1", slice(digest, 0, 12));
    return builder_to_string(*builder);
}

resolution_state_directory :: (environment: Resolution_Environment, consumer_root: string) -> string {
    return tprint("%1/contexts/%2", environment.state_root, resolution_sanitized_key(consumer_root));
}

resolution_state_file :: (environment: Resolution_Environment, consumer_root: string) -> string {
    return tprint("%1/resolution.state", resolution_state_directory(environment, consumer_root));
}

// The declaring package identity inside a consumer context: a local package is
// its consumer-relative directory, a provider package inside a Git checkout is
// its repository identity plus its in-checkout location. Reference names,
// aliases and module lists are deliberately absent.
resolution_declaring_key_local :: (consumer_root: string, package_dir: string) -> string {
    relative := package_dir;
    if consumer_root != "" && starts_with(package_dir, consumer_root) && package_dir.count > consumer_root.count
        relative = slice(package_dir, consumer_root.count + 1, package_dir.count - consumer_root.count - 1);
    return tprint("path:%", relative);
}

resolution_declaring_key_git :: (url: string, commit: string, package_path: string) -> string {
    return tprint("git:%1@%2:%3", url, commit, package_path);
}

// Selector identity: exactly one of branch/tag/rev, or the default branch. The
// spelling is part of the key, so changing the selector re-resolves while
// changing only a reference name or alias does not.
git_selector_identity :: (branch: string, tag: string, rev: string) -> string {
    if rev != "" return tprint("rev:%", rev);
    if tag != "" return tprint("tag:%", tag);
    if branch != "" return tprint("branch:%", branch);
    return "default";
}

is_full_commit_id :: (text: string) -> bool {
    if text.count != 40 return false;
    for byte: text {
        hex := (byte >= #char "0" && byte <= #char "9") || (byte >= #char "a" && byte <= #char "f") || (byte >= #char "A" && byte <= #char "F");
        if !hex return false;
    }
    return true;
}

STATE_ESCAPE_HEX_DIGITS :: "0123456789ABCDEF";

state_escape :: (value: string) -> string {
    builder: String_Builder;
    for byte: value {
        if byte == #char "%" || byte == #char "\t" || byte == #char "\n" || byte == #char "\r" {
            append(*builder, #char "%");
            append(*builder, STATE_ESCAPE_HEX_DIGITS[cast(s64) ((byte >> 4) & 15)]);
            append(*builder, STATE_ESCAPE_HEX_DIGITS[cast(s64) (byte & 15)]);
        } else {
            append(*builder, byte);
        }
    }
    return builder_to_string(*builder);
}

state_hex_value :: (byte: u8) -> int {
    if byte >= #char "0" && byte <= #char "9" return cast(int) (byte - #char "0");
    if byte >= #char "A" && byte <= #char "F" return cast(int) (byte - #char "A") + 10;
    if byte >= #char "a" && byte <= #char "f" return cast(int) (byte - #char "a") + 10;
    return -1;
}

state_unescape :: (value: string) -> string, bool {
    if find_index_from_left(value, "%") < 0 return value, true;
    builder: String_Builder;
    index := 0;
    while index < value.count {
        byte := value[index];
        if byte != #char "%" {
            append(*builder, byte);
            index += 1;
            continue;
        }
        if index + 2 >= value.count return "", false;
        high := state_hex_value(value[index + 1]);
        low := state_hex_value(value[index + 2]);
        if high < 0 || low < 0 return "", false;
        append(*builder, cast(u8) (high * 16 + low));
        index += 3;
    }
    return builder_to_string(*builder), true;
}

read_resolution_state :: (state_file: string) -> Resolution_State {
    state: Resolution_State;
    if !file_exists(state_file) return state;

    state.present = true;
    content, read_ok := read_entire_file(state_file);
    if !read_ok {
        state.corrupt = true;
        state.error = tprint("Dependency resolution state is unreadable: %", state_file);
        return state;
    }
    lines := split(content, "\n");
    if lines.count == 0 || trim(lines[0]) != RESOLUTION_STATE_HEADER {
        state.corrupt = true;
        state.error = tprint("Dependency resolution state is corrupt (unknown header): %", state_file);
        return state;
    }
    selections: [..] Resolved_Selection;
    for line, line_index: lines {
        if line_index == 0 continue;
        trimmed := trim(line);
        if trimmed == "" continue;
        fields := split(trimmed, "\t");
        if fields.count != 6 {
            state.corrupt = true;
            state.error = tprint("Dependency resolution state is corrupt (malformed row): %", state_file);
            return state;
        }
        values: [6] string;
        valid := true;
        for field, field_index: fields {
            unescaped, unescape_ok := state_unescape(field);
            if !unescape_ok valid = false;
            values[field_index] = unescaped;
        }
        if !valid || !is_full_commit_id(values[5]) {
            state.corrupt = true;
            state.error = tprint("Dependency resolution state is corrupt (invalid row): %", state_file);
            return state;
        }
        array_add(*selections, Resolved_Selection.{
            declaring_key = values[0],
            url           = values[1],
            branch        = values[2],
            tag           = values[3],
            rev           = values[4],
            commit        = values[5],
        });
    }
    state.selections = selections;
    return state;
}

// -1 when no record exists for this declaring package and source selector.
find_resolved_selection :: (state: Resolution_State, declaring_key: string, url: string, branch: string, tag: string, rev: string) -> int {
    for selection, index: state.selections {
        if selection.declaring_key != declaring_key continue;
        if selection.url != url continue;
        if selection.branch != branch || selection.tag != tag || selection.rev != rev continue;
        return index;
    }
    return -1;
}

// Remove a directory tree and only return once it is really gone. Windows
// recursive deletion (and `rmdir /S /Q`) reports completion while the tree is
// still being unlinked, so a caller that immediately re-uses the same path can
// observe a partially deleted directory and fail with "Access is denied". The
// bounded wait turns that race into a predictable result; it is a wait, not a
// retry of the caller's own work.
resolution_remove_directory :: (path: string) -> bool {
    if !file_exists(path) && !path_is_symlink(path) return true;
    #if OS == .WINDOWS {
        result := run_command("cmd", "/c", "rmdir", "/S", "/Q", path_backslashes(path));
        if result.type != .EXITED || result.exit_code != 0 return false;
    } else {
        result := run_command("rm", "-rf", path);
        if result.type != .EXITED || result.exit_code != 0 return false;
    }
    for 0..4999 {
        if !file_exists(path) && !path_is_symlink(path) return true;
        sleep_milliseconds(1);
    }
    return !file_exists(path) && !path_is_symlink(path);
}

// Publish the complete selection set for one consumer context atomically. A
// failure leaves the previous file untouched.
publish_resolution_state :: (environment: Resolution_Environment, consumer_root: string, selections: [] Resolved_Selection) -> bool {
    directory := resolution_state_directory(environment, consumer_root);
    if !make_directory_if_it_does_not_exist(directory, recursive = true) return false;

    builder: String_Builder;
    print_to_builder(*builder, "%\n", RESOLUTION_STATE_HEADER);
    for selection: selections {
        print_to_builder(*builder, "%\t%\t%\t%\t%\t%\n",
            state_escape(selection.declaring_key),
            state_escape(selection.url),
            state_escape(selection.branch),
            state_escape(selection.tag),
            state_escape(selection.rev),
            selection.commit);
    }
    target := resolution_state_file(environment, consumer_root);
    temporary := tprint("%.tmp", target);
    if !write_entire_file(temporary, builder_to_string(*builder)) return false;
    if !atomic_file_replace_or_just_rename_if_destination_file_does_not_exist(temporary, target) {
        file_delete(temporary);
        return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// Git commands. Every call runs through resolve_git_command so tests can count
// network-capable invocations and so the resolver never guesses at Git
// semantics with package-name or version-range rules.
// ---------------------------------------------------------------------------

git_run :: (arguments: [] string, working_directory := "") -> (string, Process_Result) {
    command: [..] string;
    array_add(*command, "git");
    for argument: arguments array_add(*command, argument);
    result, output, errors, timed_out := run_command(..command, working_directory = working_directory, capture_and_return_output = true);
    if timed_out return "", Process_Result.{type = .FAILED_TO_LAUNCH};
    return output, result;
}

git_captured_value :: (arguments: [] string, working_directory := "") -> (string, bool) {
    output, result := git_run(arguments, working_directory);
    if result.type != .EXITED || result.exit_code != 0 return "", false;
    return trim(output), true;
}

// The content-cache directory name for one source. The prefix stays short on
// purpose: a materialized checkout path is content/<key>/<40-character commit>/
// <in-repository package path>, and Windows file APIs (GetFileAttributesW,
// FindFirstFileExW) reject paths at MAX_PATH unless long paths are opted in.
// A shorter readable prefix plus the 48-bit digest leaves several dozen
// characters of headroom for those in-repository paths.
resolution_source_key :: (url: string) -> string {
    return resolution_sanitized_key(url, 24);
}

git_content_repository_directory :: (environment: Resolution_Environment, url: string) -> string {
    return tprint("%1/git/%2", environment.content_cache_root, resolution_source_key(url));
}

git_content_checkout_directory :: (environment: Resolution_Environment, url: string, commit: string) -> string {
    return tprint("%1/content/%2/%3", environment.content_cache_root, resolution_source_key(url), commit);
}

git_repository_present :: (repository: string) -> bool {
    return is_directory(tprint("%/.git", repository));
}

git_commit_available :: (repository: string, commit: string) -> bool {
    if !git_repository_present(repository) return false;
    _, ok := git_captured_value(string.["-C", repository, "cat-file", "-e", commit]);
    return ok;
}

git_checkout_commit :: (checkout: string) -> string, bool {
    if !is_directory(checkout) return "", false;
    value, ok := git_captured_value(string.["-C", checkout, "rev-parse", "HEAD"]);
    return value, ok;
}

// Clone or refresh the shared content repository. Network access only happens
// when the caller allows it: an offline resolution never reaches this branch,
// and an ordinary reuse never calls it at all because the recorded content is
// already present.
git_ensure_repository :: (environment: Resolution_Environment, url: string, allow_network: bool, refresh: bool) -> string, string {
    repository := git_content_repository_directory(environment, url);
    if git_repository_present(repository) {
        if refresh && allow_network {
            _, fetched := git_captured_value(string.["-C", repository, "fetch", "--quiet", "--tags", "--prune", "--all"]);
            if !fetched return repository, tprint("Could not fetch the Git source: %", url);
        }
        return repository, "";
    }
    if !allow_network return "", tprint("Offline resolution needs cached content for the Git source: %", url);

    if !make_directory_if_it_does_not_exist(get_directory_path(repository), recursive = true)
        return "", tprint("Could not create the content cache for: %", url);
    resolution_remove_directory(repository);
    _, cloned := git_captured_value(string.["clone", "--quiet", url, repository]);
    if !cloned || !git_repository_present(repository) {
        resolution_remove_directory(repository);
        return "", tprint("Could not clone the Git source: %", url);
    }
    return repository, "";
}

// Resolve a selector spelling to a full commit id. The selector kind is part of
// the lookup so a branch named like a tag cannot change the meaning of a
// declared source.
git_resolve_selector :: (environment: Resolution_Environment, url: string, branch: string, tag: string, rev: string) -> (string, string) {
    repository, repository_error := git_ensure_repository(environment, url, true, true);
    if repository_error != "" return "", repository_error;

    if rev != "" {
        commit, ok := git_captured_value(string.["-C", repository, "rev-list", "-n", "1", rev]);
        if ok return commit, "";
        _, fetched := git_captured_value(string.["-C", repository, "fetch", "--quiet", "origin", rev]);
        if fetched {
            refetched, refetched_ok := git_captured_value(string.["-C", repository, "rev-list", "-n", "1", rev]);
            if refetched_ok return refetched, "";
        }
        return "", tprint("Git revision '%' did not resolve to a commit in %", rev, url);
    }
    if tag != "" {
        commit, ok := git_captured_value(string.["-C", repository, "rev-list", "-n", "1", tprint("refs/tags/%", tag)]);
        if ok return commit, "";
        return "", tprint("Git tag '%' did not resolve to a commit in %", tag, url);
    }
    if branch != "" {
        commit, ok := git_captured_value(string.["-C", repository, "rev-list", "-n", "1", tprint("refs/remotes/origin/%", branch)]);
        if ok return commit, "";
        return "", tprint("Git branch '%' did not resolve to a commit in %", branch, url);
    }
    head_commit, head_ok := git_captured_value(string.["-C", repository, "rev-list", "-n", "1", "refs/remotes/origin/HEAD"]);
    if head_ok return head_commit, "";
    local_head, local_head_ok := git_captured_value(string.["-C", repository, "rev-list", "-n", "1", "HEAD"]);
    if local_head_ok return local_head, "";
    return "", tprint("The default branch did not resolve to a commit in %", url);
}

// Materialize one commit's content. A recorded commit is restored by itself
// (never by moving to the newest branch); a damaged or missing checkout is
// rebuilt from the shared repository when the network is allowed, and is an
// error otherwise.
git_ensure_content :: (environment: Resolution_Environment, url: string, commit: string) -> (string, string) {
    checkout := git_content_checkout_directory(environment, url, commit);
    if is_directory(checkout) {
        current, current_ok := git_checkout_commit(checkout);
        if current_ok && current == commit return checkout, "";
        if current_ok {
            return "", tprint("Cached content for commit % is damaged: %", commit, checkout);
        }
        if environment.mode == .OFFLINE return "", tprint("Cached content for commit % is incomplete: %", commit, checkout);
        resolution_remove_directory(checkout);
    }
    if environment.mode == .OFFLINE return "", tprint("Offline resolution needs cached content for commit %.", commit);

    repository, repository_error := git_ensure_repository(environment, url, true, false);
    if repository_error != "" return "", repository_error;
    if !git_commit_available(repository, commit) {
        git_captured_value(string.["-C", repository, "fetch", "--quiet", "--tags", "--all"]);
        if !git_commit_available(repository, commit) return "", tprint("Missing Git content for commit %: %", commit, url);
    }
    if !make_directory_if_it_does_not_exist(get_directory_path(checkout), recursive = true) return "", tprint("Could not create the content cache directory: %", checkout);

    // Materialize straight into the final path instead of renaming a staging
    // directory over it. On Windows a staged directory can keep "Access is
    // denied" for a rename long after the git commands that wrote it exited,
    // and a rename has no recovery path, so the cache is filled the way git
    // itself fills it: clone into place, then check out the exact commit.
    // Incomplete content is never trusted - the entry check above validates the
    // commit and rebuilds a checkout that does not match - so a clone
    // interrupted here costs work, never correctness.
    resolution_remove_directory(checkout);
    cloned_now := false;
    for attempt: 0..4 {
        _, cloned := git_captured_value(string.["clone", "--quiet", "--no-checkout", "--shared", repository, checkout]);
        if cloned {
            cloned_now = true;
            break;
        }
        // A concurrent owner may have won the same path; accept it only when it
        // is a real checkout of this commit.
        if is_directory(checkout) {
            current, current_ok := git_checkout_commit(checkout);
            if current_ok && current == commit return checkout, "";
        }
        resolution_remove_directory(checkout);
        sleep_milliseconds(100);
    }
    if !cloned_now return "", tprint("Could not materialize Git content for commit %: %", commit, url);
    _, checked_out := git_captured_value(string.["-C", checkout, "checkout", "--quiet", "--detach", commit]);
    if !checked_out {
        resolution_remove_directory(checkout);
        return "", tprint("Could not check out commit % in %", commit, url);
    }
    current, current_ok := git_checkout_commit(checkout);
    if !current_ok || current != commit {
        resolution_remove_directory(checkout);
        return "", tprint("Could not materialize Git content for commit %: %", commit, checkout);
    }
    return checkout, "";
}
