// `with` is a sloppy-mode-only statement: valid in SCRIPT grammar, a hard parse error in
// MODULE grammar (modules are always strict mode). This exercises a grammar branch the
// legacy parse_module target (always ParseMode::Module) structurally cannot reach.
var obj = { a: 1, b: 2 };
var out = [];

with (obj) {
  out.push(a + b);
}

function duplicateParams(a, a, b) {
  // duplicate parameter names are also only legal in sloppy (non-strict) function bodies
  return a + b;
}

var re = /[a-z]+\d*/gi;
var tpl = `total=${out[0]}`;
label: {
  if (out.length) break label;
  out.push(0);
}
console.log(duplicateParams(1, 2, 3), tpl, re.test("abc123"));
