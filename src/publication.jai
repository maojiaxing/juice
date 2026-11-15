// Publication transforms (ticket 030, spec §9): the pure text-to-text
// generators producing the three published module artifacts from the single
// definition source src/module.jai, plus the target/modules landing path
// helpers:
//
// - Juice directory module (target/modules/Juice/module.jai): the package
//   section cut verbatim (the Package compatibility face — the field shapes
//   old juice modules/Juice.jai declares);
// - Testing.jai (target/modules/Testing.jai): the testing section with the
//   Testing_ public-name prefixes stripped — flat module, bare exports, the
//   old juice Testing.jai API-compatible face;
// - juice_core.jai (target/modules/juice_core.jai): a generated module that
//   #loads the plugin face closure by module-relative paths (ticket 049) and
//   re-declares the two built-in id constants extracted verbatim from the
//   definition source (module.jai itself is not #loaded: its testing section
//   carries self-test blocks that only the transpile pipeline can compile).
//
// Ticket 037 adds a fourth publication that is not a module face: the
// discovery source (juice_internal/test_discovery.jai under the modules
// directory) is a verbatim copy of src/test_discovery.jai, #loaded by
// absolute path into the generated test metaprogram. The juice_internal/
// subdirectory keeps it out of the public import face, and the copy has no
// transform at all — the callers read the source and write it unchanged, so
// the compiled-in discovery behavior and the generated test program can
// never drift.
//
// Ticket 049 makes juice_core self-contained: the plugin face closure files
// (JUICE_CORE_LOAD_FILES) are published verbatim under
// <modules>/juice_internal/plugin_face/ and #loaded by paths relative to
// juice_core.jai's own directory — a #load inside a name-imported module
// resolves against the containing file's directory (the 048 decision 5
// spike fact). The published modules/ tree therefore relocates unchanged;
// no build-machine src path crosses the publication boundary.
//
// Section boundary contract (the single source — src/module.jai's header
// comment): the definition source carries exactly two marker comments,
// `// [PUBLICATION-SECTION package]` and `// [PUBLICATION-SECTION testing]`
// (a line matches when its trimmed content equals the marker text), plus
// exactly one self-test cut `// [PUBLICATION-CUT testing-self-tests]` inside
// the testing section. The package section is the lines between the package
// marker and the next marker; the testing section is the lines after the
// testing marker up to the cut marker (the self-test procedures and state
// below it are juice's own suite, never published). Leading and trailing
// blank lines are trimmed from both sections. A missing, duplicated,
// misordered or unknown-named marker fails the publication loudly
// (ok = false) — drift in the marker contract must never publish silently.
//
// Line fidelity (the transpile discipline): the prefix strip rewrites IDENT
// tokens only, so the published Testing.jai is line-for-line identical to
// its source section (published line N = section line N) — diagnostics and
// path_mapping stay verifiable against the definition source.
//
// Pure functions only — the caller (the build.jai metaprogram, ticket 031)
// reads the definition source and writes the artifacts. This module is a
// bootstrap #load target and must stay test-free; its unit tests live in
// tests/publication_tests.jai (0053 rule). main.jai loads it too — the
// exe's test command derives the published discovery artifact's path
// through test_discovery_module_path (ticket 037); the build metaprogram
// is the producer side.
//
// Path separators normalize with front_slashes (transpile_front.jai's
// self-contained implementation): the bootstrap #load closure does not
// include path_safety.jai (whose path_slashes this module used before the
// ticket 032 wiring — same semantics; the ticket 031 closure discipline).

#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

PUBLICATION_SECTION_PACKAGE :: "package";
PUBLICATION_SECTION_TESTING :: "testing";

MARKER_PREFIX :: "// [PUBLICATION-SECTION ";
MARKER_SUFFIX :: "]";

TESTING_PREFIX :: "Testing_";

// The testing-section cut marker: the published Testing.jai ends before this
// line. The definition source keeps its self-test procedures and state below
// the marker (juice's own suite), while the consumer face stays test-free —
// the published module must compile as standard Jai without contributing
// @test procedures to a consumer's program. Exactly one marker is required;
// missing or duplicated markers fail the publication loudly.
PUBLICATION_CUT_TESTING_SELF_TESTS :: "// [PUBLICATION-CUT testing-self-tests]";

