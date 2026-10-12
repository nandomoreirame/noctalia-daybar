import { describe, it, expect } from "vitest";
import { calendarRoots, calendarSections, collectionsArgs, parseCollections, isReadOnlyCollection, isWritableCalendar, isReadOnlyCalendar, escapeRegex, findArgs, parsePaths, pickFile, isRecurring, isDeletablePath, deleteArgs, readArgs, removeEventChecks, hideEvents, eventKey } from "../utils/eventdelete.js";

// Fixture home is /opt/u: absolute user-home paths are rejected by the commit hook.
const HOME = "/opt/u";

describe("calendarRoots", () => {
  it("reads every path = line, expanding ~ and stripping /* and trailing slashes", () => {
    const config = `[calendars]\n[[google]]\npath = ~/.local/share/calendars/google/*\ntype = discover\n[[work]]\n  path = "/data/cal/work/"\n[locale]\ntimeformat = %H:%M\n`;
    expect(calendarRoots(config, HOME)).toEqual(["/opt/u/.local/share/calendars/google", "/data/cal/work"]);
  });

  it("expands $HOME/ and ${HOME}/ like ~/, and strips trailing slashes before /*", () => {
    const config = "path = $HOME/.local/share/calendars/a/*\npath = ${HOME}/.local/share/calendars/b/\npath = /data/cal/c/*/\n";
    expect(calendarRoots(config, HOME)).toEqual([
      "/opt/u/.local/share/calendars/a",
      "/opt/u/.local/share/calendars/b",
      "/data/cal/c"
    ]);
  });

  it("drops duplicates and relative paths; empty config gives no roots", () => {
    expect(calendarRoots("path = rel/dir\npath = /a\npath = /a/", HOME)).toEqual(["/a"]);
    expect(calendarRoots("", HOME)).toEqual([]);
    expect(calendarRoots(null, HOME)).toEqual([]);
  });
});

