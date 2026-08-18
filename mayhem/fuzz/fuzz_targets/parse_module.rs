// Preserved from the legacy mayhemheroes integration (target name: parse_module) — relocated
// to mayhem/fuzz/ (additive) instead of the repo-root fuzz/, with ONE fix: strip the leading
// UTF-8 BOM(s) before handing text to deno_ast (see the BOM comment below — this is a
// harness-correctness fix, not a behavior change to what gets fuzzed).
//
// deno_ast::parse_module returns a Result: a parse error is the EXPECTED outcome for
// malformed/adversarial input, so we just consume it. A panic (swc has historically panicked
// on adversarial input) is the finding this target is looking for.
#![no_main]

use libfuzzer_sys::fuzz_target;

use deno_ast::parse_module;
use deno_ast::MediaType;
use deno_ast::ModuleSpecifier;
use deno_ast::ParseParams;

fuzz_target!(|data: &[u8]| {
    let source_text = String::from_utf8_lossy(data);

    // deno_ast's own parse() internally calls strip_bom_from_arc(text, /* panic in debug */
    // true) on EVERY call path (parse_module/parse_program/parse_script all route through it)
    // — with `--debug-assertions` (cargo-fuzz's default), a text starting with U+FEFF hits a
    // deliberate `panic!("BOM should be stripped from text before providing it to deno_ast to
    // avoid a file text allocation")` (src/parsing.rs, strip_bom_from_arc — upstream's own
    // comment there: "this is only a perf concern, so don't crash in release"). This is deno_ast
    // telling ITS CALLERS to pre-strip the BOM; it is not a parser bug, so we strip here rather
    // than let every BOM-prefixed input "crash" the target on an intentional,
    // non-security-relevant debug assertion.
    //
    // EVERY leading U+FEFF is stripped, not just one: the public deno_ast::strip_bom removes a
    // single BOM, so an input opening with two (EF BB BF EF BB BF) still reached parse() with a
    // leading BOM and panicked all three targets on that same check — a false crash. std's
    // trim_start_matches is O(n) and puts no project code between the fuzz input and the
    // parse_* entry point. Inputs with zero or one leading BOM reach the parser exactly as
    // before; a U+FEFF after the first non-BOM character is kept (swc lexes it as whitespace).
    let source_text = source_text.trim_start_matches('\u{FEFF}');

    let parse_params = ParseParams {
        specifier: ModuleSpecifier::parse("file:///my_file.ts").unwrap(),
        media_type: MediaType::TypeScript,
        text: source_text.into(),
        capture_tokens: true,
        maybe_syntax: None,
        scope_analysis: false,
    };

    let _ = parse_module(parse_params);
});
