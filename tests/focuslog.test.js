import { describe, it, expect } from "vitest";
import { addSession, sessionsOn, goalJustReached } from "../utils/focuslog.js";
import { createEmpty } from "../utils/store.js";

describe("focus log", () => {
  it("counts completed focus sessions per day without mutating the input", () => {
    const data = createEmpty();
    const once = addSession(data, "2026-10-09");
    const twice = addSession(once, "2026-10-09");
    expect(sessionsOn(data, "2026-10-09")).toBe(0);
    expect(sessionsOn(twice, "2026-10-09")).toBe(2);
    expect(sessionsOn(addSession(twice, "2026-10-10"), "2026-10-10")).toBe(1);
  });

  it("tolerates a store without a focus log", () => {
    expect(sessionsOn({}, "2026-10-09")).toBe(0);
    expect(addSession({ tasks: [] }, "2026-10-09").focusLog).toEqual({ "2026-10-09": 1 });
  });

  it("reports the goal only on the session that reaches it", () => {
    expect(goalJustReached(7, 8)).toBe(false);
    expect(goalJustReached(8, 8)).toBe(true);
    expect(goalJustReached(9, 8)).toBe(false);
    expect(goalJustReached(1, 0)).toBe(false);
  });
});
