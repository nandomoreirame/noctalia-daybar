import { describe, it, expect } from "vitest";
import { MAX_RECENT, normalizeRecent, addRecent, recordRecent, chipText, sameTimer } from "../utils/timers.js";

describe("recent timers", () => {
  it("puts the newest first, drops duplicates and keeps four", () => {
    let list = [];
    for (const e of [{ seconds: 60, label: "" }, { seconds: 300, label: "chá" }, { seconds: 600, label: "" }, { seconds: 900, label: "bolo" }, { seconds: 1200, label: "" }]) {
      list = addRecent(list, e);
    }
    expect(MAX_RECENT).toBe(4);
    expect(list).toEqual([{ seconds: 1200, label: "" }, { seconds: 900, label: "bolo" }, { seconds: 600, label: "" }, { seconds: 300, label: "chá" }]);
    expect(addRecent(list, { seconds: 300, label: "chá" })).toEqual([{ seconds: 300, label: "chá" }, { seconds: 1200, label: "" }, { seconds: 900, label: "bolo" }, { seconds: 600, label: "" }]);
  });

  it("returns the same list when the timer is already the newest", () => {
    const list = [{ seconds: 300, label: "chá" }];
    expect(addRecent(list, { seconds: 300, label: "chá" })).toBe(list);
  });

  it("tells timers apart by duration and label", () => {
    expect(sameTimer({ seconds: 300, label: "chá" }, { seconds: 300, label: "chá" })).toBe(true);
    expect(sameTimer({ seconds: 300, label: "chá" }, { seconds: 300, label: "" })).toBe(false);
  });

  it("normalizes stored entries", () => {
    const raw = [{ seconds: 300, label: "chá" }, { seconds: 0 }, { seconds: 86401 }, { seconds: 90.5 }, "x", null, { seconds: 60, label: 7 }, { seconds: 120 }, { seconds: 30 }, { seconds: 45 }];
    expect(normalizeRecent(raw)).toEqual([{ seconds: 300, label: "chá" }, { seconds: 60, label: "" }, { seconds: 120, label: "" }, { seconds: 30, label: "" }]);
    expect(normalizeRecent("x")).toEqual([]);
    expect(normalizeRecent(undefined)).toEqual([]);
  });

  it("records into the store data, same object when nothing changes", () => {
    const data = { tasks: [], recentTimers: [] };
    const next = recordRecent(data, { seconds: 300, label: "chá" });
    expect(next.recentTimers).toEqual([{ seconds: 300, label: "chá" }]);
    expect(data.recentTimers).toEqual([]);
    expect(recordRecent(next, { seconds: 300, label: "chá" })).toBe(next);
    expect(recordRecent({ tasks: [] }, { seconds: 60, label: "" }).recentTimers).toEqual([{ seconds: 60, label: "" }]);
  });

  it("formats the chip text with a short label", () => {
    expect(chipText({ seconds: 300, label: "" })).toBe("05:00");
    expect(chipText({ seconds: 300, label: "chá" })).toBe("05:00 · chá");
    expect(chipText({ seconds: 5400, label: "uma pausa bem longa para o café" })).toBe("1:30:00 · uma pausa bem lon…");
  });
});
