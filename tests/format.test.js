import { describe, it, expect } from "vitest";
import { describeWhen } from "../utils/format.js";

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
