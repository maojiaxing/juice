// Juice process-internal source-to-source transpiler infrastructure (ADR
// 0004): the shared types (Transpile_Mode / Load_Target / Transpile_Context
// / Test_Entry / Transpile_Diagnostic / Transpile_Result), the lexer, the
// edit mechanism and the line-fidelity helpers. The pipeline itself — the
// plugin interface, the two built-in plugins and the transpile_source
// runner — lives in src/transpile_plugin.jai, loaded right after this file
// in both build.jai and main.jai. No IO, no global state.
//
// Output contract (docs/transpiled-output-formatting.md, ADR 0005):
// every view has exactly as many lines as its source file; verbatim regions
// (everything that is not an edit point) are copied byte for byte; output
// uses "\n" line endings everywhere. Edit points are token-bounded: test
// header replacement, the "@test" tag, in-package #load placeholders, and
// build-mode #load target rewrites.

#import "Basic";
#import "String";

Transpile_Mode :: enum u8 {
    STRIP;   // build: test blocks become line-preserving comment placeholders,
             // in-package #load target strings are rewritten to view paths.
    EXPAND;  // test: test blocks become juice_test_N procedures, in-package
             // #load statements become line-preserving comment placeholders.
}

// One in-package #load rewrite entry: `from` is the resolved package-relative
// target path ("/" separated, exactly as resolve_load_target returns it);
// `to` is the string written into the view in place of the target literal.
Load_Target :: struct {
    from: string;
    to:   string;
}

Transpile_Context :: struct {
    mode: Transpile_Mode;
    // Package-relative path of the source file, "/" separated (e.g.
    // "src/foo.jai"). Derives anonymous test names and resolves #load targets.
    path: string;
    // Number assigned to this file's first test. Global test-list ordering
    // (files in discovery order, tests in source order) is the caller's
    // responsibility; tests within one file are numbered sequentially.
    next_test_number: s64;
    // STRIP mode only: rewrite targets for literal in-package #load statements.
    load_targets: [] Load_Target;
    // Registry-driven pipeline (spec 0060 decision 3): the registered
    // plugins, declaration order = dispatch order. An empty list means the
    // default pipeline (the two built-in plugins) — every existing caller
    // keeps its behavior unchanged.
    plugins: [..] Transpile_Plugin;
    // Per-plugin cross-file state slots, aligned with plugins order (spec
    // 0060 decision 2's Transpile_Context extension fields): each plugin
    // casts its slot to its own state type; the caller owns the slot's
    // storage, which persists across transpile_source calls (the same
    // channel family as next_test_number's numbering continuation). The
    // default pipeline uses no slots (null).
    plugin_state: [..] *void;
}

Test_Entry :: struct {
    name:   string;  // report name: the source token's string value for named
                     // tests, "package-relative path:line" for anonymous ones.
    number: s64;     // N in juice_test_N
    line:   s64;     // original file line of the `test` token
}

Transpile_Diagnostic :: struct {
    line:    s64;
    column:  s64;
    message: string;
}

Transpile_Result :: struct {
    view:        string;
    tests:       [..] Test_Entry;
    diagnostics: [..] Transpile_Diagnostic;
}

// ---------------------------------------------------------------------------
// Lexer
// ---------------------------------------------------------------------------

Token_Kind :: enum u8 {
    IDENT;
    STRING;
    NUMBER;
    DIRECTIVE;
    PUNCT;
}

Token :: struct {
    kind:     Token_Kind;
    start:    s64;  // byte offset, inclusive
    end:      s64;  // byte offset, exclusive
    line:     s64;  // 1-based line of the token start
    column:   s64;  // 1-based column of the token start
    end_line: s64;  // 1-based line of the token end (multi-line strings)
}

