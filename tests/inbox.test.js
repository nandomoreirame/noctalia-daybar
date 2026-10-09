import { describe, it, expect } from "vitest";
import { createEmpty } from "../utils/store.js";
import { isHttpUrl, hasLink, addLink, archiveLink, addNote, deleteNote, prefillFromClipboard } from "../utils/inbox.js";

const T0 = "2026-10-09T15:00:00.000Z";

describe("inbox", () => {
  it.each([
    ["https://example.com", true],
    ["http://example.com/a?b=c#d", true],
    ["  https://example.com/x  ", true],
    ["ftp://example.com", false],
    ["https://", false],
    ["veja https://example.com", false],
    ["javascript:alert(1)", false],
    ["", false]
  ])("isHttpUrl(%j) = %s", (text, expected) => {
    expect(isHttpUrl(text)).toBe(expected);
  });

  it("adds links once and archives them", () => {
    let data = addLink(createEmpty(), " https://a.dev ", "l1", T0);
    data = addLink(data, "https://a.dev", "l2", T0);
    expect(data.links).toEqual([{ id: "l1", url: "https://a.dev", archived: false, createdAt: T0 }]);
    expect(hasLink(data, "https://a.dev")).toBe(true);
    expect(archiveLink(data, "l1").links[0].archived).toBe(true);
  });

  it("adds and deletes notes", () => {
    const data = addNote(createEmpty(), "  ideia  ", "n1", T0);
    expect(data.notes).toEqual([{ id: "n1", text: "ideia", createdAt: T0 }]);
    expect(deleteNote(data, "n1").notes).toEqual([]);
  });

  it("prefills only new http(s) URLs", () => {
    const data = addLink(createEmpty(), "https://old.dev", "l1", T0);
    expect(prefillFromClipboard("https://new.dev\n", data)).toBe("https://new.dev");
    expect(prefillFromClipboard("https://old.dev", data)).toBe("");
    expect(prefillFromClipboard("texto qualquer", data)).toBe("");
    expect(prefillFromClipboard(null, data)).toBe("");
  });
});
