import { join } from "./deps.ts";

interface Point<T = number> {
  x: T;
  y: T;
}

export class Shape implements Point {
  constructor(public x = 0, public y = 0) {}
  area(): number {
    return Math.abs(this.x * this.y);
  }
}

const p: Point = new Shape(3, 4);
console.log(`area=${p.area?.() ?? 0}`, join("a", "b"));
