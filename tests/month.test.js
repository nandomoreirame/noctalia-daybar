import { describe, it, expect } from "vitest";
import { monthGrid, shiftMonth } from "../utils/month.js";

const NOW = new Date(2026, 9, 9, 15, 0);

describe("monthGrid", () => {
  const ev = { uid: "e", start: new Date(2026, 9, 12, 10).getTime() / 1000, end: new Date(2026, 9, 12, 11).getTime() / 1000 };
  const grid = monthGrid(2026, 9, NOW, [ev]);

  it("starts on Monday and has 42 cells", () => {
    expect(grid).toHaveLength(42);
    expect(grid[0]).toMatchObject({ date: "2026-09-28", day: 28, inMonth: false });
    expect(grid[3]).toMatchObject({ date: "2026-10-01", day: 1, inMonth: true });
  });

  it("marks today and days with events", () => {
    expect(grid.find((c) => c.today).date).toBe("2026-10-09");
    expect(grid.filter((c) => c.hasEvents).map((c) => c.date)).toEqual(["2026-10-12"]);
  });

  it("handles a month starting on Monday", () => {
    expect(monthGrid(2026, 5, NOW, [])[0].date).toBe("2026-06-01");
  });
});

describe("shiftMonth", () => {
  it("wraps across years", () => {
    expect(shiftMonth(2026, 11, 1)).toEqual({ year: 2027, month: 0 });
    expect(shiftMonth(2026, 0, -1)).toEqual({ year: 2025, month: 11 });
  });
});
