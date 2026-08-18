// mayhem/kat — known-answer-test probe for mayhem/test.sh.
//
// See mayhem/kat/Cargo.toml for why this exists as a separate, dynamically linked binary
// rather than relying on `cargo test` alone.
//
// Parses 4 FIXED sources through deno_ast's public parse_module/parse_program/parse_script
// entry points and prints exact computed facts as `KAT_<NAME>=<value>`. mayhem/test.sh matches
// each line EXACTLY (grep -qxF). A parser regression, or a neutered ("sabotaged") binary that
// prints nothing, fails every one of these checks. Expected values were computed against this
// exact source tree with `cargo +stable run --release` (deno_ast 0.53.3, swc_ecma_parser
// =27.0.7 — all swc crates are exact-pinned in the upstream root Cargo.toml, so these values
// are deterministic across rebuilds) and are recorded next to each check below.
use deno_ast::diagnostics::Diagnostic;
use deno_ast::{
  parse_module, parse_program, parse_script, MediaType, ModuleSpecifier, ParseParams,
};

fn specifier(s: &str) -> ModuleSpecifier {
  ModuleSpecifier::parse(s).unwrap_or_else(|e| {
    eprintln!("kat: bad specifier {s:?}: {e}");
    std::process::exit(1);
  })
}

fn main() {
  // 1) + 2) A fixed 2-item TypeScript module, with token capture on. Exact top-level item
  //    count and exact captured-token count are both fully determined by the fixed source.
  //    Source: "export const a = 1;\nexport function f() {}\n"
  let module_src = "export const a = 1;\nexport function f() {}\n";
  let parsed = parse_module(ParseParams {
    specifier: specifier("file:///probe_module.ts"),
    media_type: MediaType::TypeScript,
    text: module_src.into(),
    capture_tokens: true,
    maybe_syntax: None,
    scope_analysis: false,
  })
  .unwrap_or_else(|e| {
    eprintln!("kat: KAT_MODULE_ITEMS/KAT_TOKEN_COUNT: failed to parse fixed module: {e}");
    std::process::exit(1);
  });
  println!("KAT_MODULE_ITEMS={}", parsed.program_ref().body().count());
  println!("KAT_TOKEN_COUNT={}", parsed.tokens().len());

  // 3) A deliberately invalid TypeScript snippet: "const x: = ;" (a type annotation with no
  //    type, immediately followed by an empty initializer). Must fail to parse — and the
  //    diagnostic's stable error CODE plus its 1-indexed line/column position are both exact,
  //    fixed facts about this exact broken source.
  let bad_src = "const x: = ;";
  let err = parse_module(ParseParams {
    specifier: specifier("file:///probe_bad.ts"),
    media_type: MediaType::TypeScript,
    text: bad_src.into(),
    capture_tokens: false,
    maybe_syntax: None,
    scope_analysis: false,
  })
  .err()
  .unwrap_or_else(|| {
    eprintln!(
      "kat: KAT_BAD_PARSE: expected a parse ERROR for deliberately-invalid input {bad_src:?}, got Ok"
    );
    std::process::exit(1);
  });
  println!("KAT_BAD_CODE={}", err.code());
  let pos = err.display_position();
  println!("KAT_BAD_LINE={}", pos.line_number);
  println!("KAT_BAD_COL={}", pos.column_number);

  // 4) `with` statements are sloppy-mode-only: legal SCRIPT grammar, illegal (or at least not
  //    the grammar) a module targets. parse_script (the NEW mayhem/parse_script target's entry
  //    point) must accept this fixed source; this is the same grammar divergence that target
  //    exists to fuzz, asserted here as an exact, sabotage-detectable fact.
  let with_src = "with ({ a: 1 }) { a; }";
  let script_result = parse_script(ParseParams {
    specifier: specifier("file:///probe_with.js"),
    media_type: MediaType::JavaScript,
    text: with_src.into(),
    capture_tokens: false,
    maybe_syntax: None,
    scope_analysis: false,
  });
  println!("KAT_SCRIPT_WITH_OK={}", script_result.is_ok());

  // 5) A fixed TSX source combining the generic/JSX angle-bracket disambiguation (`<T,>`) with
  //    a JSX element — the exact surface the NEW mayhem/parse_program_tsx target fuzzes.
  //    Exact top-level item count for this fixed source.
  let tsx_src = "const identity = <T,>(x: T): T => x;\n\
                 export const el = <div className=\"a\">{identity(1)}</div>;\n";
  let tsx_parsed = parse_program(ParseParams {
    specifier: specifier("file:///probe_tsx.tsx"),
    media_type: MediaType::Tsx,
    text: tsx_src.into(),
    capture_tokens: false,
    maybe_syntax: None,
    scope_analysis: false,
  })
  .unwrap_or_else(|e| {
    eprintln!("kat: KAT_TSX_ITEMS: failed to parse fixed TSX source: {e}");
    std::process::exit(1);
  });
  println!("KAT_TSX_ITEMS={}", tsx_parsed.program_ref().body().count());
}