is_ident_start :: (c: u8) -> bool {
    return (c >= #char "a" && c <= #char "z") || (c >= #char "A" && c <= #char "Z") || c == #char "_";
}

is_ident_char :: (c: u8) -> bool {
    return is_ident_start(c) || (c >= #char "0" && c <= #char "9");
}

is_digit_char :: (c: u8) -> bool {
    return c >= #char "0" && c <= #char "9";
}

TWO_CHAR_OPS :: string.[
    "::", ":=", "->", "==", "!=", "<=", ">=", "&&", "||", "<<", ">>",
    "++", "--", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "..",
];

// Tokenize the whole file. Trivia (whitespace, line comments, nested block
// comments) is consumed and only reflected in the gaps between token spans.
lex_source :: (source: string) -> [..] Token {
    tokens: [..] Token;
    line := 1;
    column := 1;
    i := 0;
    while i < source.count {
        c := source[i];

        if c == #char " " || c == #char "\t" || c == #char "\n" {
            if c == #char "\n" {
                line += 1;
                column = 1;
            } else {
                column += 1;
            }
            i += 1;
            continue;
        }

        if c == #char "/" && i + 1 < source.count {
            if source[i+1] == #char "/" {
                while i < source.count && source[i] != #char "\n" {
                    i += 1;
                    column += 1;
                }
                continue;
            }
            if source[i+1] == #char "*" {
                i += 2;
                column += 2;
                nesting := 1;
                while i < source.count && nesting > 0 {
                    if source[i] == #char "\n" {
                        line += 1;
                        column = 1;
                        i += 1;
                        continue;
                    }
                    if i + 1 < source.count && source[i] == #char "/" && source[i+1] == #char "*" {
                        nesting += 1;
                        i += 2;
                        column += 2;
                        continue;
                    }
                    if i + 1 < source.count && source[i] == #char "*" && source[i+1] == #char "/" {
                        nesting -= 1;
                        i += 2;
                        column += 2;
                        continue;
                    }
                    i += 1;
                    column += 1;
                }
                continue;
            }
        }

        if c == #char "#" && i + 1 < source.count && is_ident_start(source[i+1]) {
            start := i;
            start_line := line;
            start_col := column;
            i += 2;
            column += 2;
            while i < source.count && is_ident_char(source[i]) {
                i += 1;
                column += 1;
            }
            array_add(*tokens, .{kind = .DIRECTIVE, start = start, end = i, line = start_line, column = start_col, end_line = line});
            continue;
        }

        if c == #char "\"" {
            start := i;
            start_line := line;
            start_col := column;
            i += 1;
            column += 1;
            while i < source.count {
                ch := source[i];
                if ch == #char "\n" {
                    line += 1;
                    column = 1;
                    i += 1;
                    continue;
                }
                if ch == #char "\\" && i + 1 < source.count {
                    i += 2;
                    column += 2;
                    continue;
                }
                if ch == #char "\"" {
                    i += 1;
                    column += 1;
                    break;
                }
                i += 1;
                column += 1;
            }
            array_add(*tokens, .{kind = .STRING, start = start, end = i, line = start_line, column = start_col, end_line = line});
            continue;
        }

        if is_digit_char(c) {
            start := i;
            start_line := line;
            start_col := column;
            while i < source.count && (is_ident_char(source[i]) || source[i] == #char ".") {
                i += 1;
                column += 1;
            }
            array_add(*tokens, .{kind = .NUMBER, start = start, end = i, line = start_line, column = start_col, end_line = line});
            continue;
        }

        if is_ident_start(c) {
            start := i;
            start_line := line;
            start_col := column;
            while i < source.count && is_ident_char(source[i]) {
                i += 1;
                column += 1;
            }
            array_add(*tokens, .{kind = .IDENT, start = start, end = i, line = start_line, column = start_col, end_line = line});
            continue;
        }

        if i + 1 < source.count {
            pair := slice(source, i, 2);
            matched := false;
            for op: TWO_CHAR_OPS {
                if pair == op {
                    matched = true;
                    break;
                }
            }
            if matched {
                array_add(*tokens, .{kind = .PUNCT, start = i, end = i + 2, line = line, column = column, end_line = line});
                i += 2;
                column += 2;
                continue;
            }
        }

        array_add(*tokens, .{kind = .PUNCT, start = i, end = i + 1, line = line, column = column, end_line = line});
        i += 1;
        column += 1;
    }
    return tokens;
}

