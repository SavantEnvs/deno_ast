// deno-lint-ignore-file
@decorator
class Widget {
  #priv = new Map<string, bigint>([["k", 1n]]);
  static {
    console.log("static block");
  }
  get size(): number {
    return this.#priv.size satisfies number;
  }
}

label: for (let i = 0; i < 10; i++) {
  if (i % 2) continue label;
  switch (i) {
    case 0: break;
    default: void 0;
  }
}

const re = /[\p{L}]+/gu;
const tpl = String.raw`raw ${re.source}`;
export { Widget, tpl };
