#!/usr/bin/env bash
#
# mayhem/build.sh — build deno_ast's ADDITIVE cargo-fuzz targets as sanitized libFuzzer
# binaries (OSS-Fuzz Rust path: cargo-fuzz + ASan via RUSTFLAGS), the mayhem/kat oracle probe,
# and (built only, no run) the project's own test suite.
#
# Targets produced (one Mayhemfile each):
#   /mayhem/parse_module        — PRESERVED legacy target (mayhemheroes original name).
#                                  deno_ast::parse_module, MediaType::TypeScript.
#   /mayhem/parse_program_tsx   — NEW. deno_ast::parse_program (auto module/script detection),
#                                  MediaType::Tsx (TypeScript + JSX).
#   /mayhem/parse_script        — NEW. deno_ast::parse_script (forced Script grammar),
#                                  MediaType::JavaScript.
#   /mayhem/kat                 — dynamically-linked known-answer probe (mayhem/test.sh)
#
# deno_ast ships its OWN upstream fuzz/ crate at the repo root (fuzz/fuzz_targets/
# parse_module.rs, bin name `fuzz_parse_module`) — we do NOT touch it (upstream file). All
# three targets here come from mayhem/fuzz/, a wholly ADDITIVE cargo-fuzz crate (its own,
# separate cargo workspace — see the header comment in mayhem/fuzz/Cargo.toml for why) that
# preserves the legacy mayhemheroes `parse_module` harness (relocated, not the upstream one)
# plus two new sibling targets.
#
# Runs inside the commit image (RUST mayhem/Dockerfile) as `mayhem` in /mayhem. The Rust
# toolchain + cargo registry live at $CARGO_HOME=/opt/toolchains/rust/cargo (pinned by the
# Dockerfile ENV — absolute, $HOME-independent).
#
# DWARF gate (SPEC §6.2 item 10): rustc's own CUs land at DWARF4 and the ASan runtime archive
# at DWARF5; the gate reads only the FIRST .debug_info CU. The Dockerfile precompiles a tiny
# DWARF3 anchor object (/opt/toolchains/rust/dwarf3-anchor/anchor.o) and a cc-wrapper that
# PREPENDS it ahead of every other link input. $RUST_DEBUG_FLAGS wires that wrapper in via
# `-Clinker`, threaded through RUSTFLAGS on every cargo-fuzz build.
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE.
#   - This FIRST build (in CI, online) populates the cargo registry under $CARGO_HOME.
#   - The committed Cargo.lock files (mayhem/fuzz/Cargo.lock, mayhem/kat/Cargo.lock; upstream's
#     own root Cargo.lock covers the oracle build of the deno_ast crate itself) let the offline
#     re-run resolve the SAME dependency graph from that cache with no new network I/O. The
#     rlenv runtime exports CARGO_NET_OFFLINE=true for the re-run, so this script does NOT
#     hard-code --offline (that would break this first, online build).
#   - Re-running on an already-built tree must also succeed (idempotent: every step below is
#     safe to repeat — `cp -f`, `cargo fuzz build`/`cargo build` overwrite).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

# $SANITIZER_FLAGS is the base image's CLANG-oriented ASan/UBSan contract (SPEC §6.1/§6.2 item
# 8); rustc ignores it and gets its OWN sanitizer flag via RUSTFLAGS `-Zsanitizer=address`
# below (the OSS-Fuzz Rust path). Referenced here only informationally.
echo "SANITIZER_FLAGS (clang contract; informational for Rust — see RUSTFLAGS below)=${SANITIZER_FLAGS:-}"

: "${SRC:=/mayhem}"
cd "$SRC"

# ── upstream's OWN rust-toolchain.toml (channel = "1.89.0") overrides EVERY bare `cargo`
# invocation under this tree via rustup's directory-override lookup — including inside
# mayhem/fuzz and mayhem/kat. A bare `cargo fuzz build` would silently run under that STABLE
# toolchain instead of our nightly and fail on `-Zsanitizer=address` ("only accepted on the
# nightly compiler"). So EVERY cargo invocation below passes an explicit `+<toolchain>`, never
# bare `cargo`. $RUST_FUZZ_TOOLCHAIN is the Dockerfile-pinned nightly (ENV, set from the
# RUST_CHANNEL build ARG). The oracle build uses upstream's OWN pin instead (read here, once,
# from rust-toolchain.toml — see mayhem/Dockerfile for why that toolchain is pre-installed, and
# why "already installed + explicit `+channel`" needs no network, unlike `rustup toolchain
# install` for a bare-minor channel).
: "${RUST_FUZZ_TOOLCHAIN:?RUST_FUZZ_TOOLCHAIN must be set by mayhem/Dockerfile}"
ORACLE_TOOLCHAIN="$(sed -n 's/^channel *= *"\(.*\)"/\1/p' rust-toolchain.toml)"
[ -n "$ORACLE_TOOLCHAIN" ] || { echo "ERROR: could not read channel from rust-toolchain.toml" >&2; exit 1; }
echo "fuzz toolchain (Dockerfile-pinned nightly): $RUST_FUZZ_TOOLCHAIN"
echo "oracle toolchain (upstream's own rust-toolchain.toml pin): $ORACLE_TOOLCHAIN"
# Record it so mayhem/test.sh uses the IDENTICAL toolchain at run time (never re-derive it
# independently — keeps build.sh's precompile and test.sh's run on the same toolchain).
mkdir -p "$SRC/mayhem-build"
printf '%s\n' "$ORACLE_TOOLCHAIN" > "$SRC/mayhem-build/oracle-toolchain.txt"

