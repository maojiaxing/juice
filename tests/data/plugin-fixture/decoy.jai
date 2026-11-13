// Fixture plugin package decoy (ticket 025 E2E): the false-positive
// surface the scan must skip — the note text inside a string literal and a
// comment, a plugin note hanging on a declaration that is not
// get_juice_plugin, and a get_juice_plugin reference at a non-statement
// position. None of these is an anchor, so this file contributes no hit.
// It is scanned but never compiled (the E2E driver only imports the two
// anchored modules), so its references may stay unresolved.
#import "Basic";
#import "juice_core";

// "@juice_plugin" inside a comment is trivia, not an anchor.

NOTE_TEXT :: "@juice_plugin";

decoy_proc :: () -> string {
    return "@juice_plugin";
} @juice_plugin

call_site :: () {
    p := get_juice_plugin;
}
