import { describe, it, expect } from "vitest";
import { add, applyPreview, setImage, markFailed, markOff, isCurrent, rename, remove, sorted, search, prefillFromClipboard, hasUrl } from "../utils/bookmarks.js";

const T0 = "2026-10-09T15:00:00.000Z";
const T1 = "2026-10-09T16:00:00.000Z";
const empty = () => ({ bookmarks: [] });

describe("bookmarks.add", () => {
  it("saves at once with the domain as title, pending when fetching is on", () => {
    const r = add(empty(), " https://www.site.com/a ", "b1", T0, true);
    expect(r.replaced).toBe(false);
    expect(r.bookmark).toEqual({
      id: "b1", url: "https://www.site.com/a", title: "site.com", description: "", image: "", imageUrl: "",
      status: "pending", token: 1, createdAt: T0, savedAt: T0
    });
    expect(r.data.bookmarks).toEqual([r.bookmark]);
  });

  it("marks the bookmark 'off' when fetching is disabled", () => {
    expect(add(empty(), "https://site.com", "b1", T0, false).bookmark.status).toBe("off");
  });

  it("rejects non-http input", () => {
    expect(add(empty(), "javascript:alert(1)", "b1", T0, true)).toBeNull();
  });

  it("replaces a duplicate: same id, moved to top, refetched with a new token", () => {
    let data = add(empty(), "https://site.com/a?utm_source=x", "b1", T0, true).data;
    data = add(data, "https://other.com", "b2", T0, true).data;
    data = rename(data, "b1", "My title");
    const r = add(data, "https://site.com/a/#top", "b3", T1, true);
    expect(r.replaced).toBe(true);
    expect(r.bookmark).toMatchObject({ id: "b1", url: "https://site.com/a/#top", title: "site.com", status: "pending", token: 2, createdAt: T0, savedAt: T1 });
    expect(r.data.bookmarks.map((b) => b.id)).toEqual(["b1", "b2"]);
  });
});

describe("bookmarks preview results", () => {
  const base = () => add(empty(), "https://site.com/a", "b1", T0, true).data;

  it("applies metadata for the current token", () => {
    const data = applyPreview(base(), "b1", 1, { title: "Title", description: "Desc", image: "https://cdn.com/i.png" });
    expect(data.bookmarks[0]).toMatchObject({ title: "Title", description: "Desc", imageUrl: "https://cdn.com/i.png", status: "ok" });
  });

  it("keeps the domain when the page has no title", () => {
    expect(applyPreview(base(), "b1", 1, { title: "", description: "", image: "" }).bookmarks[0].title).toBe("site.com");
  });

  it("ignores stale tokens and unknown ids (same object back)", () => {
    const data = base();
    expect(applyPreview(data, "b1", 7, { title: "x", description: "", image: "" })).toBe(data);
    expect(applyPreview(data, "zz", 1, { title: "x", description: "", image: "" })).toBe(data);
    expect(setImage(data, "b1", 7, "/t/b1")).toBe(data);
    expect(markFailed(data, "b1", 7)).toBe(data);
  });

  it("sets the cached image path and marks failures", () => {
    expect(setImage(base(), "b1", 1, "/t/b1").bookmarks[0].image).toBe("/t/b1");
    expect(markFailed(base(), "b1", 1).bookmarks[0]).toMatchObject({ status: "failed", title: "site.com" });
  });
});

describe("bookmarks edits and queries", () => {
  it("renames (trimmed, blank ignored) and removes", () => {
    const data = add(empty(), "https://site.com", "b1", T0, true).data;
    expect(rename(data, "b1", "  New  title ").bookmarks[0].title).toBe("New title");
    expect(rename(data, "b1", "  ")).toBe(data);
    expect(remove(data, "b1").bookmarks).toEqual([]);
  });

  it("sorts newest saved first and searches title, description and URL without accents", () => {
    let data = add(empty(), "https://a.com", "a", T0, true).data;
    data = add(data, "https://b.com", "b", T1, true).data;
    data = applyPreview(data, "a", 1, { title: "Ação rápida", description: "Notícias", image: "" });
    expect(sorted(data.bookmarks).map((b) => b.id)).toEqual(["b", "a"]);
    expect(search(data.bookmarks, "acao").map((b) => b.id)).toEqual(["a"]);
    expect(search(data.bookmarks, "noticias").map((b) => b.id)).toEqual(["a"]);
    expect(search(data.bookmarks, "b.com").map((b) => b.id)).toEqual(["b"]);
    expect(search(data.bookmarks, "").length).toBe(2);
  });

  it("prefills only http URLs that are not saved yet (normalized)", () => {
    const data = add(empty(), "https://site.com/a", "b1", T0, true).data;
    expect(hasUrl(data, "https://site.com/a/")).toBe(true);
    expect(prefillFromClipboard("https://site.com/a#x", data)).toBe("");
    expect(prefillFromClipboard(" https://new.com ", data)).toBe("https://new.com");
    expect(prefillFromClipboard("hello", data)).toBe("");
  });
});

describe("bookmarks fetch bookkeeping", () => {
  const base = () => add({ bookmarks: [] }, "https://site.com/a", "b1", T0, true).data;

  it("marks a dropped fetch as off for the current token only", () => {
    expect(markOff(base(), "b1", 1).bookmarks[0].status).toBe("off");
    const data = base();
    expect(markOff(data, "b1", 9)).toBe(data);
  });

  it("knows whether a job still matches a live bookmark", () => {
    const data = base();
    expect(isCurrent(data, "b1", 1)).toBe(true);
    expect(isCurrent(data, "b1", 2)).toBe(false);
    expect(isCurrent(remove(data, "b1"), "b1", 1)).toBe(false);
  });
});

