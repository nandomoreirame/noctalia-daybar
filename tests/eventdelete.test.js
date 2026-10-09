import { describe, it, expect } from "vitest";
import { calendarRoots, collectionsArgs, parseCollections, isReadOnlyCollection, isWritableCalendar, escapeRegex, findArgs, parsePaths, pickFile } from "../utils/eventdelete.js";

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

  it("accepts a single match", () => {
    expect(pickFile(["/r/me/1.ics"], cols, "Eventos")).toEqual({ ok: true, path: "/r/me/1.ics" });
    expect(pickFile(["/r/other/1.ics"], cols, "Eventos")).toEqual({ ok: true, path: "/r/other/1.ics" });
  });

  it("picks the copy in the event's calendar when the UID is in several", () => {
    expect(pickFile(["/r/me/1.ics", "/r/fam/9.ics"], cols, "Família")).toEqual({ ok: true, path: "/r/fam/9.ics" });
  });

  it("refuses when the calendar does not single one out", () => {
    expect(pickFile(["/r/me/1.ics", "/r/fam/9.ics"], cols, "Outra")).toEqual({ ok: false, error: "ambiguous" });
    expect(pickFile(["/r/me/1.ics", "/r/me/2.ics"], cols, "Eventos")).toEqual({ ok: false, error: "ambiguous" });
  });
});
