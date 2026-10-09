import { describe, it, expect } from "vitest";
import { fold, matches } from "../utils/text.js";

describe("text.fold", () => {
  it("lowercases and strips pt-BR accents", () => {
    expect(fold("Ação É Ótima, CÃO")).toBe("acao e otima, cao");
    expect(fold("Ç ü ñ")).toBe("c u n");
  });

  it("handles empty and non-string input", () => {
    expect(fold("")).toBe("");
    expect(fold(null)).toBe("");
    expect(fold(undefined)).toBe("");
  });
});

describe("text.matches", () => {
  it("matches every word of the query in any of the fields", () => {
    expect(matches(["Reunião de equipe", "notas"], "reuniao")).toBe(true);
    expect(matches(["Reunião de equipe", "notas"], "equipe notas")).toBe(true);
    expect(matches(["Reunião de equipe"], "equipe cafe")).toBe(false);
  });

  it("matches everything for a blank query", () => {
    expect(matches(["x"], "   ")).toBe(true);
    expect(matches([], "")).toBe(true);
  });
});
