import { describe, it, expect } from "vitest";
import { evaluate, formatNumber } from "../utils/calc.js";

describe("calc.evaluate", () => {
  it.each([
    ["2+2", 4],
    ["2+3*4", 14],
    ["(2+3)*4", 20],
    ["2^3^2", 512],
    ["-2^2", -4],
    ["-2*3", -6],
    ["--2", 2],
    ["+5", 5],
    ["2,5*2", 5],
    ["1.234,5+0,5", 1235],
    ["10/4", 2.5],
    ["200*15%", 30],
    ["(50+50)%", 1],
    [" 7 - 10 ", -3]
  ])("%s = %s", (expr, value) => {
    expect(evaluate(expr)).toEqual({ ok: true, value });
  });

  it.each([
    ["", "empty"],
    ["2/0", "division-by-zero"],
    ["2+", "syntax"],
    ["(2", "syntax"],
    ["2)", "syntax"],
    ["()", "syntax"],
    ["2 3", "syntax"],
    ["1.2.3", "syntax"],
    ["*2", "syntax"],
    ["constructor", "syntax"],
    ["process.exit()", "syntax"],
    ["9^999", "overflow"]
  ])("%s -> %s", (expr, error) => {
    expect(evaluate(expr)).toEqual({ ok: false, error });
  });
});

describe("calc.formatNumber", () => {
  it("uses comma decimals and hides float noise", () => {
    expect(formatNumber(0.1 + 0.2)).toBe("0,3");
    expect(formatNumber(2.5)).toBe("2,5");
    expect(formatNumber(4)).toBe("4");
    expect(formatNumber(-1.5)).toBe("-1,5");
  });
});
