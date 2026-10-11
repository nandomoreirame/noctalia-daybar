import { describe, it, expect } from "vitest";
import { parseDuration, MAX_SECONDS } from "../utils/duration.js";

describe("parseDuration", () => {
  it.each([
    ["90s", 90],
    ["10m", 600],
    ["10min", 600],
    ["10MIN", 600],
    ["1h", 3600],
    ["1h30", 5400],
    ["1h30m", 5400],
    ["1:30", 90],
    ["1:02:03", 3723],
    ["25", 1500]
  ])("%s -> %i s", (text, seconds) => {
    expect(parseDuration(text)).toEqual({ ok: true, seconds, label: "" });
  });

  it("keeps the other words as the label, wherever the duration is", () => {
    expect(parseDuration("chá 5m")).toEqual({ ok: true, seconds: 300, label: "chá" });
    expect(parseDuration("10m tirar o bolo")).toEqual({ ok: true, seconds: 600, label: "tirar o bolo" });
  });

  it("prefers a token with a unit over a bare number", () => {
    expect(parseDuration("2 ovos 7m")).toEqual({ ok: true, seconds: 420, label: "2 ovos" });
  });

  it("fails without a duration", () => {
    expect(parseDuration("chá")).toEqual({ ok: false, error: "needs-duration" });
    expect(parseDuration("")).toEqual({ ok: false, error: "needs-duration" });
    expect(parseDuration(null)).toEqual({ ok: false, error: "needs-duration" });
  });

  it("rejects zero, more than 24 h and out-of-range fields", () => {
    for (const t of ["0", "0s", "25h", "1441m", "1:75", "1h75", "86401s"]) {
      expect(parseDuration(t)).toEqual({ ok: false, error: "invalid-duration" });
    }
    expect(parseDuration("24h")).toEqual({ ok: true, seconds: MAX_SECONDS, label: "" });
    expect(parseDuration("86400s")).toEqual({ ok: true, seconds: MAX_SECONDS, label: "" });
  });

  it("checks each field at its boundary", () => {
    expect(parseDuration("1:59").seconds).toBe(119);
    expect(parseDuration("1h59").seconds).toBe(7140);
    expect(parseDuration("1:59:59").seconds).toBe(7199);
    for (const t of ["1:60", "1h60", "1:60:00", "1:00:60", "0:00"]) {
      expect(parseDuration(t)).toEqual({ ok: false, error: "invalid-duration" });
    }
  });

  it("reads oversized numbers as invalid, not as missing", () => {
    for (const t of ["100000s", "99999", "100:00:00", "12345m"]) {
      expect(parseDuration(t)).toEqual({ ok: false, error: "invalid-duration" });
    }
  });

  it("accepts 1h30min", () => {
    expect(parseDuration("1H30MIN")).toEqual({ ok: true, seconds: 5400, label: "" });
  });

  it("sums consecutive unit words", () => {
    expect(parseDuration("1h 30m chá")).toEqual({ ok: true, seconds: 5400, label: "chá" });
    expect(parseDuration("bolo 5m 30s")).toEqual({ ok: true, seconds: 330, label: "bolo" });
  });

  it("prefers h/m/s units over a clock time in the label", () => {
    expect(parseDuration("reunião às 14:30 5m")).toEqual({ ok: true, seconds: 300, label: "reunião às 14:30" });
    expect(parseDuration("chá 1:30")).toEqual({ ok: true, seconds: 90, label: "chá" });
  });

  it("takes a bare number only as the first word", () => {
    expect(parseDuration("10 chá")).toEqual({ ok: true, seconds: 600, label: "chá" });
    expect(parseDuration("ler 3 capítulos")).toEqual({ ok: false, error: "needs-duration" });
  });
});
