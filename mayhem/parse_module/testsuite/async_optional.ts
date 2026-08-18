import type { Reader } from "./io.ts";

interface Config {
  retries?: number;
  onError?: (err: Error) => void;
}

export async function withRetry<T>(
  fn: () => Promise<T>,
  cfg: Config = {},
): Promise<T | undefined> {
  const retries = cfg.retries ?? 3;
  for (let i = 0; i < retries; i++) {
    try {
      return await fn();
    } catch (err) {
      cfg.onError?.(err as Error);
      if (i === retries - 1) throw err;
    }
  }
  return undefined;
}

export class Pipeline {
  private steps: Array<(r: Reader) => Promise<Reader>> = [];

  use(step: (r: Reader) => Promise<Reader>): this {
    this.steps.push(step);
    return this;
  }

  async run(input: Reader): Promise<Reader | null> {
    let cur: Reader | null = input;
    for (const step of this.steps) {
      cur = cur ? await step(cur) : null;
    }
    return cur?.closed ? null : cur;
  }
}
