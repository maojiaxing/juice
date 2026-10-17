// The extension-syntax file: `x := try half(n);` lowers to a multi-return
// error check (the try/catch plugin, MULTI_RETURN convention) — the mirror
// view carries the lowered code.
Error :: enum {
    NONE;
    NEGATIVE;
}

half :: (n: int) -> Error, int {
    if n < 0 return .NEGATIVE, 0;
    return .NONE, n / 2;
}

double :: (n: int) -> Error, int {
    x := try half(n);
    return .NONE, x * 4;
}
