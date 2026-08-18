// NEW sibling target (additive to the preserved legacy `parse_module`): fuzzes
// deno_ast::parse_program with MediaType::Tsx instead of parse_module + MediaType::TypeScript.
//
// Two axes of new coverage vs. the legacy target:
//   - `parse_program` lets swc auto-detect module vs. script grammar from the source text
//     itself (import/export presence), instead of always forcing Module mode — a different
//     code path through deno_ast::parsing::refine_parse_mode / parse().
//   - MediaType::Tsx turns on JSX parsing on top of the TypeScript grammar (angle-bracket
//     ambiguity between generics `<T>` and JSX tags is one of the trickier corners of swc's
//     lexer/parser and a plausible panic surface).
//
// Bounded input size (fuzzing hygiene, not a correctness requirement — SPEC 6b): a very deep
// expression/JSX nesting can blow the native stack purely from input size, so cap it to keep
// each iteration cheap; a stack overflow within this bound is a legitimate crash finding.
//
// parse_program returns a Result: a parse error is the EXPECTED outcome for malformed/
// adversarial input, so we just consume it. Panics (swc has historically panicked on
// adversarial input, especially around JSX/generic disambiguation) are the findings we want.
#![no_main]

use libfuzzer_sys::fuzz_target;

use deno_ast::parse_program;
use deno_ast::strip_bom;
use deno_ast::MediaType;
use deno_ast::ModuleSpecifier;
use deno_ast::ParseParams;

const MAX_LEN: usize = 65_536;

fuzz_target!(|data: &[u8]| {
    if data.len() > MAX_LEN {
        return;
    }
    let source_text = String::from_utf8_lossy(data);

    // See mayhem/fuzz/fuzz_targets/parse_module.rs for why: deno_ast panics (debug_assertions
    // build) on a leading BOM it wasn't asked to strip itself — pre-stripping is the documented
    // caller contract, not something we're doing to dodge a real parser bug.
    let source_text = strip_bom(source_text.into_owned());

    let parse_params = ParseParams {
        specifier: ModuleSpecifier::parse("file:///my_file.tsx").unwrap(),
        media_type: MediaType::Tsx,
        text: source_text.into(),
        capture_tokens: true,
        maybe_syntax: None,
        scope_analysis: false,
    };

    let _ = parse_program(parse_params);
});