# DWARF<4 anchor (see header). RUST_DEBUG_FLAGS is the SPEC §6.2 item 10 knob — EDIT only if
# the anchor prefix moves; do not drop -Clinker or the gate regresses.
: "${RUST_DEBUG_FLAGS:=-Cdebuginfo=2 -Zdwarf-version=3 -Clinker=/opt/toolchains/rust/dwarf3-anchor/cc-wrapper.sh}"

# OSS-Fuzz Rust libFuzzer+ASan flags. cargo-fuzz sets the ASan flag itself, but we pin it
# explicitly. --cfg fuzzing matches libfuzzer-sys; force-frame-pointers aids ASan backtraces.
FUZZ_RUSTFLAGS="--cfg fuzzing -Zsanitizer=address -Cforce-frame-pointers $RUST_DEBUG_FLAGS"

FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"
FUZZ_TARGETS=(parse_module parse_program_tsx parse_script)

echo "=== cargo fuzz build (image nightly, ASan via RUSTFLAGS, DWARF3 anchor) ==="
echo "RUSTFLAGS=$FUZZ_RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

# mayhem/fuzz/ is deliberately its OWN cargo workspace (see mayhem/fuzz/Cargo.toml), NOT a
# member of any other workspace — deno_ast's root Cargo.toml has NO [workspace] table at all
# (it's a plain single-package crate), and upstream's own fuzz/ claims workspace-root-of-one
# status via its own `[workspace] members = ["."]`. So cargo-fuzz writes mayhem/fuzz's binaries
# under mayhem/fuzz/target/ — verified empirically; asserted below with `[ -x "$bin" ]` so a
# wrong guess fails loudly instead of "succeeding".
for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  RUSTFLAGS="$FUZZ_RUSTFLAGS" cargo "+$RUST_FUZZ_TOOLCHAIN" fuzz build --fuzz-dir "$FUZZ_DIR" \
    -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp -f "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# ── Per-target dictionaries — copy into the FLAT /mayhem root, where each Mayhemfile's
#    cmd-level `dictionary:` key points (docs/seed-corpus.md: a referenced-but-absent dict
#    makes libFuzzer exit 1 at 0 edges). ──────────────────────────────────────────────────────
for t in "${FUZZ_TARGETS[@]}"; do
  d="mayhem/$t/$t.dict"
  if [ -f "$d" ]; then
    cp -f "$d" "/mayhem/$t.dict"
    echo "copied dictionary /mayhem/$t.dict"
  fi
done

# ── The KAT probe used by mayhem/test.sh (NORMAL flags, oracle toolchain — a functional
#    oracle, not a triage artifact; its own workspace so it never touches deno_ast's own root
#    Cargo.toml). A plain `cargo build` on the gnu target is already dynamically linked (unlike
#    Go, Rust needs no cgo-style trick for this) — we still assert it so a future static-link
#    change (e.g. a musl target) can't silently weaken the sabotage-detecting oracle. ─────────
echo "=== building /mayhem/kat (KAT probe, oracle toolchain $ORACLE_TOOLCHAIN) ==="
( cd mayhem/kat && env -u RUSTFLAGS cargo "+$ORACLE_TOOLCHAIN" build --release )
cp -f mayhem/kat/target/release/kat /mayhem/kat
if ! file /mayhem/kat | grep -q 'dynamically linked'; then
  echo "FATAL: /mayhem/kat is not dynamically linked — the sabotage check could not" >&2
  echo "       neuter it, which would make mayhem/test.sh a reward-hackable oracle." >&2
  file /mayhem/kat >&2
  exit 1
fi
echo "built /mayhem/kat (dynamically linked)"

# ── The project's own test suite (NORMAL flags, oracle toolchain — no RUSTFLAGS/sanitizer) —
#    build only, so mayhem/test.sh just RUNS it. --all-features --all-targets matches what
#    upstream's own CI runs (.github/workflows/ci.yml), minus `-D warnings`. ~190 #[test] cases
#    across src/ (parsing, lexing, transpiling, cjs_parse, type_strip, diagnostics, exports, …)
#    assert exact ASTs/emit output/diagnostic text+positions — real known-answer assertions. A
#    SEPARATE CARGO_TARGET_DIR keeps this clean (non-instrumented) build from colliding with
#    the fuzz targets' ASan-instrumented target dir above.
echo "=== precompiling: cargo +$ORACLE_TOOLCHAIN test --no-run --all-targets --all-features (project's NORMAL flags) ==="
( env -u RUSTFLAGS CARGO_TARGET_DIR="$SRC/mayhem-tests-target" \
    cargo "+$ORACLE_TOOLCHAIN" test --no-run --release --all-targets --all-features )
echo "test suite built under $SRC/mayhem-tests-target"

echo "build.sh complete:"
ls -la /mayhem/parse_module /mayhem/parse_program_tsx /mayhem/parse_script /mayhem/kat
