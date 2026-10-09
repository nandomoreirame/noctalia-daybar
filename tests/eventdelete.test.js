import { describe, it, expect } from "vitest";
import { calendarRoots, collectionsArgs, parseCollections, isReadOnlyCollection, isWritableCalendar } from "../utils/eventdelete.js";

// Fixture home is /opt/u: a /home/<name> path is rejected by the commit hook.
const HOME = "/opt/u";

describe("calendarRoots", () => {
  it("reads every path = line, expanding ~ and stripping /* and trailing slashes", () => {
    const config = `[calendars]\n[[google]]\npath = ~/.local/share/calendars/google/*\ntype = discover\n[[work]]\n  path = "/data/cal/work/"\n[locale]\ntimeformat = %H:%M\n`;
    expect(calendarRoots(config, HOME)).toEqual(["/opt/u/.local/share/calendars/google", "/data/cal/work"]);
  });

  it("drops duplicates and relative paths; empty config gives no roots", () => {
    expect(calendarRoots("path = rel/dir\npath = /a\npath = /a/", HOME)).toEqual(["/a"]);
    expect(calendarRoots("", HOME)).toEqual([]);
    expect(calendarRoots(null, HOME)).toEqual([]);
  });
});

describe("collections", () => {
  it("lists displayname files recursively under the roots", () => {
    expect(collectionsArgs(["/r1", "/r2"])).toEqual(["grep", "-rH", "--include=displayname", "", "--", "/r1", "/r2"]);
  });

  it("parses grep -H output into dir, id and name", () => {
    const out = "/r/abc@virtual/displayname:Feriados no Brasil\n/r/me@gmail.com/displayname:Eventos\n\n";
    expect(parseCollections(out)).toEqual([
      { dir: "/r/abc@virtual", id: "abc@virtual", name: "Feriados no Brasil" },
      { dir: "/r/me@gmail.com", id: "me@gmail.com", name: "Eventos" }
    ]);
  });

  it("treats virtual and holiday collections as read-only", () => {
    expect(isReadOnlyCollection("e1q2@virtual")).toBe(true);
    expect(isReadOnlyCollection("pt.brazilian#holiday@group.v.calendar.google.com")).toBe(true);
    expect(isReadOnlyCollection("me@gmail.com")).toBe(false);
  });

  it("allows deleting only in calendars backed by a writable collection", () => {
    const cols = parseCollections("/r/a@virtual/displayname:Feriados\n/r/me@gmail.com/displayname:Eventos\n");
    expect(isWritableCalendar(cols, "Eventos")).toBe(true);
    expect(isWritableCalendar(cols, "Feriados")).toBe(false);
    expect(isWritableCalendar(cols, "Unknown")).toBe(false);
    expect(isWritableCalendar([], "Eventos")).toBe(false);
  });
});
