// Fixture plugin anchor (scan-only; derives the module name "extra" from
// the file stem — it collides with first-plugin's extra.jai).
get_juice_plugin :: () -> *X { return null; } @juice_plugin
