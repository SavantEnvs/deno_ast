#!/usr/bin/env bash
#
# mayhem/test.sh — RUN deno_ast's OWN precompiled test suite (built by mayhem/build.sh via
# `cargo test --no-run --all-targets --all-features --release` — the exact suite upstream CI
# runs in .github/workflows/ci.yml, minus `-D warnings`) plus the mayhem/kat known-answer
# probe, and emit a CTRF summary. exit 0 iff nothing failed.
#
# PATCH-grade oracle (SPEC §6.3). Two parts, and the SECOND is the load-bearing one:
#
#  1) The ~190 #[test] cases across src/ (parsing, lexing, transpiling, cjs_parse, type_strip,
#     diagnostics, exports, …) — real known-answer suites asserting exact expected AST/emit
#     output and exact diagnostic text/positions, not just "didn't panic".
#
#  2) The KAT probe /mayhem/kat — docs/netnew-worker-prompt.md §4 explicitly forbids relying on
#     `cargo test` alone as the oracle: a `--test` harness binary runs every #[test] in-process
#     from ONE entrypoint, so a process-wide sabotage `_exit(0)` looks identical to "the test
#     binary produced no output" — indistinguishable from a build failure, and easy to
#     reward-hack around. /mayhem/kat is instead a tiny, separate, dynamically-linked (build.sh
#     asserts this with `file`) binary whose entire job is to parse 4 FIXED TS/TSX/JS sources
#     through deno_ast's public parse_module/parse_program/parse_script and print exact
#     computed facts; a neutered binary prints nothing and every exact-string assertion below
#     fails. A patch that stubs the parser to dodge a crash cannot reproduce these values either.
#
# This script only RUNS things — mayhem/build.sh already built the test suite and /mayhem/kat.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

PASSED=0; FAILED=0; SKIPPED=0

# ── 1) the project's own precompiled test suite (no cargo/toolchain needed at run time — the
#    binaries under mayhem-tests-target/release/deps/ were already built by build.sh) ─────────
TDIR="$SRC/mayhem-tests-target/release/deps"
if [ ! -d "$TDIR" ]; then
  echo "ERROR: $TDIR missing — mayhem/build.sh should have built the test suite" >&2
  emit_ctrf "cargo-test+kat" 0 1 0; exit 1
fi

OUT="$(mktemp)"
for bin in "$TDIR"/deno_ast-*; do
  [ -f "$bin" ] && [ -x "$bin" ] || continue
  case "$bin" in *.d) continue ;; esac
  echo "=== running $(basename "$bin") ==="
  "$bin" 2>&1 | tee -a "$OUT"
done

# Sum every `test result: ok. X passed; Y failed; ... Z ignored` line across all test binaries.
sum_field() { grep -E '^test result:' "$OUT" | sed -E "s/.* ([0-9]+) $1.*/\1/" | awk '{s+=$1} END {print s+0}'; }
PASSED=$(sum_field passed)
FAILED=$(sum_field failed)
SKIPPED=$(sum_field ignored)
: "${PASSED:=0}" "${FAILED:=0}" "${SKIPPED:=0}"
rm -f "$OUT"

if [ "$(( PASSED + FAILED + SKIPPED ))" -eq 0 ]; then
  echo "ERROR: no 'test result:' lines parsed — test binaries produced no results" >&2
  emit_ctrf "cargo-test+kat" 0 1 0; exit 1
fi

# ── 2) the KAT probe (sabotage-detecting; see header) ────────────────────────────────────────
# UNCONDITIONAL by design: a missing binary is a FAILURE, never a skip. A `[ -f ... ]` guard
# here is how a probe silently stops running and the oracle quietly degrades to the
# cargo-test-only (potentially reward-hackable) case.
echo "=== KAT probe: /mayhem/kat (dynamically linked; parses 4 FIXED TS/TSX/JS sources) ==="
KAT_OUT="$(/mayhem/kat 2>&1)"; kat_rc=$?
echo "$KAT_OUT"

kat_expect() {
  local label="$1" line="$2"
  if printf '%s\n' "$KAT_OUT" | grep -qxF "$line"; then
    echo "KAT PASS: $label"
    PASSED=$(( PASSED + 1 ))
  else
    echo "KAT FAIL: $label — expected exact line: $line" >&2
    FAILED=$(( FAILED + 1 ))
  fi
}

if [ "$kat_rc" -ne 0 ]; then
  echo "KAT FAIL: /mayhem/kat exited $kat_rc (neutered, missing, or parser broken)" >&2
  FAILED=$(( FAILED + 1 ))
fi
# Expected values — computed against this exact source tree with `cargo +stable run --release`
# (deno_ast 0.53.3, all swc crates exact-pinned in the upstream root Cargo.toml — see
# mayhem/kat/src/main.rs for the fixed sources and full derivation):
#   "export const a = 1;\nexport function f() {}\n"  -> 2 top-level items, 13 captured tokens
#   "const x: = ;"  (deliberately invalid TS)         -> parse error, code "unexpected",
#                                                        at line 1, column 10
#   "with ({ a: 1 }) { a; }"  via parse_script         -> parses OK (Script-only grammar)
#   TSX generic/JSX source via parse_program           -> 2 top-level items
kat_expect "module: top-level item count"        'KAT_MODULE_ITEMS=2'
kat_expect "module: captured token count"        'KAT_TOKEN_COUNT=13'
kat_expect "invalid TS: diagnostic code"         'KAT_BAD_CODE=unexpected'
kat_expect "invalid TS: diagnostic line"         'KAT_BAD_LINE=1'
kat_expect "invalid TS: diagnostic column"       'KAT_BAD_COL=10'
kat_expect "parse_script accepts \`with\`"       'KAT_SCRIPT_WITH_OK=true'
kat_expect "TSX: top-level item count"           'KAT_TSX_ITEMS=2'

emit_ctrf "cargo-test+kat" "$PASSED" "$FAILED" "$SKIPPED"
