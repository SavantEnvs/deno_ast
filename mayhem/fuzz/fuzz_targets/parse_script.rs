// NEW sibling target (additive to the preserved legacy `parse_module`): fuzzes
// deno_ast::parse_script (script grammar, not module grammar) with MediaType::JavaScript.
//
// Scripts and modules are NOT the same grammar in swc/ECMAScript: scripts allow non-strict-mode
// constructs a module never sees (e.g. `with` statements, duplicate `var` bindings, sloppy-mode
// function-in-block semantics) and disallow top-level `import`/`export`. parse_script forces
// that alternate grammar path (ParseMode::Script in deno_ast::parsing), which the legacy
// parse_module target (always ParseMode::Module) never exercises. MediaType::JavaScript (no
// TypeScript syntax) keeps this target focused on the plain-JS lexer/parser surface.
//
// Bounded input size (fuzzing hygiene, not a correctness requirement — SPEC 6b): caps
// worst-case per-iteration cost; a stack overflow within this bound is a legitimate finding.
//
// parse_script returns a Result: a parse error is the EXPECTED outcome for malformed/
// adversarial input, so we just consume it. Panics are the findings we want.
#![no_main]

use libfuzzer_sys::fuzz_target;

use deno_ast::parse_script;
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
        specifier: ModuleSpecifier::parse("file:///my_file.js").unwrap(),
        media_type: MediaType::JavaScript,
        text: source_text.into(),
        capture_tokens: true,
        maybe_syntax: None,
        scope_analysis: false,
    };

    let _ = parse_script(parse_params);
});