token_text :: (s: string, tok: Token) -> string {
    return slice(s, tok.start, tok.end - tok.start);
}

compute_line_starts :: (s: string) -> [..] s64 {
    starts: [..] s64;
    array_add(*starts, 0);
    for i: 0..s.count-1 {
        if s[i] == #char "\n" array_add(*starts, i + 1);
    }
    return starts;
}

// Exclusive end offset of line line_0's content (just past its last char).
line_content_end :: (s: string, starts: [] s64, line_0: s64) -> s64 {
    if line_0 + 1 < starts.count return starts[line_0 + 1] - 1;
    return s.count;
}

first_non_whitespace :: (s: string, from: s64, to: s64) -> s64 {
    i := from;
    while i < to && (s[i] == #char " " || s[i] == #char "\t") i += 1;
    return i;
}

// ---------------------------------------------------------------------------
// String literal helpers
// ---------------------------------------------------------------------------

is_hex_digit :: (c: u8) -> bool {
    return is_digit_char(c) || (c >= #char "a" && c <= #char "f") || (c >= #char "A" && c <= #char "F");
}

hex_value :: (c: u8) -> s64 {
    if is_digit_char(c) return cast(s64) (c - #char "0");
    if c >= #char "a" && c <= #char "f" return cast(s64) (c - #char "a") + 10;
    return cast(s64) (c - #char "A") + 10;
}

// Decode the content of a Jai string literal (without the surrounding
// quotes). Known escapes are decoded; unknown escapes are kept verbatim so
// that backslash-separated paths survive.
decode_jai_string :: (content: string) -> string {
    builder: String_Builder;
    i := 0;
    while i < content.count {
        ch := content[i];
        if ch == #char "\\" && i + 1 < content.count {
            next := content[i+1];
            if next == #char "\\" { print_to_builder(*builder, "\\"); i += 2; }
            else if next == #char "\"" { print_to_builder(*builder, "\""); i += 2; }
            else if next == #char "n" { print_to_builder(*builder, "\n"); i += 2; }
            else if next == #char "t" { print_to_builder(*builder, "\t"); i += 2; }
            else if next == #char "r" { print_to_builder(*builder, "\r"); i += 2; }
            else if next == #char "0" { print_to_builder(*builder, "\0"); i += 2; }
            else if next == #char "x" && i + 3 < content.count && is_hex_digit(content[i+2]) && is_hex_digit(content[i+3]) {
                byte: u8 = cast(u8) (hex_value(content[i+2]) * 16 + hex_value(content[i+3]));
                tmp: [1] u8;
                tmp[0] = byte;
                print_to_builder(*builder, "%", to_string(tmp.data, 1));
                i += 4;
            }
            else {
                print_to_builder(*builder, "%", slice(content, i, 2));
                i += 2;
            }
        } else {
            print_to_builder(*builder, "%", slice(content, i, 1));
            i += 1;
        }
    }
    return builder_to_string(*builder);
}

HEX_CHARS :: "0123456789abcdef";

// Escape a string for embedding into a Jai string literal. Backslash, quote
// and control characters are escaped; everything else is passed through.
escape_jai_string :: (s: string) -> string {
    builder: String_Builder;
    for ch: s {
        if ch == #char "\\" { print_to_builder(*builder, "\\\\"); }
        else if ch == #char "\"" { print_to_builder(*builder, "\\\""); }
        else if ch == #char "\n" { print_to_builder(*builder, "\\n"); }
        else if ch == #char "\t" { print_to_builder(*builder, "\\t"); }
        else if ch == #char "\r" { print_to_builder(*builder, "\\r"); }
        else if ch < 32 {
            print_to_builder(*builder, "\\x%%", HEX_CHARS[ch >> 4], HEX_CHARS[ch & 15]);
        }
        else {
            tmp: [1] u8;
            tmp[0] = ch;
            print_to_builder(*builder, "%", to_string(tmp.data, 1));
        }
    }
    return builder_to_string(*builder);
}

quote_jai_string :: (s: string) -> string {
    return tprint("\"%1\"", escape_jai_string(s));
}

// ---------------------------------------------------------------------------
// #load target resolution
// ---------------------------------------------------------------------------

is_absolute_load_target :: (value: string) -> bool {
    if value == "" return false;
    if value[0] == #char "/" return true;
    for ch: value {
        if ch == #char ":" return true;
    }
    return false;
}

// Resolve a #load target against the current file's package-relative path
// (both "/" separated). Returns the canonical in-package relative path and
// true when the target stays inside the package root; absolute targets and
// targets escaping via ".." are out-of-package (false).
resolve_load_target :: (current_file: string, target: string) -> string, bool {
    value := copy_string(target);
    for i: 0..value.count-1 {
        if value[i] == #char "\\" value[i] = #char "/";
    }
    if value == "" || is_absolute_load_target(value) return "", false;

    dir := "";
    for i: 0..current_file.count-1 {
        if current_file[i] == #char "/" dir = slice(current_file, 0, i);
    }
    combined := ifx dir == "" then value else tprint("%1/%2", dir, value);

    parts := split(combined, "/");
    kept: [..] string;
    for part: parts {
        if part == "" || part == "." continue;
        if part == ".." {
            if kept.count == 0 return "", false;
            kept.count -= 1;
        } else {
            array_add(*kept, part);
        }
    }
    if kept.count == 0 return "", false;

    builder: String_Builder;
    for part, idx: kept {
        if idx > 0 print_to_builder(*builder, "/");
        print_to_builder(*builder, "%", part);
    }
    return builder_to_string(*builder), true;
}

find_load_target :: (targets: [] Load_Target, resolved: string) -> string, bool {
    for target: targets {
        if target.from == resolved return target.to, true;
    }
    return "", false;
}

// ---------------------------------------------------------------------------
// Edits and output assembly
// ---------------------------------------------------------------------------

Edit :: struct {
    start: s64;
    end:   s64;
    text:  string;
}

// Normalize line endings to "\n". Returns the input untouched when no "\r"
// is present, so untouched files round-trip byte for byte.
normalize_view_line_endings :: (s: string) -> string {
    has_cr := false;
    for ch: s {
        if ch == #char "\r" {
            has_cr = true;
            break;
        }
    }
    if !has_cr return s;

    builder: String_Builder;
    cursor := 0;
    i := 0;
    while i < s.count {
        if s[i] == #char "\r" {
            print_to_builder(*builder, "%", slice(s, cursor, i - cursor));
            print_to_builder(*builder, "\n");
            if i + 1 < s.count && s[i+1] == #char "\n" i += 1;
            cursor = i + 1;
        }
        i += 1;
    }
    if cursor < s.count print_to_builder(*builder, "%", slice(s, cursor, s.count - cursor));
    return builder_to_string(*builder);
}

