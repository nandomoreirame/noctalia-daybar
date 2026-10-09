import { describe, it, expect } from "vitest";
import { resolve, nextType, prevType, CYCLE } from "../utils/capture/registry.js";

const NOW = new Date(2026, 9, 9, 15, 0);

describe("capture registry", () => {
  it("defaults to task", () => {
    expect(resolve("comprar pão", null, NOW).type).toBe("task");
  });

  it("always treats '=' as calculation, even with a forced type", () => {
    expect(resolve("=2+2", "note", NOW).payload.display).toBe("4");
  });

  it("applies prefixes and strips them", () => {
    expect(resolve("/e reunião sexta 15h", null, NOW).payload.title).toBe("reunião");
    expect(resolve("/l pagar boleto 18h", null, NOW).type).toBe("reminder");
    expect(resolve("/n uma ideia", null, NOW).payload).toEqual({ text: "uma ideia" });
    expect(resolve("/ex", null, NOW).type).toBe("task");
  });

  it("detects a lone URL as link", () => {
    expect(resolve("https://a.dev/x", null, NOW).type).toBe("link");
    expect(resolve("ler https://a.dev/x", null, NOW).type).toBe("task");
  });

  it("honors the Tab-forced type", () => {
    expect(resolve("https://a.dev", "note", NOW)).toMatchObject({ type: "note", payload: { text: "https://a.dev" } });
    expect(resolve("pagar boleto 18h", "reminder", NOW).type).toBe("reminder");
  });

  it("rejects empty input with the resolved type", () => {
    expect(resolve("  ", null, NOW)).toEqual({ ok: false, type: "task", error: "empty" });
    expect(resolve("/n", null, NOW)).toEqual({ ok: false, type: "note", error: "empty" });
  });

  it("cycles types with Tab", () => {
    expect(CYCLE).toEqual(["task", "event", "reminder", "note", "link"]);
    expect(nextType("task")).toBe("event");
    expect(nextType("link")).toBe("task");
    expect(nextType("calculation")).toBe("task");
  });

  it("cycles backwards with prevType (Shift+Tab)", () => {
    expect(prevType("event")).toBe("task");
    expect(prevType("task")).toBe("link");
    expect(prevType("calculation")).toBe("link");
    expect(CYCLE.map((t) => nextType(prevType(t)))).toEqual(CYCLE);
  });
});
