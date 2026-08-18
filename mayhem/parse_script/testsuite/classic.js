// Plain, non-strict "classic script" surface: no import/export (would be a parse error under
// parse_script's script grammar), var hoisting, function declarations, labelled loops, classes.
var total = 0;

function sum(a, b) {
  return a + b;
}

outer: for (var i = 0; i < 5; i++) {
  for (var j = 0; j < 5; j++) {
    if (j === 3) continue outer;
    total = sum(total, i * j);
  }
}

class Counter {
  #n = 0;
  static from(n) {
    const c = new Counter();
    c.#n = n;
    return c;
  }
  get value() {
    return this.#n;
  }
  inc() {
    this.#n++;
    return this;
  }
}

var c = Counter.from(total).inc().inc();
switch (c.value % 3) {
  case 0:
    total += 1;
    break;
  case 1:
  case 2:
    total -= 1;
    break;
  default:
    total = 0;
}
