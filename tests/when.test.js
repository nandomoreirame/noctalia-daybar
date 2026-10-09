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

describe("parseWhen: times", () => {
  it.each([
    ["comprar pão amanhã 9h", { title: "comprar pão", date: "2026-10-10", start: "09:00", end: null }],
    ["ligar pro banco 16h", { title: "ligar pro banco", date: "2026-10-09", start: "16:00", end: null }],
    ["ligar pro banco 9h", { title: "ligar pro banco", date: "2026-10-10", start: "09:00", end: null }],
    ["standup 15h", { title: "standup", date: "2026-10-10", start: "15:00", end: null }],
    ["hoje 9h revisar", { title: "revisar", date: "2026-10-09", start: "09:00", end: null }],
    ["reunião sexta 15h-16h", { title: "reunião", date: "2026-10-16", start: "15:00", end: "16:00" }],
    ["15h às 16h30 call", { title: "call", date: "2026-10-10", start: "15:00", end: "16:30" }],
    ["depois de amanhã às 10h30 dentista", { title: "dentista", date: "2026-10-11", start: "10:30", end: null }],
    ["consulta 05/11 às 14:00", { title: "consulta", date: "2026-11-05", start: "14:00", end: null }],
    ["almoço 12:00 - 13:00 amanhã", { title: "almoço", date: "2026-10-10", start: "12:00", end: "13:00" }]
  ])("%s", (text, expected) => {
    expect(parseWhen(text, NOW)).toEqual(expected);
  });

  it("rejects impossible times", () => {
    expect(parseWhen("treino 25h", NOW)).toEqual({ title: "treino 25h", date: null, start: null, end: null });
    expect(parseWhen("treino 10h75", NOW).start).toBeNull();
  });

  it("leaves a range whose end is not after its start as plain text", () => {
    expect(parseWhen("plantão 23h-1h", NOW)).toEqual({ title: "plantão 23h-1h", date: null, start: null, end: null });
  });
});
