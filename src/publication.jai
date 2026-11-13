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
    return front_slashes(tprint("%1/Juice/module.jai", target_modules_dir(target_dir)));
}

testing_module_path :: (target_dir: string) -> string {
    return front_slashes(tprint("%1/Testing.jai", target_modules_dir(target_dir)));
}

juice_core_module_path :: (target_dir: string) -> string {
    return front_slashes(tprint("%1/juice_core.jai", target_modules_dir(target_dir)));
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
