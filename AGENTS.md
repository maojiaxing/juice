# Development Rules

## Conversational Style

- Keep answers short and concise
- No emojis in commits, issues, PR comments, or code
- No fluff or cheerful filler text (e.g., "Thanks @user" not "Thanks so much @user!")
- Technical prose only, be direct
- Use concise, clear, simple language. Define unavoidable jargon before using it.
- Explain non-trivial designs and problems as: problem, concrete example or short trace, then solution. State why the solution is necessary and distinguish it from optional complexity.
- Prefer concrete behavior and small illustrations over abstract summaries, dense terminology, or unexplained lists of changes.
- When the user asks a question, answer it first before making edits or running implementation commands.
- When responding to user feedback or an analysis, explicitly say whether you agree or disagree before saying what you changed.

## Code Quality

- Read files in full before wide-ranging changes, before editing files you have not fully inspected, and when asked to investigate or audit. Do not rely on code search snippets or partial AST dumps for broad changes.
- No *void or unconstrained Any types unless strictly necessary for low-level C FFI, generic memory allocators, or performance-critical heterogeneous storage. Leverage compile-time polymorphism ($T / $$T) for type-safe abstractions.
- Inline single-line helpers that have only one call site to eliminate unnecessary indirection and function call overhead.
- Never remove or downgrade code to fix compiler error or type mismatch caused by updated language features or external modules; update and adapt the code to match the newer specs instead.
- Prefer .{} for struct composite literals and object declarations when the type can be inferred or is explicitly declared (e.g., p := .{ x = 10, y = 20 } or p: Point = .{ 10, 20 }). While Jai allows explicit initialization like Point.{ 10, 20 }, you should always prioritize the clean, modern .{} syntax. Avoid unnecessarily repeating explicit type names during variable initialization.
- Variable names and parameter names should not be abbreviated.

## User Override

If the user's instructions conflict with any rule in this document, ask for explicit confirmation before overriding. Only then execute their instructions.