// The plugin face closure the generated juice_core module #loads (module-
// relative paths under the plugin face landing directory — ticket 049) and
// the single file list the publication copy step consumes: one list drives
// both the generated #load lines and the landing of the verbatim copies.
// module.jai is deliberately absent: its testing section carries the
// definition source's own @test procedures (cut from the published face at
// the self-test marker), so the two built-in id constants it declares are
// extracted verbatim into the generated module instead (the single source
// preserved textually).
JUICE_CORE_LOAD_FILES :: string.[
    "transpile.jai",
    "transpile_plugin.jai",
    "lifecycle.jai",
    "plugin.jai",
];

// ---------------------------------------------------------------------------
// Section cut
// ---------------------------------------------------------------------------

// The trimmed content of a source line (spaces and tabs).
line_trimmed :: (line: string) -> string {
    start := 0;
    while start < line.count && (line[start] == #char " " || line[start] == #char "\t") start += 1;
    end := line.count;
    while end > start && (line[end - 1] == #char " " || line[end - 1] == #char "\t") end -= 1;
    return slice(line, start, end - start);
}

is_blank_line :: (line: string) -> bool {
    return line_trimmed(line).count == 0;
}

// One marker-contract scan outcome: the two section spans as 0-based line
// ranges (exclusive ends), or a failure.
Section_Spans :: struct {
    package_start: s64;  // first line of the package section, -1 on failure
    package_end:   s64;  // exclusive end (the testing marker's line)
    testing_start: s64;  // first line of the testing section
    testing_end:   s64;  // exclusive end (line count)
    ok:            bool;
}

// Walks the marker contract (the single scan both extractions share):
// exactly one `package` marker and exactly one `testing` marker, in that
// order. Any other `// [PUBLICATION-SECTION ...]` line — a duplicated
// marker or a typo'd marker name — is a loud failure; a marker typo must
// never publish silently (it would publish the wrong cut).
scan_section_markers :: (lines: [] string) -> Section_Spans {
    out: Section_Spans = .{ package_start = -1, package_end = -1, testing_start = -1, testing_end = -1, ok = false };
    package_at := -1;
    testing_at := -1;
    for i: 0..lines.count - 1 {
        trimmed := line_trimmed(lines[i]);
        if trimmed.count < MARKER_PREFIX.count + MARKER_SUFFIX.count + 1 continue;
        if slice(trimmed, 0, MARKER_PREFIX.count) != MARKER_PREFIX continue;
        if slice(trimmed, trimmed.count - MARKER_SUFFIX.count, MARKER_SUFFIX.count) != MARKER_SUFFIX continue;
        name := slice(trimmed, MARKER_PREFIX.count, trimmed.count - MARKER_PREFIX.count - MARKER_SUFFIX.count);
        if name == PUBLICATION_SECTION_PACKAGE {
            if package_at >= 0 return out;  // duplicated package marker
            package_at = i;
        } else if name == PUBLICATION_SECTION_TESTING {
            if testing_at >= 0 return out;  // duplicated testing marker
            testing_at = i;
        } else {
            return out;  // unknown marker name
        }
    }
    if package_at < 0 || testing_at < 0 || testing_at < package_at return out;
    out.package_start = package_at + 1;
    out.package_end = testing_at;
    out.testing_start = testing_at + 1;
    out.testing_end = lines.count;
    out.ok = true;
    return out;
}

// The section text: the lines in [start, end) with leading and trailing
// blank lines trimmed, joined with "\n". Empty when the span is empty or
// blank-only.
section_text :: (lines: [] string, start: s64, end: s64) -> string {
    first := start;
    while first < end && is_blank_line(lines[first]) first += 1;
    last := end;
    while last > first && is_blank_line(lines[last - 1]) last -= 1;
    builder: String_Builder;
    for i: first..last - 1 {
        if i > first print_to_builder(*builder, "\n");
        print_to_builder(*builder, "%", lines[i]);
    }
    return builder_to_string(*builder);
}

// The package section cut: the lines between the package marker and the
// next marker, blank edges trimmed.
extract_package_section :: (source: string) -> (text: string, ok: bool) {
    lines := split(source, "\n");
    spans := scan_section_markers(lines);
    if !spans.ok return "", false;
    return section_text(lines, spans.package_start, spans.package_end), true;
}

// The testing section cut: the lines after the testing marker to the
// self-test cut marker, blank edges trimmed. The published face therefore
// carries the Testing API and internals but none of the definition source's
// own @test procedures.
extract_testing_section :: (source: string) -> (text: string, ok: bool) {
    lines := split(source, "\n");
    spans := scan_section_markers(lines);
    if !spans.ok return "", false;
    cut, cut_ok := find_self_test_cut_marker(lines, spans.testing_start, spans.testing_end);
    if !cut_ok return "", false;
    return section_text(lines, spans.testing_start, cut), true;
}

// The self-test cut marker scan: exactly one line whose trimmed content is
// the cut marker. Missing or duplicated markers fail (the publication must
// never silently include or exclude the wrong segment).
find_self_test_cut_marker :: (lines: [] string, start: s64, end: s64) -> (index: s64, ok: bool) {
    found := -1;
    for i: start..end - 1 {
        if line_trimmed(lines[i]) != PUBLICATION_CUT_TESTING_SELF_TESTS continue;
        if found >= 0 return -1, false;
        found = i;
    }
    if found < 0 return -1, false;
    return found, true;
}

// ---------------------------------------------------------------------------
// Publication
// ---------------------------------------------------------------------------

// The published Juice directory module content: the package section cut
// verbatim behind the standard Basic import line.
publish_juice_module :: (source: string) -> (text: string, ok: bool) {
    section, ok := extract_package_section(source);
    if !ok return "", false;
    return tprint("#import \"Basic\";\n\n%1\n", section), true;
}

// Strips the Testing_ prefix from every IDENT token carrying it — the
// bootstrap prefixed public names (Testing_run/Testing_finish/Testing_expect/
// Testing_expect_eq/Testing_fail, the Testing_Path_Pair declaration and the
// Testing_path_mapping references). The edit spans are token-bounded, so the
// line structure is preserved exactly (the line-fidelity discipline) and no
// comment or string content is touched.
strip_testing_prefix :: (source: string) -> string {
    tokens := lex_source(source);
    edits: [..] Edit;
    for tok: tokens {
        if tok.kind != .IDENT continue;
        text := token_text(source, tok);
        if text.count > TESTING_PREFIX.count && slice(text, 0, TESTING_PREFIX.count) == TESTING_PREFIX {
            array_add(*edits, .{ start = tok.start, end = tok.end, text = slice(text, TESTING_PREFIX.count, text.count - TESTING_PREFIX.count) });
        }
    }
    return apply_edits(source, edits);
}

// The published Testing module content: the testing section with the
// Testing_ prefixes stripped, behind the standard Basic import line. The
// section's self-test blocks are retained (their prefixed calls strip to
// the bare published names) — the published module carries its own contract
// tests, the Testing special case's consumption surface (ticket 031/032).
publish_testing_module :: (source: string) -> (text: string, ok: bool) {
    section, ok := extract_testing_section(source);
    if !ok return "", false;
    return tprint("#import \"Basic\";\n\n%1\n", strip_testing_prefix(section)), true;
}

// ---------------------------------------------------------------------------
// juice_core generation
// ---------------------------------------------------------------------------

// The declaration line of the named constant: the line whose trimmed
// content starts with "<name>" followed by whitespace and then "::", copied
// verbatim (interior spacing included). The generated module re-declares
// the definition source's constant textually, so the literals can never
// drift from the Juice face.
extract_constant_line :: (source: string, name: string) -> (line: string, ok: bool) {
    lines := split(source, "\n");
    for ln: lines {
        trimmed := line_trimmed(ln);
        if trimmed.count <= name.count continue;
        if slice(trimmed, 0, name.count) != name continue;
        i := name.count;
        while i < trimmed.count && (trimmed[i] == #char " " || trimmed[i] == #char "\t") i += 1;
        if i + 1 < trimmed.count && trimmed[i] == #char ":" && trimmed[i + 1] == #char ":" return trimmed, true;
    }
    return "", false;
}

// The published juice_core module content: the generated header, the two
// verbatim built-in id constant declarations, then the #load closure by
// module-relative paths under the plugin face landing directory (ticket
// 049: the verbatim copies are published beside this module, and a #load
// inside a name-imported module resolves against the containing file's
// directory — the 048 decision 5 spike fact). No build-machine path is
// quoted, so the published modules/ tree relocates unchanged. A missing
// constant declaration is a loud failure (the closure would not compile
// without it).
publish_juice_core :: (module_source: string) -> (text: string, ok: bool) {
    load_line, ok1 := extract_constant_line(module_source, "TRANSPILE_PLUGIN_LOAD_ID");
    test_line, ok2 := extract_constant_line(module_source, "TRANSPILE_PLUGIN_TEST_BLOCK_ID");
    if !ok1 || !ok2 return "", false;

    builder: String_Builder;
    print_to_builder(*builder, "// juice_core generated module (ticket 030 publication): the\n");
    print_to_builder(*builder, "// plugin-facing module face, #load-ing the plugin face closure by\n");
    print_to_builder(*builder, "// module-relative paths under juice_internal/plugin_face/ (verbatim\n");
    print_to_builder(*builder, "// copies published beside this file — #load inside a name-imported\n");
    print_to_builder(*builder, "// module resolves against the containing file's directory, so the\n");
    print_to_builder(*builder, "// modules tree relocates unchanged; ticket 049). The built-in id\n");
    print_to_builder(*builder, "// constants are the definition source's own declaration lines (single\n");
    print_to_builder(*builder, "// source); the source file itself is not #loaded — its testing\n");
    print_to_builder(*builder, "// section carries self-test blocks. Regenerated by the publish step\n");
    print_to_builder(*builder, "// every build — never edit.\n");
    print_to_builder(*builder, "%1\n", load_line);
    print_to_builder(*builder, "%1\n", test_line);
    for file: JUICE_CORE_LOAD_FILES {
        print_to_builder(*builder, "#load \"%1/%2\";\n", juice_plugin_face_relative_dir(), file);
    }
    return builder_to_string(*builder), true;
}

// ---------------------------------------------------------------------------
// Landing paths
// ---------------------------------------------------------------------------

// The published module landing paths (spec §9.2: target/modules under the
// package's target directory). "/"-separated (front_slashes normalizes the
// input's separators).
juice_module_dir :: (target_dir: string) -> string {
    return front_slashes(tprint("%1/Juice", target_modules_dir(target_dir)));
}

juice_module_path :: (target_dir: string) -> string {
    return juice_module_path_in(target_modules_dir(target_dir));
}

testing_module_path :: (target_dir: string) -> string {
    return testing_module_path_in(target_modules_dir(target_dir));
}

juice_core_module_path :: (target_dir: string) -> string {
    return juice_core_module_path_in(target_modules_dir(target_dir));
}

// The same three faces expressed against a modules directory. The target
// directory forms above are the producer side (built from the target layout);
// these are what the installation unit needs, because the consumption side —
// a running executable — only ever knows its own modules directory
// (path_safety.juice_modules_dir). One definition each: the two spellings
// cannot drift.
juice_module_path_in :: (modules_dir: string) -> string {
    return front_slashes(tprint("%1/Juice/module.jai", modules_dir));
}

testing_module_path_in :: (modules_dir: string) -> string {
    return front_slashes(tprint("%1/Testing.jai", modules_dir));
}

juice_core_module_path_in :: (modules_dir: string) -> string {
    return front_slashes(tprint("%1/juice_core.jai", modules_dir));
}

// The internal publication directory under a modules directory: the
// non-module namespace for artifacts the tool consumes by absolute path
// (#load), never by name (#import). The ticket 037 discovery source lives
// here.
JUICE_INTERNAL_DIR :: "juice_internal";

// The landing paths of the internal artifacts take the modules directory
// itself, not the target directory the three module-face helpers take: the
// consumption side only knows juice_modules_dir() (<exe>/modules), so this
// is the one form both sides can share verbatim (dev tree and installed
// layout). Callers holding a target directory derive <target>/modules first.
juice_internal_dir :: (modules_dir: string) -> string {
    return front_slashes(tprint("%1/%2", modules_dir, JUICE_INTERNAL_DIR));
}

// The fourth publication (ticket 037, spec 006 decision 4): the verbatim
// copy of src/test_discovery.jai the generated test metaprogram #loads by
// absolute path. There is no transform function — publication is the
// identity; the byte-for-byte pin is the single-source proof.
test_discovery_module_path :: (modules_dir: string) -> string {
    return front_slashes(tprint("%1/test_discovery.jai", juice_internal_dir(modules_dir)));
}

// The plugin face closure copies (ticket 049): the four JUICE_CORE_LOAD_FILES
// sources published verbatim under the private juice_internal namespace.
// juice_plugin_face_relative_dir is the module-relative form the generated
// juice_core quotes; the landing helpers derive from the same constants, so
// the #load lines and the copy destinations cannot diverge (048 decision 4).
JUICE_PLUGIN_FACE_SUBDIR :: "plugin_face";

juice_plugin_face_relative_dir :: () -> string {
    return tprint("%1/%2", JUICE_INTERNAL_DIR, JUICE_PLUGIN_FACE_SUBDIR);
}

// Takes the modules directory itself (the test_discovery_module_path
// posture): the consumption side only knows <exe>/modules, and the producer
// derives <target>/modules first.
juice_plugin_face_dir :: (modules_dir: string) -> string {
    return front_slashes(tprint("%1/%2", modules_dir, juice_plugin_face_relative_dir()));
}

juice_plugin_face_file_path :: (modules_dir: string, file: string) -> string {
    return front_slashes(tprint("%1/%2", juice_plugin_face_dir(modules_dir), file));
}

// ---------------------------------------------------------------------------
// The installation unit and its compatibility marker (spec 0087 decision 28
// and acceptance group A16; ticket 0094)
// ---------------------------------------------------------------------------
//
// The shipped product is one unit: the executable plus the modules directory
// adjacent to it. A delivered installation is only usable when the executable
// and that directory come from the same release, so the publish step lands a
// marker beside the artifacts it wrote and every command checks it before any
// work starts.
//
// The marker carries three contract identifiers — the marker format, the
// compatibility epoch and the plugin entry ABI — plus the content digest of
// every published artifact. That covers the three ways an installation goes
// wrong in practice:
//
//   - a missing artifact, or a directory that was never published (missing
//     marker): the set is incomplete;
//   - a mixed set, where one artifact comes from a different release: its
//     digest no longer matches the marker;
//   - a release whose published contract changed: the epoch or the plugin ABI
//     differs, or the artifact list itself differs from the one this
//     executable was built to read.
//
// There is deliberately no fallback. The marker is read from the modules
// directory adjacent to the running executable and nowhere else — not from a
// global location, not from sibling development sources. A mismatch is a hard
// failure with its own diagnostic; juice never "repairs" an installation and
// never guesses which half is newer.
//
// INSTALL_COMPATIBILITY_VERSION is the release contract of the published
// face: bump it whenever the declaration schema, the published artifact set,
// the generated module faces or the plugin entry surface change in a way an
// executable from another release could not consume. The plugin ABI is not
// duplicated here: the marker carries the value of JUICE_PLUGIN_ABI_VERSION's
// own declaration line (src/plugin.jai), extracted the same way the build
// extracts JUICE_VERSION, and every executable compares it against the
// constant it compiled with.

INSTALL_MANIFEST_FILE_NAME :: "install_manifest.txt";
INSTALL_MANIFEST_VERSION :: 1;
INSTALL_COMPATIBILITY_VERSION :: 1;

// One published artifact of an installation: where it lands on this machine
// and the module-relative path the marker records (module-relative is what
// makes the marker independent of where the unit is installed).
Install_Artifact_Path :: struct {
    absolute_path: string;
    relative_path: string;
}

// One artifact digest, as the marker records it.
Install_Artifact :: struct {
    relative_path: string;
    digest:        string;
}

// A parsed marker.
Install_Manifest :: struct {
    manifest_version: s64;
    compatibility:    s64;
    plugin_abi:       s64;
    artifacts:        [..] Install_Artifact;
}

// One verification outcome: ok, or the one reason it failed (the caller
// prints it; the reason never replaces the failure with a fallback).
Install_Check :: struct {
    ok:     bool;
    reason: string;
}

install_manifest_relative_path :: () -> string {
    return tprint("%1/%2", JUICE_INTERNAL_DIR, INSTALL_MANIFEST_FILE_NAME);
}

install_manifest_path :: (modules_dir: string) -> string {
    return front_slashes(tprint("%1/%2", modules_dir, install_manifest_relative_path()));
}

// The complete published set of one installation, in publication order: the
// three module faces, the discovery source, then the plugin face closure
// copies in JUICE_CORE_LOAD_FILES order. This list is the single description
// of the set: the marker is generated from it and the verifier expects it, so
// a new published artifact joins both sides by joining this function.
install_artifact_paths :: (modules_dir: string) -> [..] Install_Artifact_Path {
    modules := front_slashes(modules_dir);
    paths: [..] Install_Artifact_Path;
    array_add(*paths, install_artifact_path(modules, juice_module_path_in(modules)));
    array_add(*paths, install_artifact_path(modules, testing_module_path_in(modules)));
    array_add(*paths, install_artifact_path(modules, juice_core_module_path_in(modules)));
    array_add(*paths, install_artifact_path(modules, test_discovery_module_path(modules)));
    for file: JUICE_CORE_LOAD_FILES {
        array_add(*paths, install_artifact_path(modules, juice_plugin_face_file_path(modules, file)));
    }
    return paths;
}

// One landing path, with the marker's module-relative form derived from it. A
// path that does not sit under the modules directory keeps its absolute
// spelling, which install_relative_path_is_valid then rejects — a marker must
// never record a machine-specific path. The returned strings are heap-stable:
// the set outlives the temporary allocator's next print (the paths are used
// across the writer's file calls and the verifier's reads).
install_artifact_path :: (modules_dir: string, absolute_path: string) -> Install_Artifact_Path {
    prefix := tprint("%1/", modules_dir);
    relative := absolute_path;
    if find_index_from_left(absolute_path, prefix) == 0 {
        relative = slice(absolute_path, prefix.count, absolute_path.count - prefix.count);
    }
    return .{ absolute_path = copy_string(absolute_path), relative_path = copy_string(relative) };
}

install_relative_path_is_valid :: (relative_path: string) -> bool {
    if relative_path == "" return false;
    if relative_path[0] == #char "/" || relative_path[0] == #char "\\" return false;
    if find_index_from_left(relative_path, "\\") >= 0 return false;
    if find_index_from_left(relative_path, ":") >= 0 return false;
    return true;
}

// FNV-1a 64 over the artifact text, rendered as 16 lowercase hex characters
// (the same digest primitive the view cache uses; it is an integrity check
// against mixing releases, not a cryptographic signature).
install_artifact_digest :: (text: string) -> string {
    hash := fnv1a_hash(text.data, text.count);
    out: [16] u8;
    for i: 0..15 {
        nibble := cast(s64) ((hash >> cast(u64) (4 * (15 - i))) & 0xf);
        out[i] = cast(u8) ifx nibble < 10 then #char "0" + nibble else #char "a" + (nibble - 10);
    }
    return copy_string(to_string(out.data, 16));
}

// The integer value of a constant declaration line (`NAME :: VALUE;`, the
// extract_constant_line shape). Anything else — a near-miss name, a missing or
// non-numeric value, trailing text — fails, so a marker can never be generated
// from a guess about the plugin ABI.
constant_integer_value :: (line: string, name: string) -> (value: s64, ok: bool) {
    trimmed := line_trimmed(line);
    if trimmed.count <= name.count return 0, false;
    if slice(trimmed, 0, name.count) != name return 0, false;
    cursor := name.count;
    while cursor < trimmed.count && (trimmed[cursor] == #char " " || trimmed[cursor] == #char "\t") cursor += 1;
    if cursor + 1 >= trimmed.count return 0, false;
    if trimmed[cursor] != #char ":" || trimmed[cursor + 1] != #char ":" return 0, false;
    cursor += 2;
    while cursor < trimmed.count && (trimmed[cursor] == #char " " || trimmed[cursor] == #char "\t") cursor += 1;
    start := cursor;
    result: s64 = 0;
    while cursor < trimmed.count {
        character := trimmed[cursor];
        if character < #char "0" || character > #char "9" break;
        result = result * 10 + cast(s64) (character - #char "0");
        cursor += 1;
    }
    if cursor == start return 0, false;
    while cursor < trimmed.count && (trimmed[cursor] == #char " " || trimmed[cursor] == #char "\t") cursor += 1;
    if cursor >= trimmed.count || trimmed[cursor] != #char ";" return 0, false;
    cursor += 1;
    while cursor < trimmed.count && (trimmed[cursor] == #char " " || trimmed[cursor] == #char "\t") cursor += 1;
    if cursor != trimmed.count return 0, false;
    return result, true;
}

parse_decimal_integer :: (text: string) -> (value: s64, ok: bool) {
    if text == "" return 0, false;
    result: s64 = 0;
    for character: text {
        if character < #char "0" || character > #char "9" return 0, false;
        result = result * 10 + cast(s64) (character - #char "0");
    }
    return result, true;
}

// One `<key> <integer>` marker line.
marker_field_value :: (line: string, key: string) -> (value: s64, ok: bool) {
    if line.count <= key.count + 1 return 0, false;
    if slice(line, 0, key.count) != key return 0, false;
    if line[key.count] != #char " " return 0, false;
    value, ok := parse_decimal_integer(slice(line, key.count + 1, line.count - key.count - 1));
    return value, ok;
}

marker_string_is_digest :: (text: string) -> bool {
    if text.count != 16 return false;
    for character: text {
        if character >= #char "0" && character <= #char "9" continue;
        if character >= #char "a" && character <= #char "f" continue;
        return false;
    }
    return true;
}

// The marker text for one published set. `texts` is aligned with
// install_artifact_paths (the same publication order). An incomplete set, an
// unusable plugin ABI line or an unusable landing path is a loud failure: a
// half-described installation must never be publishable.
publish_install_manifest :: (modules_dir: string, plugin_abi_line: string, texts: [] string) -> (text: string, ok: bool) {
    plugin_abi, abi_ok := constant_integer_value(plugin_abi_line, "JUICE_PLUGIN_ABI_VERSION");
    if !abi_ok return "", false;
    paths := install_artifact_paths(modules_dir);
    if texts.count != paths.count return "", false;
    builder: String_Builder;
    print_to_builder(*builder, "juice-install-manifest %1\n", INSTALL_MANIFEST_VERSION);
    print_to_builder(*builder, "compatibility %1\n", INSTALL_COMPATIBILITY_VERSION);
    print_to_builder(*builder, "plugin_abi %1\n", plugin_abi);
    print_to_builder(*builder, "artifacts %1\n", paths.count);
    for path, index: paths {
        if !install_relative_path_is_valid(path.relative_path) return "", false;
        print_to_builder(*builder, "%1 %2\n", path.relative_path, install_artifact_digest(texts[index]));
    }
    return builder_to_string(*builder), true;
}

// The marker's parse. Every structural deviation — a missing header field, a
// truncated or over-long artifact list, an artifact line without exactly one
// digest, trailing lines — fails: a damaged marker must never degrade into an
// empty or partial expectation.
parse_install_manifest :: (text: string) -> (Install_Manifest, bool) {
    result: Install_Manifest;
    lines := split(text, "\n");
    if lines.count < 5 return result, false;
    if lines[lines.count - 1] != "" return result, false;
    line_count := lines.count - 1;

    manifest_version, version_ok := marker_field_value(lines[0], "juice-install-manifest");
    if !version_ok return result, false;
    compatibility, compatibility_ok := marker_field_value(lines[1], "compatibility");
    if !compatibility_ok return result, false;
    plugin_abi, abi_ok := marker_field_value(lines[2], "plugin_abi");
    if !abi_ok return result, false;
    artifact_count, count_ok := marker_field_value(lines[3], "artifacts");
    if !count_ok return result, false;
    if artifact_count < 0 return result, false;
    if line_count != 4 + artifact_count return result, false;

    result.manifest_version = manifest_version;
    result.compatibility = compatibility;
    result.plugin_abi = plugin_abi;
    for i: 4..line_count - 1 {
        line := lines[i];
        space := find_index_from_left(line, " ");
        if space <= 0 return .{}, false;
        relative_path := slice(line, 0, space);
        digest := slice(line, space + 1, line.count - space - 1);
        if !install_relative_path_is_valid(relative_path) return .{}, false;
        if !marker_string_is_digest(digest) return .{}, false;
        array_add(*result.artifacts, .{ relative_path = copy_string(relative_path), digest = copy_string(digest) });
    }
    return result, true;
}

// Verification of one installation: the marker describes this executable's
// release and every artifact beside it still matches the marker. `ok = false`
// carries the single reason, which the caller prints; nothing here repairs,
// retries or looks elsewhere for a set.
verify_install :: (modules_dir: string, expected_plugin_abi: s64) -> Install_Check {
    check: Install_Check;
    modules := front_slashes(modules_dir);
    marker_path := install_manifest_path(modules);
    text, read_ok := read_entire_file(marker_path);
    if !read_ok {
        check.reason = tprint("the installation marker is missing: %1", marker_path);
        return check;
    }
    manifest, parsed := parse_install_manifest(text);
    if !parsed {
        check.reason = tprint("the installation marker is malformed: %1", marker_path);
        return check;
    }
    if manifest.manifest_version != INSTALL_MANIFEST_VERSION {
        check.reason = tprint("the installation marker uses format %1, this executable reads %2",
                              manifest.manifest_version, INSTALL_MANIFEST_VERSION);
        return check;
    }
    if manifest.compatibility != INSTALL_COMPATIBILITY_VERSION {
        check.reason = tprint("the installation marker declares release compatibility %1, this executable requires %2",
                              manifest.compatibility, INSTALL_COMPATIBILITY_VERSION);
        return check;
    }
    if manifest.plugin_abi != expected_plugin_abi {
        check.reason = tprint("the installation marker declares plugin ABI %1, this executable supports %2",
                              manifest.plugin_abi, expected_plugin_abi);
        return check;
    }
    paths := install_artifact_paths(modules);
    if manifest.artifacts.count != paths.count {
        check.reason = tprint("the installation marker describes %1 artifacts, this executable's release publishes %2",
                              manifest.artifacts.count, paths.count);
        return check;
    }
    for path, index: paths {
        if manifest.artifacts[index].relative_path != path.relative_path {
            check.reason = tprint("the installation marker describes %1 where this executable's release publishes %2",
                                  manifest.artifacts[index].relative_path, path.relative_path);
            return check;
        }
    }
    for path, index: paths {
        content, content_ok := read_entire_file(path.absolute_path);
        if !content_ok {
            check.reason = tprint("the installed artifact %1 is missing", path.relative_path);
            return check;
        }
        if install_artifact_digest(content) != manifest.artifacts[index].digest {
            check.reason = tprint("the installed artifact %1 does not match the published release (content digest mismatch)", path.relative_path);
            return check;
        }
    }
    check.ok = true;
    return check;
}

// The executable-side gate: verify the unit adjacent to the running
// executable and explain any failure in the operator's terms. Every command
// runs this before it touches a package, so a broken installation fails once,
// loudly, instead of producing a downstream error that looks like a user
// mistake.
require_compatible_install :: (modules_dir: string, expected_plugin_abi: s64) -> bool {
    check := verify_install(modules_dir, expected_plugin_abi);
    if check.ok return true;
    print("[juice ERROR] This juice executable and its adjacent modules directory are not one compatible installation.\n");
    print("[juice ERROR] %\n", check.reason);
    print("[juice ERROR] Installation: %\n", front_slashes(modules_dir));
    print("[juice] The executable and modules/ must be delivered, upgraded and rolled back together; juice does not fall back to another installation or to development sources.\n");
    return false;
}

// The publish step's writer, shared by the bootstrap metaprogram and the test
// scaffolding so one code path produces an installation: every artifact in
// install_artifact_paths order, then the marker describing them. The caller
// reads every source first (no partial publication); this function only
// writes, and the marker is written last so an interrupted write leaves an
// installation that fails verification instead of one that looks complete.
publish_install_set :: (modules_dir: string, plugin_abi_line: string, texts: [] string) -> (failure: string, ok: bool) {
    paths := install_artifact_paths(modules_dir);
    if texts.count != paths.count {
        return tprint("the published set is incomplete: %1 of %2 artifacts", texts.count, paths.count), false;
    }
    marker, marker_ok := publish_install_manifest(modules_dir, plugin_abi_line, texts);
    if !marker_ok return "the installation marker could not be generated", false;
    for path: paths {
        directory := path_strip_filename(path.absolute_path);
        if !make_directory_if_it_does_not_exist(directory, recursive = true) {
            return tprint("could not create %1", directory), false;
        }
    }
    for path, index: paths {
        if !write_entire_file(path.absolute_path, texts[index]) {
            return tprint("could not write %1", path.absolute_path), false;
        }
    }
    marker_path := install_manifest_path(modules_dir);
    if !write_entire_file(marker_path, marker) return tprint("could not write %1", marker_path), false;
    return "", true;
}
