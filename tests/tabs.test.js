import { describe, it, expect } from "vitest";
import { TABS, ICONS, initialTab, setLastTab } from "../utils/tabs.js";
import { createEmpty } from "../utils/store.js";

describe("tabs", () => {
  it("lists the toolbar tabs in order", () => {
    expect(TABS).toEqual(["calendar", "today", "focus", "bookmarks", "notes"]);
  });

  it("prefers an IPC request, then the setting, then the last tab", () => {
    expect(initialTab("notes", "today", "focus")).toBe("notes");
    expect(initialTab("", "last", "removed")).toBe("today");
    expect(initialTab("", "calendar", "focus")).toBe("calendar");
    expect(initialTab("", "last", "focus")).toBe("focus");
  });

  it("falls back to today for unknown or missing values", () => {
    expect(initialTab("", "last", "")).toBe("today");
    expect(initialTab("bogus", "bogus", "bogus")).toBe("today");
    expect(initialTab("", undefined, undefined)).toBe("today");
  });

  it("stores the last tab without mutating, ignoring unknown keys", () => {
    const data = createEmpty();
    const next = setLastTab(data, "focus");
    expect(next.ui.lastTab).toBe("focus");
    expect(data.ui.lastTab).toBe("");
    expect(setLastTab(next, "focus")).toBe(next);
    expect(setLastTab(next, "bogus")).toBe(next);
  });

  it("has one icon per tab, shared by the tab bar and the bar widget", () => {
    expect(Object.keys(ICONS).sort()).toEqual([...TABS].sort());
    expect(ICONS.calendar).toBe("calendar");
  });
});
