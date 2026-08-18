type Result<T, E = Error> = { ok: true; value: T } | { ok: false; error: E };

async function* gen<T extends object>(items: T[]): AsyncGenerator<T> {
  for (const it of items) yield await Promise.resolve(it);
}

enum Color { Red = 1, Green, Blue }

namespace Util {
  export const id = <A,>(a: A): A => a;
}

declare module "ext" {
  export function f(x: unknown): asserts x is string;
}

export default gen([{ c: Color.Red, v: Util.id(42) }] as const);
