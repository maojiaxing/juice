// Fixture plugin anchor (scan-only — this file is never compiled): the
// lexical scan recognizes the get_juice_plugin declaration by its
// @juice_plugin tail note. The return type stays unresolved on purpose.
get_juice_plugin :: () -> *X { return null; } @juice_plugin
