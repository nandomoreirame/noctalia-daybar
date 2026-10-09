import { describe, it, expect } from "vitest";
import { describeWhen, relativeTime, relativeKey } from "../utils/format.js";

const NOW = new Date(2026, 9, 9, 15, 0);

describe("describeWhen", () => {
  it("names today and tomorrow, else dd/mm", () => {
    expect(describeWhen("2026-10-09", null, null, NOW)).toEqual({ day: "today", time: "" });
    expect(describeWhen("2026-10-10", "09:00", null, NOW)).toEqual({ day: "tomorrow", time: "09:00" });
    expect(describeWhen("2026-10-16", "15:00", "16:00", NOW)).toEqual({ day: "16/10", time: "15:00–16:00" });
  });

  it("handles a missing date", () => {
    expect(describeWhen(null, null, null, NOW)).toEqual({ day: "", time: "" });
  });
});

describe("format.relativeTime", () => {
  const NOW = new Date("2026-10-09T15:00:00.000Z");
  it.each([
    ["2026-10-09T14:59:40.000Z", { unit: "now", n: 0 }],
    ["2026-10-09T14:55:00.000Z", { unit: "minutes", n: 5 }],
    ["2026-10-09T12:00:00.000Z", { unit: "hours", n: 3 }],
    ["2026-10-06T15:00:00.000Z", { unit: "days", n: 3 }],
    ["2026-09-01T15:00:00.000Z", { unit: "date", n: 0, date: "2026-09-01" }],
    ["2026-10-09T15:05:00.000Z", { unit: "now", n: 0 }]
  ])("%s", (iso, expected) => {
    expect(relativeTime(iso, NOW)).toEqual(expected);
  });
});

describe("format.relativeKey", () => {
  it("maps units to i18n keys and leaves dates keyless", () => {
    expect(relativeKey({ unit: "now", n: 0 })).toEqual({ key: "time.now", n: 0, date: "" });
    expect(relativeKey({ unit: "minutes", n: 5 })).toEqual({ key: "time.minutes", n: 5, date: "" });
    expect(relativeKey({ unit: "date", n: 0, date: "2026-09-01" })).toEqual({ key: "", n: 0, date: "2026-09-01" });
  });
});