describe("calendarSections", () => {
  it("maps [[name]] sections with type and path", () => {
    const config = `[calendars]
[[google]]
path = ~/.local/share/calendars/google/*
type = discover
[[work]]
path = /data/cal/work/
type = calendar
[[birthdays]]
path = /data/cal/bd/
type = calendar
`;
    expect(calendarSections(config, HOME)).toEqual([
      { name: "google", path: "/opt/u/.local/share/calendars/google", type: "discover" },
      { name: "work", path: "/data/cal/work", type: "calendar" },
      { name: "birthdays", path: "/data/cal/bd", type: "calendar" }
    ]);
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

  it("names a type=calendar collection by its section name", () => {
    const out = "/data/cal/work/displayname:Whatever\n";
    const sections = [{ name: "work", path: "/data/cal/work", type: "calendar" }, { name: "google", path: "/r/g", type: "discover" }];
    expect(parseCollections(out, sections)).toEqual([
      { dir: "/data/cal/work", id: "work", name: "work" }
    ]);
    expect(parseCollections("", sections)).toEqual([
      { dir: "/data/cal/work", id: "work", name: "work" }
    ]);
  });

  it("treats virtual, holiday, birthday, import and group calendars as read-only", () => {
    expect(isReadOnlyCollection("e1q2@virtual")).toBe(true);
    expect(isReadOnlyCollection("pt.brazilian#holiday@group.v.calendar.google.com")).toBe(true);
    expect(isReadOnlyCollection("#contacts@group.v.calendar.google.com")).toBe(true);
    expect(isReadOnlyCollection("abc#contacts@group.v.calendar.google.com")).toBe(true);
    expect(isReadOnlyCollection("xyz@import.calendar.google.com")).toBe(true);
    expect(isReadOnlyCollection("abc@group.v.calendar.google.com")).toBe(true);
    expect(isReadOnlyCollection("me@gmail.com")).toBe(false);
  });

  it("allows deleting only in calendars backed by a writable collection", () => {
    const cols = parseCollections("/r/a@virtual/displayname:Feriados\n/r/me@gmail.com/displayname:Eventos\n");
    expect(isWritableCalendar(cols, "Eventos")).toBe(true);
    expect(isWritableCalendar(cols, "Feriados")).toBe(false);
    expect(isWritableCalendar(cols, "Unknown")).toBe(false);
    expect(isWritableCalendar([], "Eventos")).toBe(false);
  });

  it("flags a calendar read-only only when every collection with its name is read-only", () => {
    const cols = parseCollections("/r/a@virtual/displayname:Feriados\n/r/me@gmail.com/displayname:Eventos\n");
    expect(isReadOnlyCalendar(cols, "Feriados")).toBe(true);
    expect(isReadOnlyCalendar(cols, "Eventos")).toBe(false);
    expect(isReadOnlyCalendar(cols, "Unknown")).toBe(false);
    expect(isReadOnlyCalendar([], "Feriados")).toBe(false);
    expect(isReadOnlyCalendar(undefined, "Feriados")).toBe(false);
  });
});

describe("UID lookup", () => {
  it("escapes regex metacharacters", () => {
    expect(escapeRegex("a.b+c(1)[x]")).toBe("a\\.b\\+c\\(1\\)\\[x\\]");
  });

  it("greps the exact UID line, PCRE, .ics only, roots after --", () => {
    expect(findArgs("7799ut.p@google.com", ["/r"])).toEqual(["grep", "-rlP", "--include=*.ics", "-e", "^UID:7799ut\\.p@google\\.com\\r?$", "--", "/r"]);
  });

  it("keeps a hostile UID inside one argument", () => {
    const args = findArgs("x$(rm -rf ~)", ["/r"]);
    expect(args[4]).toBe("^UID:x\\$\\(rm -rf ~\\)\\r?$");
    expect(args.length).toBe(7);
  });

  it("parses grep -l output into .ics paths", () => {
    expect(parsePaths("/r/a/1.ics\n\n/r/b/2.ics\nnoise\n")).toEqual(["/r/a/1.ics", "/r/b/2.ics"]);
  });
});

describe("pickFile", () => {
  const cols = [{ dir: "/r/me", id: "me", name: "Eventos" }, { dir: "/r/fam", id: "fam", name: "Família" }];

  it("returns not-found for no match", () => {
    expect(pickFile([], cols, "Eventos")).toEqual({ ok: false, error: "not-found" });
  });

  it("accepts a single match only when it sits in the event's writable calendar", () => {
    expect(pickFile(["/r/me/1.ics"], cols, "Eventos")).toEqual({ ok: true, path: "/r/me/1.ics" });
    expect(pickFile(["/r/other/1.ics"], cols, "Eventos")).toEqual({ ok: false, error: "ambiguous" });
  });

  it("refuses a single match in a read-only collection", () => {
    const ro = [{ dir: "/r/hol", id: "h@virtual", name: "Feriados" }];
    expect(pickFile(["/r/hol/1.ics"], ro, "Feriados")).toEqual({ ok: false, error: "read-only" });
  });

  it("picks the copy in the event's calendar when the UID is in several", () => {
    expect(pickFile(["/r/me/1.ics", "/r/fam/9.ics"], cols, "Família")).toEqual({ ok: true, path: "/r/fam/9.ics" });
  });

  it("refuses when the calendar does not single one out", () => {
    expect(pickFile(["/r/me/1.ics", "/r/fam/9.ics"], cols, "Outra")).toEqual({ ok: false, error: "ambiguous" });
    expect(pickFile(["/r/me/1.ics", "/r/me/2.ics"], cols, "Eventos")).toEqual({ ok: false, error: "ambiguous" });
  });
});

describe("recurrence", () => {
  it("detects RRULE and RECURRENCE-ID, not the words inside other properties", () => {
    expect(isRecurring("BEGIN:VEVENT\nRRULE:FREQ=WEEKLY\nEND:VEVENT")).toBe(true);
    expect(isRecurring("BEGIN:VEVENT\r\nRECURRENCE-ID;TZID=X:20261010T100000\r\nEND:VEVENT")).toBe(true);
    expect(isRecurring("BEGIN:VEVENT\nDESCRIPTION:no RRULE: here\nEND:VEVENT")).toBe(false);
    expect(isRecurring("")).toBe(false);
  });

  it("ignores RRULE inside a VTIMEZONE block", () => {
    const ics = "BEGIN:VCALENDAR\nBEGIN:VTIMEZONE\nTZID:X\nBEGIN:STANDARD\nRRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU\nEND:STANDARD\nEND:VTIMEZONE\nBEGIN:VEVENT\nUID:a\nSUMMARY:Once\nEND:VEVENT\nEND:VCALENDAR";
    expect(isRecurring(ics)).toBe(false);
  });
});

describe("paths and commands", () => {
  const roots = ["/opt/u/.local/share/calendars/google"];

  it("deletes only .ics files strictly inside a root, without dot segments", () => {
    expect(isDeletablePath("/opt/u/.local/share/calendars/google/me/1.ics", roots)).toBe(true);
    expect(isDeletablePath("/opt/u/.local/share/calendars/google/me/../../../x.ics", roots)).toBe(false);
    expect(isDeletablePath("/opt/u/.local/share/calendars/google/me/1.txt", roots)).toBe(false);
    expect(isDeletablePath("/opt/u/.local/share/calendars/googleX/me/1.ics", roots)).toBe(false);
    expect(isDeletablePath("/etc/passwd.ics", roots)).toBe(false);
  });

  it("builds rm and cat argv with the path after --", () => {
    expect(deleteArgs("/r/me/1.ics")).toEqual(["rm", "-f", "--", "/r/me/1.ics"]);
    expect(readArgs("/r/me/1.ics")).toEqual(["cat", "--", "/r/me/1.ics"]);
  });
});

describe("data cleanup", () => {
  it("removes every Today check of the UID", () => {
    const data = { eventChecks: { "u1|2026-10-09": true, "u1|2026-10-10": true, "u2|2026-10-09": true } };
    expect(removeEventChecks(data, "u1").eventChecks).toEqual({ "u2|2026-10-09": true });
    expect(data.eventChecks["u1|2026-10-09"]).toBe(true);
  });

  it("hides only events whose uid AND calendar match", () => {
    const events = [
      { uid: "a", calendar: "Work" },
      { uid: "a", calendar: "Home" },
      { uid: "b", calendar: "Work" }
    ];
    expect(hideEvents(events, [eventKey("a", "Work")])).toEqual([
      { uid: "a", calendar: "Home" },
      { uid: "b", calendar: "Work" }
    ]);
    expect(hideEvents(events, [])).toBe(events);
    expect(hideEvents(null, [eventKey("a", "Work")])).toEqual([]);
  });
});