// Edits are recorded during the left-to-right scan but not necessarily in
// output order (the "@test" insertion is recorded when the anchor is seen,
// before edits inside the body). Sort by start offset before applying; the
// regions are disjoint by construction.
sort_edits :: (edits: [] Edit) {
    for i: 1..edits.count-1 {
        if i >= edits.count break;
        key := edits[i];
        j := i - 1;
        while j >= 0 && edits[j].start > key.start {
            edits[j+1] = edits[j];
            j -= 1;
        }
        edits[j+1] = key;
    }
}

apply_edits :: (s: string, edits: [] Edit) -> string {
    if edits.count == 0 return s;
    sort_edits(edits);
    builder: String_Builder;
    cursor := 0;
    for edit: edits {
        print_to_builder(*builder, "%", slice(s, cursor, edit.start - cursor));
        print_to_builder(*builder, "%", edit.text);
        cursor = edit.end;
    }
    print_to_builder(*builder, "%", slice(s, cursor, s.count - cursor));
    return builder_to_string(*builder);
}

// Comment placeholder for a stripped test block: first line carries the
// block's original text, every further line is a plain marker. The first
// line's original text ends at the block's own closing brace (a one-line
// block may share its line with another block or trailing trivia).
strip_block_edit :: (s: string, starts: [] s64, test_tok: Token, close_tok: Token) -> Edit {
    builder: String_Builder;
    first_end := line_content_end(s, starts, test_tok.line - 1);
    if close_tok.line == test_tok.line && close_tok.end < first_end first_end = close_tok.end;
    print_to_builder(*builder, "// juice: test stripped: %", slice(s, test_tok.start, first_end - test_tok.start));
    line_0 := test_tok.line;
    while line_0 < close_tok.line {
        line_start := starts[line_0];
        line_end := line_content_end(s, starts, line_0);
        ws_end := first_non_whitespace(s, line_start, line_end);
        print_to_builder(*builder, "\n%", slice(s, line_start, ws_end - line_start));
        print_to_builder(*builder, "// juice: test stripped");
        line_0 += 1;
    }
    return .{start = test_tok.start, end = close_tok.end, text = builder_to_string(*builder)};
}

