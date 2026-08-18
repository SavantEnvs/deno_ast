// Preserved from the legacy mayhemheroes integration (target name: parse_module) — relocated
// to mayhem/fuzz/ (additive) instead of the repo-root fuzz/, with ONE fix: strip a leading
// UTF-8 BOM before handing text to deno_ast (see the strip_bom() comment below — this is a
// harness-correctness fix, not a behavior change to what gets fuzzed).
//
// deno_ast::parse_module returns a Result: a parse error is the EXPECTED outcome for
// malformed/adversarial input, so we just consume it. A panic (swc has historically panicked
// on adversarial input) is the finding this target is looking for.
#![no_main]

use libfuzzer_sys::fuzz_target;

use deno_ast::parse_module;
use deno_ast::strip_bom;
use deno_ast::MediaType;
use deno_ast::ModuleSpecifier;
use deno_ast::ParseParams;

fuzz_target!(|data: &[u8]| {
    let source_text = String::from_utf8_lossy(data);

    // deno_ast's own parse() internally calls strip_bom_from_arc(text, /* panic in debug */
    // true) on EVERY call path (parse_module/parse_program/parse_script all route through it)
    // — with `--debug-assertions` (cargo-fuzz's default), a text starting with U+FEFF hits a
    // deliberate `panic!("BOM should be stripped from text before providing it to deno_ast to
    // avoid a file text allocation")` (src/parsing.rs:409-420). This is deno_ast telling ITS
    // CALLERS to pre-strip the BOM (the public deno_ast::strip_bom exists for exactly this);
    // it is not a parser bug, so we call it here rather than let every libFuzzer BOM-prefixed
    // input "crash" the target on an intentional, non-security-relevant debug assertion.
    let source_text = strip_bom(source_text.into_owned());

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
