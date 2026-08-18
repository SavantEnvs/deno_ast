# Findings also reproducible via this target

Both of the following (found across all three targets) reproduce on `parse_program_tsx` too;
full write-ups + reproducers live under `mayhem/parse_module/known-findings/` to avoid
triplicating the same root-cause analysis:

- `../parse_module/known-findings/unary-op-eof-span-panic/` — bare `-`/`!` at EOF.
- `../parse_module/known-findings/class-hash-name-underflow/` — `class C{#` (bare private-name
  sigil at EOF).

No `parse_program_tsx`-only finding was isolated during integration triage.
