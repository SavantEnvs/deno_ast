# Panic: integer subtract-with-overflow parsing a bare `#` inside a class body

**Found by:** all three targets (`parse_module`, `parse_program_tsx`, `parse_script`) — the
buggy code lives in a dependency (`swc_common`) reachable from every deno_ast entry point.

**Reproducer:** `repro.txt` — 9 bytes: `class C{#`.

**Trigger:** feed `class C{#` (a class body containing only a lone, unterminated private-name
sigil `#`) to `deno_ast::parse_module` / `parse_program` / `parse_script`, built with
`--debug-assertions` (cargo-fuzz's default — overflow-checks are also on under this profile,
which is what actually trips this one; see Impact below).

**Panic:**
```
thread '<unnamed>' panicked at swc_common-17.0.1/src/syntax_pos.rs:1248:17:
attempt to subtract with overflow
```

**Root cause (upstream dependency, not deno_ast's own code):** parsing a private name (`#foo`)
inside a class body computes a span/position by subtracting two byte offsets; when the `#` is
the last byte of the source (no identifier follows, immediate EOF), one of the operands
underflows `usize`/`BytePos` arithmetic in `swc_common::syntax_pos`.

**Impact:** this one is NOT merely a `debug_assert!` — it is Rust's built-in overflow check
(`-C overflow-checks=on`, part of cargo-fuzz's `--debug-assertions` release profile, matching
how OSS-Fuzz builds every Rust libFuzzer target). In a plain `--release` build without overflow
checks this subtraction would silently WRAP instead of panicking, producing a nonsensical huge
`BytePos`/span value that could then be used to index or slice source text elsewheree — a
real path to an out-of-bounds panic or, in a `get_unchecked`-style consumer, worse. Under the
fuzz build it's a clean, deterministic, 9-byte-reproducible panic — a trivial denial-of-service
for any process that calls `deno_ast::parse_*` on attacker-controlled text without
`catch_unwind`.

**Suggested upstream fix:** use checked/saturating subtraction (or reorder the operands) when
computing the private-name span in `swc_common::syntax_pos` for the truncated-at-EOF case.

Not guarded in the harness — this is a genuine parser panic, not a harness misuse issue.
