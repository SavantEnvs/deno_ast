# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile for deno_ast (TypeScript/JavaScript source parsing/lexing/AST library
# wrapping swc; Rust / cargo-fuzz). Builds ON TOP of the org base image, adding a pinned Rust
# nightly + cargo-fuzz under /opt/toolchains/rust (SPEC §6.2 item 8), plus a DWARF3 "anchor"
# object used to satisfy the DWARF<4 gate against the ASan runtime's DWARF5 archive (SPEC §6.2
# item 10 — see mayhem/build.sh for the full rationale), plus a SECOND (stable) toolchain for
# the oracle build (deno_ast's own rust-toolchain.toml pin).
#
# Build (from the repo root, on the `mayhem` branch):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) -t deno_ast-commit:test .

FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (never an ENV — an empty ENV breaks clang). build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH
# Undefaulted (no '=') so the base ENV default flows through unless --build-arg overrides it.
ARG SANITIZER_FLAGS

# ── Rust toolchain @ a FIXED, lockable, $HOME-independent prefix ───────────────────────────
# Nightly is required for -Zsanitizer=address (the OSS-Fuzz Rust ASan path) and for
# -Z dwarf-version=3. nightly-2025-09-05 is the fleet-proven pin used on jaq/gluesql/zeekstd in
# this same cohort; deno_ast's `edition = "2024"` (stabilized well before this date) and its
# large swc dependency graph both build cleanly on it (verified locally).
ARG RUST_CHANNEL=nightly-2025-09-05
ARG CARGO_FUZZ_VERSION=0.13.2

ENV RUSTUP_HOME=/opt/toolchains/rust/rustup \
    CARGO_HOME=/opt/toolchains/rust/cargo \
    PATH=/opt/toolchains/rust/cargo/bin:${PATH} \
    RUST_FUZZ_TOOLCHAIN=${RUST_CHANNEL}

USER root
RUN install -d /opt/toolchains/rust \
 && curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh \
 && sh /tmp/rustup-init.sh -y --no-modify-path --profile minimal \
        --default-toolchain "${RUST_CHANNEL}" \
 && rustup component add rust-src --toolchain "${RUST_CHANNEL}" \
 && cargo install cargo-fuzz --version "${CARGO_FUZZ_VERSION}" --locked \
 && rm -f /tmp/rustup-init.sh \
 # The commit build AND the air-gapped PATCH re-run run as `mayhem` (2000): it must read the
 # toolchain and read/refresh the cargo registry cache, so hand the whole prefix to 2000.
 && chown -R 2000:2000 /opt/toolchains/rust

# ── DWARF<4 anchor (SPEC §6.2 item 10) ─────────────────────────────────────────────────────
# cargo-fuzz's ASan build links a precompiled `librustc-nightly_rt.asan.a` runtime archive
# (DWARF5) via --whole-archive, and it lands FIRST in the final binary's .debug_info — so plain
# rustc debuginfo flags (which only affect rustc's OWN compilation units) can't fix the first-CU
# check verify-repo runs. Fix: prepend a hand-built DWARF3 compile-unit as the FIRST object in
# every link via a `-Clinker=<cc-wrapper>` RUSTFLAG — .debug_info CUs appear in linker-argument
# order, so the anchor's DWARF3 CU lands at offset 0. This is a first-CU-only, cosmetic fix — the
# rest of the binary (asan runtime + most rustc-emitted CUs) stays DWARF4/5; fuzzing and
# crash-finding are unaffected, only debug-info triage of the bulk of the binary.
RUN set -eux; \
    install -d /opt/toolchains/rust/dwarf3-anchor; \
    printf 'const int mayhem_dwarf3_anchor = 0;\n' > /opt/toolchains/rust/dwarf3-anchor/anchor.c; \
    clang -g -gdwarf-3 -c /opt/toolchains/rust/dwarf3-anchor/anchor.c \
      -o /opt/toolchains/rust/dwarf3-anchor/anchor.o; \
    printf '#!/bin/sh\nexec clang /opt/toolchains/rust/dwarf3-anchor/anchor.o "$@"\n' \
      > /opt/toolchains/rust/dwarf3-anchor/cc-wrapper.sh; \
    chmod +x /opt/toolchains/rust/dwarf3-anchor/cc-wrapper.sh; \
    chmod -R a+rX /opt/toolchains/rust/dwarf3-anchor; \
    echo "DWARF3 anchor ready: $(readelf --debug-dump=info /opt/toolchains/rust/dwarf3-anchor/anchor.o | grep -m1 Version:)"

# Source enters from the build CONTEXT (CI checkout): the FULL repo (incl. .git history) → /mayhem.
USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# ── upstream's OWN rust-toolchain.toml pins a SECOND toolchain (stable 1.89.0, not our
# nightly) ── deno_ast's repo root ships `rust-toolchain.toml` (channel = "1.89.0", an upstream
# file we never edit). rustup's directory-override lookup applies that file to EVERY bare
# `cargo` invocation anywhere under this tree — including our additive mayhem/fuzz and
# mayhem/kat crates — so a BARE `cargo fuzz build` here would silently run under upstream's
# stable 1.89.0 instead of the nightly this Dockerfile just installed, and die with "the option
# `Z` is only accepted on the nightly compiler" (confirmed empirically). Fix, applied in
# mayhem/build.sh / mayhem/test.sh: ALWAYS pass an explicit `+<toolchain>` — `+$RUST_FUZZ_TOOLCHAIN`
# for the fuzz build, and `+<upstream's own pin>` for the oracle build/test/KAT (read
# dynamically from rust-toolchain.toml, so it tracks upstream automatically across a `sync`).
# That second toolchain is installed HERE, once, online: it's a FULL version (major.minor.patch
# — "1.89.0", not a bare-minor "1.89"), so this is a single, unambiguous install with no
# "syncing channel updates" network round-trip needed later, unlike a bare-minor channel.
# Runs as `mayhem` (not root): /opt/toolchains/rust is already chown'd to 2000:2000 above, so
# this user can install an additional toolchain into it directly.
RUN STABLE_CHANNEL="$(sed -n 's/^channel *= *"\(.*\)"/\1/p' /mayhem/rust-toolchain.toml)" \
 && [ -n "$STABLE_CHANNEL" ] || { echo "ERROR: could not read channel from rust-toolchain.toml" >&2; exit 1; } \
 && echo "installing upstream-pinned toolchain for the oracle build: $STABLE_CHANNEL" \
 && rustup toolchain install "$STABLE_CHANNEL" --profile minimal

# Populates $CARGO_HOME (online, this first build) and builds the sanitized fuzz targets,
# per-target dictionaries, and the mayhem/kat KAT probe.
RUN bash mayhem/build.sh

# Run the project's functional suite + the KAT probe at build time (a failing suite fails the build).
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
