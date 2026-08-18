# Panic: `peek()` called at EOF without checking current token (parse_script ONLY)

**Found by:** `parse_script` only — reproduced against `parse_module` and `parse_program_tsx`
too during triage and does NOT panic there, which is exactly the kind of grammar-path
divergence this additive target exists to fuzz (see mayhem/fuzz/fuzz_targets/parse_script.rs).

**Reproducer:** `repro.txt` — 8 bytes: `class C{` (an unterminated class body — opening brace,
no members, no closing brace, immediate EOF).

**Trigger:** feed `class C{` to `deno_ast::parse_script` (MediaType::JavaScript, Script
grammar), built with `--debug-assertions` (cargo-fuzz's default).

**Panic:**
```
thread '<unnamed>' panicked at swc_ecma_lexer-26.0.0/src/common/parser/class_and_fn.rs:923:17:
parser should not call peek() without knowing current token.
Current token is <eof>
```

**Root cause (upstream dependency, not deno_ast's own code):** the class-member parser, on
seeing `{` with nothing before EOF, calls `peek()` to look ahead for a modifier/method-name
disambiguation (the same lookahead used to tell `get`/`set`/`async`/`static` modifiers apart
from method names) without first confirming a current token exists — `swc_ecma_lexer` has an
internal invariant ("parser should not call peek() without knowing current token") that this
exact truncated-body shape violates only through the Script-grammar entry point; parse_module
and parse_program_tsx's class-body handling takes a different path that reports a normal
`Eof`-kind `SyntaxError` instead of reaching this unguarded `peek()`.

**Impact:** a real, deterministic, 8-byte-reproducible panic on a plausible input (any
truncated/incomplete JS "script" — e.g. a partially-uploaded or streamed file cut off
mid-class) — a denial-of-service for any process that calls `deno_ast::parse_script` on
untrusted/partial text without `catch_unwind`.

**Suggested upstream fix:** in `swc_ecma_lexer`'s class-body member parser, check
`cur().is_eof()` (or equivalent) before calling the disambiguating `peek()`, and emit the
normal unexpected-EOF diagnostic instead.

Not guarded in the harness — this is a genuine parser panic, not a harness misuse issue.
