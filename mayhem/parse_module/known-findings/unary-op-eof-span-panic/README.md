# Panic: `lo > hi` span assertion on a bare unary operator at EOF

**Found by:** all three targets (`parse_module`, `parse_program_tsx`, `parse_script`) — the
buggy code lives in a dependency (`swc_ecma_lexer`) reachable from every deno_ast entry point.

**Reproducer:** `repro.txt` — a single byte: `-` (also reproduces with `!`).

**Trigger:** feed the 1-byte source `-` (or `!`) to `deno_ast::parse_module` /
`parse_program` / `parse_script` with `capture_tokens: true` (matches this integration's
harnesses) built with `--debug-assertions` (cargo-fuzz's default — the same OSS-Fuzz-style
Rust build every one of these targets uses).

**Panic:**
```
thread '<unnamed>' panicked at swc_ecma_lexer-26.0.0/src/common/parser/expr.rs:1554:19:
lo: BytePos(1), hi: BytePos(0)
```

**Root cause (upstream dependency, not deno_ast's own code):** `parse_unary_expr` in
`swc_ecma_lexer` consumes the operator (`-`/`!`/`delete`/...), then tries to parse the operand
via `p.parse_unary_expr()`. When the source ends immediately after the operator, that recursive
call fails and the error-recovery path substitutes `Invalid { span: Span::new_with_checked(0,
0) }` for the missing operand. The enclosing `UnaryExpr`'s span is then built as
`Span::new_with_checked(start, arg.span_hi())` where `start` (captured before consuming the
operator, using an off-by-one via `cur_pos() - BytePos(1)` bookkeeping elsewhere in the same
function) ends up `> arg.span_hi()` for this specific EOF-during-recovery shape — violating
`Span::new_with_checked`'s `debug_assert!(lo <= hi)`.

**Impact:** in a normal (non-`debug_assertions`) release build this does NOT panic — the
`debug_assert!` is compiled out and the malformed `(lo=1, hi=0)` span is silently accepted,
which is arguably worse (a span with `lo > hi` used later for source-slicing or diagnostics
could misbehave). Under `--debug-assertions` (this integration's fuzz build, and how OSS-Fuzz
builds all Rust libFuzzer targets) it's a clean, deterministic, 1-byte-reproducible panic — a
trivial denial-of-service for any process that calls `deno_ast::parse_*` on attacker-controlled
text without `catch_unwind`.

**Suggested upstream fix:** in `swc_ecma_lexer`'s unary-expression error-recovery path, clamp
the enclosing span's `hi` to be `>= lo` (or use `start` for both ends of the `Invalid` span)
before calling `Span::new_with_checked`.

Not guarded in the harness — this is a genuine parser panic, not a harness misuse issue (see
this integration's fix for the BOM-strip debug-assertion, which by contrast *is* a documented
caller-contract issue and IS handled in the harness).