// Comment placeholder for a stripped in-package #load statement. The first
// line carries the original line text; further lines (a statement spanning
// K > 1 lines) get the "(cont)" marker. Leading whitespace of every
// replaced line is replicated.
load_strip_edit :: (s: string, starts: [] s64, load_tok: Token, semi_tok: Token) -> Edit {
    builder: String_Builder;
    first_end := line_content_end(s, starts, load_tok.line - 1);
    print_to_builder(*builder, "// juice: load stripped: %", slice(s, load_tok.start, first_end - load_tok.start));
    line_0 := load_tok.line;
    while line_0 < semi_tok.line {
        line_start := starts[line_0];
        line_end := line_content_end(s, starts, line_0);
        ws_end := first_non_whitespace(s, line_start, line_end);
        print_to_builder(*builder, "\n%", slice(s, line_start, ws_end - line_start));
        print_to_builder(*builder, "// juice: load stripped (cont)");
        line_0 += 1;
    }
    return .{start = load_tok.start, end = semi_tok.end, text = builder_to_string(*builder)};
}

// ---------------------------------------------------------------------------
// Anchor machinery (shared with the test-block plugin in transpile_plugin.jai)
// ---------------------------------------------------------------------------

find_matching_close :: (s: string, tokens: [] Token, open_index: s64) -> s64, bool {
    depth := 0;
    j := open_index;
    while j < tokens.count {
        text := token_text(s, tokens[j]);
        if tokens[j].kind == .PUNCT && text == "{" {
            depth += 1;
        } else if tokens[j].kind == .PUNCT && text == "}" {
            depth -= 1;
            if depth == 0 return j, true;
        }
        j += 1;
    }
    return 0, false;
}

is_statement_position :: (have_prev: bool, prev_text: string) -> bool {
    if !have_prev return true;
    return prev_text == ";" || prev_text == "}" || prev_text == "{";
}

// Whether the token at `index` starts a test block anchor: `test` + string
// + `{`, or `test` + `{`.
is_test_anchor :: (s: string, tokens: [] Token, index: s64) -> bool {
    if index >= tokens.count return false;
    if tokens[index].kind != .IDENT || token_text(s, tokens[index]) != "test" return false;
    if index + 1 < tokens.count && token_text(s, tokens[index + 1]) == "{" return true;
    if index + 2 < tokens.count && tokens[index + 1].kind == .STRING && token_text(s, tokens[index + 2]) == "{" return true;
    return false;
}
