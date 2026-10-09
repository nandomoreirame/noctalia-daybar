import { describe, it, expect } from "vitest";
import { parseWhen } from "../utils/when.js";

// Friday, 9 October 2026, 15:00 local time.
const NOW = new Date(2026, 9, 9, 15, 0);

describe("parseWhen: days", () => {
  it.each([
    ["pagar boleto amanhã", "pagar boleto", "2026-10-10"],
    ["Amanhã comprar pão", "comprar pão", "2026-10-10"],
    ["comprar pão amanha", "comprar pão", "2026-10-10"],
    ["dentista depois de amanhã", "dentista", "2026-10-11"],
    ["hoje revisar PR", "revisar PR", "2026-10-09"],
    ["pagar boleto na segunda", "pagar boleto", "2026-10-12"],
    ["reunião sexta", "reunião", "2026-10-16"],
    ["feira no sábado", "feira", "2026-10-10"],
    ["feira sabado", "feira", "2026-10-10"],
    ["terca-feira academia", "academia", "2026-10-13"],
    ["consulta 05/11", "consulta", "2026-11-05"],
    ["aniversário 01/10", "aniversário", "2027-10-01"],
    ["prova 10/10/27", "prova", "2027-10-10"]
  ])("%s", (text, title, date) => {
    const r = parseWhen(text, NOW);
    expect(r.title).toBe(title);
    expect(r.date).toBe(date);
  });

  it("ignores invalid calendar dates", () => {
    expect(parseWhen("31/02 teste", NOW)).toEqual({ title: "31/02 teste", date: null, start: null, end: null });
  });

  it("leaves text without date untouched", () => {
    expect(parseWhen("comprar 2 pães", NOW)).toEqual({ title: "comprar 2 pães", date: null, start: null, end: null });
  });

  it("does not match weekday names inside other words", () => {
    expect(parseWhen("segundas intenções", NOW).date).toBeNull();
  });
});
