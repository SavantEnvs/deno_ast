# Findings index for this target

- `unterminated-class-body-eof-peek-panic/` — parse_script-ONLY finding (see that directory).

Also reproducible on this target (found across all three; full write-ups live under
`mayhem/parse_module/known-findings/` to avoid triplicating the same root-cause analysis):

- `../parse_module/known-findings/unary-op-eof-span-panic/` — bare `-`/`!` at EOF.
- `../parse_module/known-findings/class-hash-name-underflow/` — `class C{#` (bare private-name
  sigil at EOF).
