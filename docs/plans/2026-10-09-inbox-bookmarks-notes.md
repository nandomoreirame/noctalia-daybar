# Plan: Bookmarks and Notes

> **Spec:** docs/specs/inbox-bookmarks-notes/SPEC.md

**Goal:** Replace the Inbox tab with a Bookmarks tab (browser-like previews fetched once and cached) and a Notes tab (Markdown notes opened in their own overlay window with autosave).
**Architecture:** Pure logic in new `utils/` libraries (`text.js`, `url.js`, `pagemeta.js`, `fetch.js`, `fetchpool.js`, `bookmarks.js`, `notes.js`, `markdown.js`), unit-tested with vitest; store schema moves to v2 (no migration). `Main.qml` owns the bookmark fetch pool (curl argv processes) and the note window; `BookmarksView.qml`, `NotesView.qml`, `NoteWindow.qml` and `components/ui/ConfirmButton.qml` are thin UI.
**Tech Stack:** QML (Quickshell / noctalia-shell 4.7.x), ES2018 JavaScript, vitest 2, curl.
**Total Tasks:** 20
**Estimated Complexity:** large (Deep)

---

## Conventions for every task

- Repo root: `~/dev/projects/noctalia-daybar` (run every command from there).
- `npm test -- <file>` for one file, `npm test` for the suite. Read the `Tests  N passed` line; never trust a piped exit code.
- `utils/**/*.js` start with `.pragma library`; cross-file deps use `.import "x.js" as X`; top-level declarations at column 0 (the test transform exports them by regex). No ES `import`/`export`, no `URL`, no `String.prototype.normalize` (not guaranteed in the QML JS engine).
- No `eval`, no `Function`, no shell strings: every external command is an argv array.
- Page metadata is untrusted: always rendered with `textFormat: Text.PlainText`.
- Do NOT reference any previous or source project in code, comments, docs or commits.
- QML tasks have no automated harness. Their check is a runtime one: restart the shell (`qs -c noctalia-shell kill`, wait until `pgrep -x qs` is empty, then start it detached), then `grep -iE "ReferenceError|TypeError|is not a type|non-existent" "$(ls -t /run/user/1000/quickshell/by-id/*/log.log | head -1)"` must print nothing about daybar, plus the visual check described in the task.
- Commit after every task with `/git commit` (never raw git). Implementers (subagents / external CLIs) DO NOT run any git command; only the orchestrator commits.
- New UI strings go into BOTH `i18n/pt.json` and `i18n/en.json` (Task 11 adds all of them up front).

## Dependency graph

```
T1 text ── T2 url ─┬─ T3 pagemeta
                   ├─ T5 bookmarks (needs T1, T2)
                   └─ T9 capture/clipboard (needs T5)
T4 fetch (argv)
T6 fetchpool
T7 notes (needs T1)
T8 markdown (needs T2)
T10 store v2 + tabs (needs T5, T7 shapes)
T11 i18n keys
T12 relative time
T13 settings toggle (manifest + Settings.qml)
T14 ConfirmButton (ui)
T15 Main services (needs T3-T10, T13)
T16 BookmarksView (needs T14, T15)
T17 NoteWindow (needs T8, T14, T15)
T18 NotesView (needs T12, T14, T17)
T19 Panel wiring, InboxView removal (needs T16, T18)
T20 Docs, smoke rows, final verification (all)
```

Parallel batches: {T1, T4, T6, T11, T12, T13, T14} → {T2, T7} → {T3, T5, T8} → {T9, T10} → T15 → {T16, T17} → T18 → T19 → T20.

---

### Task 1: Accent-insensitive text folding

**Requirement:** REQ-010, REQ-011 (search)
**Files:**
- Create: `utils/text.js`
- Test: `tests/text.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**

`tests/text.test.js`:
```js
import { describe, it, expect } from "vitest";
import { fold, matches } from "../utils/text.js";

describe("text.fold", () => {
  it("lowercases and strips pt-BR accents", () => {
    expect(fold("Ação É Ótima, CÃO")).toBe("acao e otima, cao");
    expect(fold("Ç ü ñ")).toBe("c u n");
  });

  it("handles empty and non-string input", () => {
    expect(fold("")).toBe("");
    expect(fold(null)).toBe("");
    expect(fold(undefined)).toBe("");
  });
});

describe("text.matches", () => {
  it("matches every word of the query in any of the fields", () => {
    expect(matches(["Reunião de equipe", "notas"], "reuniao")).toBe(true);
    expect(matches(["Reunião de equipe", "notas"], "equipe notas")).toBe(true);
    expect(matches(["Reunião de equipe"], "equipe cafe")).toBe(false);
  });

  it("matches everything for a blank query", () => {
    expect(matches(["x"], "   ")).toBe(true);
    expect(matches([], "")).toBe(true);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/text.test.js`
Expected: FAIL (cannot resolve `../utils/text.js`).

**Step 3: Write minimal implementation**

`utils/text.js`:
```js
.pragma library

// Search helpers. String.prototype.normalize is not guaranteed in the QML JS
// engine, so accents are folded with an explicit table.

var FOLD = [
  [/[áàâãäå]/g, "a"], [/[éèêë]/g, "e"], [/[íìîï]/g, "i"], [/[óòôõö]/g, "o"],
  [/[úùûü]/g, "u"], [/ç/g, "c"], [/ñ/g, "n"]
];

function fold(value) {
  let s = String(value === null || value === undefined ? "" : value).toLowerCase();
  for (const [re, plain] of FOLD) s = s.replace(re, plain);
  return s;
}

// True when every whitespace-separated word of `query` appears in some field.
function matches(fields, query) {
  const words = fold(query).split(/\s+/).filter((w) => w.length > 0);
  if (words.length === 0) return true;
  const haystack = fields.map(fold).join("\n");
  return words.every((w) => haystack.indexOf(w) >= 0);
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/text.test.js`
Expected: PASS (4 tests).

**Step 5: Commit**
Run: `/git commit`

---

### Task 2: URL helpers (validation, normalization, domain, resolution)

**Requirement:** REQ-003, REQ-004, REQ-005, REQ-006
**Files:**
- Create: `utils/url.js`
- Test: `tests/url.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development, security-guardrails)
- Reviewers: business-logic-reviewer, security-reviewer, test-reviewer

**Step 1: Write the failing test**

`tests/url.test.js`:
```js
import { describe, it, expect } from "vitest";
import { isHttpUrl, normalizeUrl, domainOf, resolveUrl } from "../utils/url.js";

describe("url.isHttpUrl", () => {
  it.each([
    ["https://example.com", true],
    ["http://example.com/a?b=c#d", true],
    ["  https://example.com/x  ", true],
    ["ftp://example.com", false],
    ["https://", false],
    ["veja https://example.com", false],
    ["javascript:alert(1)", false],
    ["", false]
  ])("%j -> %s", (text, expected) => {
    expect(isHttpUrl(text)).toBe(expected);
  });
});

describe("url.normalizeUrl", () => {
  it.each([
    ["https://Example.COM/Path/", "https://example.com/Path"],
    ["https://example.com/a#section", "https://example.com/a"],
    ["https://example.com/a?utm_source=x&id=7&UTM_medium=y", "https://example.com/a?id=7"],
    ["https://example.com/?utm_campaign=z", "https://example.com"],
    ["  http://example.com  ", "http://example.com"]
  ])("%j -> %j", (input, expected) => {
    expect(normalizeUrl(input)).toBe(expected);
  });

  it("returns an empty string for non-http input", () => {
    expect(normalizeUrl("javascript:alert(1)")).toBe("");
    expect(normalizeUrl("")).toBe("");
  });
});

describe("url.domainOf", () => {
  it("returns the host without www and port", () => {
    expect(domainOf("https://www.GitHub.com/a")).toBe("github.com");
    expect(domainOf("http://localhost:8080/x")).toBe("localhost");
    expect(domainOf("not a url")).toBe("");
  });
});

describe("url.resolveUrl", () => {
  const page = "https://site.com/blog/post.html?x=1";
  it.each([
    ["https://cdn.com/a.png", "https://cdn.com/a.png"],
    ["//cdn.com/a.png", "https://cdn.com/a.png"],
    ["/img/a.png", "https://site.com/img/a.png"],
    ["a.png", "https://site.com/blog/a.png"],
    ["  /x.png  ", "https://site.com/x.png"],
    ["data:image/png;base64,AAA", ""],
    ["javascript:alert(1)", ""],
    ["", ""]
  ])("%j -> %j", (ref, expected) => {
    expect(resolveUrl(ref, page)).toBe(expected);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/url.test.js`
Expected: FAIL (cannot resolve `../utils/url.js`).

**Step 3: Write minimal implementation**

`utils/url.js`:
```js
.pragma library

// URL helpers without the URL class (not available in the QML JS engine).

var HTTP_RE = /^https?:\/\/[^\s/$.?#][^\s]*$/i;

function isHttpUrl(text) {
  return HTTP_RE.test(String(text || "").trim());
}

// Identity used to detect duplicates: lowercase scheme and host, no #fragment,
// no utm_* parameters, no trailing slash.
function normalizeUrl(url) {
  const s = String(url || "").trim();
  if (!isHttpUrl(s)) return "";
  const noHash = s.split("#")[0];
  const q = noHash.indexOf("?");
  let base = q >= 0 ? noHash.slice(0, q) : noHash;
  const query = q >= 0 ? noHash.slice(q + 1) : "";
  const params = query.split("&").filter((p) => p !== "" && !/^utm_/i.test(p.split("=")[0]));
  base = base.replace(/^https?:\/\/[^/]+/i, (origin) => origin.toLowerCase()).replace(/\/+$/, "");
  return params.length > 0 ? base + "?" + params.join("&") : base;
}

function domainOf(url) {
  const m = /^https?:\/\/([^/?#:]+)/i.exec(String(url || "").trim());
  return m ? m[1].toLowerCase().replace(/^www\./, "") : "";
}

// Resolves an href/src found in a page against the page URL. Only http(s)
// results are returned; anything else (data:, javascript:, ...) gives "".
function resolveUrl(ref, pageUrl) {
  const r = String(ref || "").trim();
  if (!r) return "";
  if (isHttpUrl(r)) return r;
  const page = /^(https?):\/\/([^/?#]+)([^?#]*)/i.exec(String(pageUrl || "").trim());
  if (!page) return "";
  const scheme = page[1].toLowerCase();
  let out = "";
  if (r.indexOf("//") === 0) out = scheme + ":" + r;
  else if (r.charAt(0) === "/") out = scheme + "://" + page[2] + r;
  else if (/^[a-z][a-z0-9+.-]*:/i.test(r)) return "";
  else out = scheme + "://" + page[2] + (page[3] ? page[3].replace(/[^/]*$/, "") : "/") + r;
  return isHttpUrl(out) ? out : "";
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/url.test.js`
Expected: PASS (all cases).

**Step 5: Commit**
Run: `/git commit`

---

### Task 3: Page metadata parser

**Requirement:** REQ-005, REQ-006
**Files:**
- Create: `utils/pagemeta.js`
- Test: `tests/pagemeta.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development, security-guardrails)
- Reviewers: business-logic-reviewer, security-reviewer, test-reviewer

**Step 1: Write the failing test**

`tests/pagemeta.test.js`:
```js
import { describe, it, expect } from "vitest";
import { parse, decodeEntities } from "../utils/pagemeta.js";

const PAGE = "https://site.com/blog/post";

describe("pagemeta.decodeEntities", () => {
  it("decodes named and numeric entities", () => {
    expect(decodeEntities("A &amp; B &lt;3&gt; &quot;x&quot; &#39;y&#39; &#x41;&#66; caf&eacute;")).toBe("A & B <3> \"x\" 'y' AB café");
  });

  it("leaves unknown entities and invalid code points alone", () => {
    expect(decodeEntities("&bogus; &#xFFFFFFFF;")).toBe("&bogus; &#xFFFFFFFF;");
  });
});

describe("pagemeta.parse", () => {
  it("prefers Open Graph tags", () => {
    const html = `<html><head><title>Plain</title>
      <meta property="og:title" content="OG Title">
      <meta content="OG description" property="og:description" />
      <meta property='og:image' content='/img/cover.png'>
      <meta name="description" content="Meta description"></head></html>`;
    expect(parse(html, PAGE)).toEqual({ title: "OG Title", description: "OG description", image: "https://site.com/img/cover.png" });
  });

  it("falls back to twitter tags, <title> and meta description", () => {
    const html = `<TITLE>  Fallback
      title </TITLE><meta name="Description" content="Desc">
      <meta name="twitter:image" content="https://cdn.com/t.jpg">`;
    expect(parse(html, PAGE)).toEqual({ title: "Fallback title", description: "Desc", image: "https://cdn.com/t.jpg" });
  });

  it("decodes entities, strips tags and treats markup as text", () => {
    const html = `<meta property="og:title" content="&lt;script&gt;alert(1)&lt;/script&gt; Tom &amp; Jerry">`;
    expect(parse(html, PAGE).title).toBe("alert(1) Tom & Jerry");
  });

  it("caps title at 200 and description at 400 characters", () => {
    const long = "x".repeat(1000);
    const r = parse(`<meta property="og:title" content="${long}"><meta property="og:description" content="${long}">`, PAGE);
    expect(r.title.length).toBe(200);
    expect(r.description.length).toBe(400);
  });

  it("ignores non-http images and returns empty fields for empty input", () => {
    expect(parse(`<meta property="og:image" content="data:image/png;base64,AAAA">`, PAGE).image).toBe("");
    expect(parse("", PAGE)).toEqual({ title: "", description: "", image: "" });
    expect(parse(null, PAGE)).toEqual({ title: "", description: "", image: "" });
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/pagemeta.test.js`
Expected: FAIL (cannot resolve `../utils/pagemeta.js`).

**Step 3: Write minimal implementation**

`utils/pagemeta.js`:
```js
.pragma library
.import "url.js" as Url

// Extracts { title, description, image } from untrusted page HTML. Results are
// plain text (tags stripped, entities decoded, length capped); the UI must still
// render them as PlainText.

var TITLE_MAX = 200;
var DESC_MAX = 400;
var NAMED = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " ", eacute: "é", aacute: "á", oacute: "ó", iacute: "í", uacute: "ú", atilde: "ã", otilde: "õ", ccedil: "ç", ecirc: "ê", acirc: "â", ocirc: "ô", agrave: "à", hellip: "…", mdash: "—", ndash: "–", rsquo: "’", lsquo: "‘", rdquo: "”", ldquo: "“" };

function decodeEntities(text) {
  return String(text || "").replace(/&(#x[0-9a-f]+|#[0-9]+|[a-z]+);/gi, (whole, body) => {
    if (body.charAt(0) === "#") {
      const code = body.charAt(1).toLowerCase() === "x" ? parseInt(body.slice(2), 16) : parseInt(body.slice(1), 10);
      return code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : whole;
    }
    const named = NAMED[body.toLowerCase()];
    return named === undefined ? whole : named;
  });
}

function clean(text, max) {
  const plain = decodeEntities(text).replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
  return plain.length > max ? plain.slice(0, max) : plain;
}

function attributes(tag) {
  const attrs = {};
  const re = /([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*("([^"]*)"|'([^']*)'|([^\s"'>]+))/g;
  let m;
  while ((m = re.exec(tag)) !== null) {
    const value = m[3] !== undefined ? m[3] : (m[4] !== undefined ? m[4] : m[5]);
    attrs[m[1].toLowerCase()] = value;
  }
  return attrs;
}

// Content of the first <meta property|name="key">, or "".
function metaContent(html, keys) {
  const tags = html.match(/<meta\b[^>]*>/gi) || [];
  for (const key of keys) {
    for (const tag of tags) {
      const a = attributes(tag);
      const id = String(a.property || a.name || "").toLowerCase();
      if (id === key && a.content) return a.content;
    }
  }
  return "";
}

function parse(html, pageUrl) {
  const source = String(html || "");
  if (!source) return { title: "", description: "", image: "" };
  const titleTag = /<title\b[^>]*>([\s\S]*?)<\/title>/i.exec(source);
  const title = metaContent(source, ["og:title", "twitter:title"]) || (titleTag ? titleTag[1] : "");
  const description = metaContent(source, ["og:description", "twitter:description", "description"]);
  const image = metaContent(source, ["og:image", "og:image:url", "og:image:secure_url", "twitter:image"]);
  return {
    title: clean(title, TITLE_MAX),
    description: clean(description, DESC_MAX),
    image: Url.resolveUrl(decodeEntities(image), pageUrl)
  };
}
```

Note on the hostile-title test: `&lt;script&gt;` decodes to `<script>`, which `clean` strips as a tag, leaving `alert(1) Tom & Jerry` after whitespace collapse. Keep decode before strip so encoded markup never survives as markup.

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/pagemeta.test.js`
Expected: PASS (7 tests).

**Step 5: Commit**
Run: `/git commit`

---

### Task 4: curl argv builders

**Requirement:** REQ-005, REQ-006, REQ-018 (thumbnail removal)
**Files:**
- Create: `utils/fetch.js`
- Test: `tests/fetch.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development, security-guardrails)
- Reviewers: security-reviewer, test-reviewer

**Step 1: Write the failing test**

`tests/fetch.test.js`:
```js
import { describe, it, expect } from "vitest";
import { pageArgs, imageArgs, thumbPath, removeArgs, isUsableExit } from "../utils/fetch.js";

const LIMITS = ["--proto", "=http,https", "--proto-redir", "=http,https", "--max-time", "8", "--max-filesize", "2000000", "--max-redirs", "5"];

describe("fetch argv", () => {
  it("fetches a page with protocol, time and size limits, URL after --", () => {
    const args = pageArgs("https://site.com/a");
    expect(args.slice(0, 2)).toEqual(["curl", "-sSL"]);
    expect(args).toEqual(expect.arrayContaining(LIMITS));
    expect(args.slice(-2)).toEqual(["--", "https://site.com/a"]);
  });

  it("downloads an image to a given path with the same limits", () => {
    const args = imageArgs("https://cdn.com/a.png", "/tmp/thumbs/abc");
    expect(args).toEqual(expect.arrayContaining(LIMITS));
    expect(args).toEqual(expect.arrayContaining(["-o", "/tmp/thumbs/abc"]));
    expect(args.slice(-2)).toEqual(["--", "https://cdn.com/a.png"]);
  });

  it("keeps a hostile URL as one inert argument", () => {
    const args = pageArgs("https://x.com/;rm -rf ~");
    expect(args[args.length - 1]).toBe("https://x.com/;rm -rf ~");
  });

  it("builds thumbnail paths from internal ids only", () => {
    expect(thumbPath("/c/thumbs", "lz3k-9f")).toBe("/c/thumbs/lz3k-9f");
    expect(thumbPath("/c/thumbs", "../etc/passwd")).toBe("");
    expect(removeArgs("/c/thumbs/lz3k-9f")).toEqual(["rm", "-f", "--", "/c/thumbs/lz3k-9f"]);
  });

  it("accepts a clean exit and a truncated-at-cap exit", () => {
    expect(isUsableExit(0)).toBe(true);
    expect(isUsableExit(63)).toBe(true);
    expect(isUsableExit(28)).toBe(false);
    expect(isUsableExit(6)).toBe(false);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/fetch.test.js`
Expected: FAIL (cannot resolve `../utils/fetch.js`).

**Step 3: Write minimal implementation**

`utils/fetch.js`:
```js
.pragma library

// argv builders for preview fetching. Always arrays (Process.command), URL last
// after "--", http/https only, bounded in time, size and redirects.

var UA = "Mozilla/5.0 (X11; Linux x86_64) Daybar/0.2";
var LIMITS = ["--proto", "=http,https", "--proto-redir", "=http,https", "--max-time", "8", "--max-filesize", "2000000", "--max-redirs", "5"];

function pageArgs(url) {
  return ["curl", "-sSL"].concat(LIMITS, ["-A", UA, "-H", "Accept-Language: pt-BR,pt;q=0.9,en;q=0.8", "--", url]);
}

function imageArgs(url, outPath) {
  return ["curl", "-sSL"].concat(LIMITS, ["-A", UA, "-o", outPath, "--", url]);
}

// Ids come from Store.makeId (base36 and "-"); anything else is refused so a
// path can never escape the thumbnail directory.
function thumbPath(dir, id) {
  return /^[a-z0-9-]+$/i.test(String(id || "")) ? dir + "/" + id : "";
}

function removeArgs(path) {
  return ["rm", "-f", "--", path];
}

// 0 = ok; 63 = stopped at --max-filesize (whatever arrived is still parsed).
function isUsableExit(code) {
  return code === 0 || code === 63;
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/fetch.test.js`
Expected: PASS (5 tests).

**Step 5: Commit**
Run: `/git commit`

---

### Task 5: Bookmark operations

**Requirement:** REQ-003, REQ-004, REQ-005, REQ-007, REQ-008, REQ-009, REQ-010, REQ-019
**Files:**
- Create: `utils/bookmarks.js`
- Test: `tests/bookmarks.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**

`tests/bookmarks.test.js`:
```js
import { describe, it, expect } from "vitest";
import { add, applyPreview, setImage, markFailed, rename, remove, sorted, search, prefillFromClipboard, hasUrl } from "../utils/bookmarks.js";

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
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/bookmarks.test.js`
Expected: FAIL (cannot resolve `../utils/bookmarks.js`).

**Step 3: Write minimal implementation**

`utils/bookmarks.js`:
```js
.pragma library
.import "url.js" as Url
.import "text.js" as Text

// Bookmark operations. Pure; every function returns a NEW data object (or the
// same one when nothing changes). `token` increases on every (re)save so results
// from a superseded fetch are ignored.
// bookmark: { id, url, title, description, image, imageUrl, status, token, createdAt, savedAt }
// status: "pending" (fetch queued/running), "ok", "failed", "off" (fetching disabled)

function findByUrl(data, url) {
  const key = Url.normalizeUrl(url);
  return key ? data.bookmarks.find((b) => Url.normalizeUrl(b.url) === key) || null : null;
}

function hasUrl(data, url) {
  return findByUrl(data, url) !== null;
}

// Returns { data, bookmark, replaced } or null for an invalid URL.
function add(data, rawUrl, id, nowIso, fetchEnabled) {
  const url = String(rawUrl || "").trim();
  if (!Url.isHttpUrl(url)) return null;
  const existing = findByUrl(data, url);
  const bookmark = {
    id: existing ? existing.id : id,
    url: url,
    title: Url.domainOf(url),
    description: "",
    image: "",
    imageUrl: "",
    status: fetchEnabled ? "pending" : "off",
    token: existing ? existing.token + 1 : 1,
    createdAt: existing ? existing.createdAt : nowIso,
    savedAt: nowIso
  };
  const rest = data.bookmarks.filter((b) => b.id !== bookmark.id);
  return { data: Object.assign({}, data, { bookmarks: [bookmark].concat(rest) }), bookmark: bookmark, replaced: !!existing };
}

function update(data, id, token, patch) {
  const target = data.bookmarks.find((b) => b.id === id);
  if (!target || (token !== null && target.token !== token)) return data;
  return Object.assign({}, data, { bookmarks: data.bookmarks.map((b) => b.id !== id ? b : Object.assign({}, b, patch(b))) });
}

function applyPreview(data, id, token, meta) {
  return update(data, id, token, (b) => ({
    title: meta.title || Url.domainOf(b.url),
    description: meta.description || "",
    imageUrl: meta.image || "",
    status: "ok"
  }));
}

function setImage(data, id, token, path) {
  return update(data, id, token, () => ({ image: path }));
}

function markFailed(data, id, token) {
  return update(data, id, token, () => ({ status: "failed" }));
}

function rename(data, id, title) {
  const clean = String(title || "").replace(/\s+/g, " ").trim();
  if (!clean) return data;
  return update(data, id, null, () => ({ title: clean }));
}

function remove(data, id) {
  return Object.assign({}, data, { bookmarks: data.bookmarks.filter((b) => b.id !== id) });
}

function sorted(list) {
  return list.slice().sort((a, b) => (a.savedAt < b.savedAt ? 1 : a.savedAt > b.savedAt ? -1 : 0));
}

function search(list, query) {
  return list.filter((b) => Text.matches([b.title, b.description, b.url], query));
}

// Clipboard text to prefill the capture field with: a new http(s) URL, else "".
function prefillFromClipboard(clip, data) {
  const s = String(clip || "").trim();
  return Url.isHttpUrl(s) && !hasUrl(data, s) ? s : "";
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/bookmarks.test.js`
Expected: PASS (11 tests).

**Step 5: Commit**
Run: `/git commit`

---

### Task 6: Fetch pool (max 3 concurrent, deduplicated)

**Requirement:** REQ-007, REQ-019 (drop queue when disabled)
**Files:**
- Create: `utils/fetchpool.js`
- Test: `tests/fetchpool.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**

`tests/fetchpool.test.js`:
```js
import { describe, it, expect } from "vitest";
import { createPool, request, finish, clearQueue } from "../utils/fetchpool.js";

const job = (id, token = 1) => ({ id, token, url: "https://" + id + ".com" });

describe("fetch pool", () => {
  it("starts up to the limit and queues the rest", () => {
    let p = createPool(3);
    const started = [];
    for (const id of ["a", "b", "c", "d"]) {
      const r = request(p, job(id));
      p = r.pool;
      started.push(...r.start);
    }
    expect(started.map((j) => j.id)).toEqual(["a", "b", "c"]);
    expect(p.queue.map((j) => j.id)).toEqual(["d"]);
  });

  it("starts the next queued job when one finishes", () => {
    let p = createPool(1);
    p = request(p, job("a")).pool;
    p = request(p, job("b")).pool;
    const r = finish(p, "a");
    expect(r.start.map((j) => j.id)).toEqual(["b"]);
    expect(r.pool.running.map((j) => j.id)).toEqual(["b"]);
  });

  it("replaces a queued job for the same id with the newer token", () => {
    let p = createPool(1);
    p = request(p, job("a")).pool;
    p = request(p, job("b", 1)).pool;
    p = request(p, job("b", 2)).pool;
    expect(p.queue).toEqual([job("b", 2)]);
  });

  it("queues a refetch of a running id until that run finishes", () => {
    let p = createPool(3);
    p = request(p, job("a", 1)).pool;
    const r = request(p, job("a", 2));
    expect(r.start).toEqual([]);
    expect(finish(r.pool, "a").start).toEqual([job("a", 2)]);
  });

  it("ignores finish for an id that is not running and can drop the queue", () => {
    let p = createPool(1);
    p = request(p, job("a")).pool;
    p = request(p, job("b")).pool;
    expect(finish(p, "zz").start).toEqual([]);
    p = clearQueue(p);
    expect(p.queue).toEqual([]);
    expect(p.running.map((j) => j.id)).toEqual(["a"]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/fetchpool.test.js`
Expected: FAIL (cannot resolve `../utils/fetchpool.js`).

**Step 3: Write minimal implementation**

`utils/fetchpool.js`:
```js
.pragma library

// Bounded pool for preview fetches. Pure state; Main.qml owns the processes.
// job: { id, token, url }. At most one running job per id.

function createPool(limit) {
  return { limit: limit, queue: [], running: [] };
}

function drain(pool) {
  const start = [];
  let queue = pool.queue.slice();
  let running = pool.running.slice();
  let i = 0;
  while (running.length < pool.limit && i < queue.length) {
    const next = queue[i];
    if (running.some((j) => j.id === next.id)) {
      i++;
      continue;
    }
    queue.splice(i, 1);
    running.push(next);
    start.push(next);
  }
  return { pool: { limit: pool.limit, queue: queue, running: running }, start: start };
}

function request(pool, job) {
  const queue = pool.queue.filter((j) => j.id !== job.id).concat([job]);
  return drain({ limit: pool.limit, queue: queue, running: pool.running });
}

function finish(pool, id) {
  if (!pool.running.some((j) => j.id === id)) return { pool: pool, start: [] };
  return drain({ limit: pool.limit, queue: pool.queue, running: pool.running.filter((j) => j.id !== id) });
}

function clearQueue(pool) {
  return { limit: pool.limit, queue: [], running: pool.running };
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/fetchpool.test.js`
Expected: PASS (5 tests).

**Step 5: Commit**
Run: `/git commit`

---

### Task 7: Note operations and derived title/snippet

**Requirement:** REQ-011, REQ-014, REQ-015, REQ-017
**Files:**
- Create: `utils/notes.js`
- Test: `tests/notes.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**

`tests/notes.test.js`:
```js
import { describe, it, expect } from "vitest";
import { titleOf, snippetOf, isBlank, add, update, remove, sorted, search } from "../utils/notes.js";

const T0 = "2026-10-09T15:00:00.000Z";
const T1 = "2026-10-09T16:00:00.000Z";

describe("notes derived fields", () => {
  it.each([
    ["# Shopping list\n- milk", "Shopping list"],
    ["\n\n  **Bold** and _it_ `code`  \nmore", "Bold and it code"],
    ["- [x] done item", "done item"],
    ["> quoted [link](https://x.com) ![img](a.png)", "quoted link img"],
    ["1. first", "first"],
    ["   \n  ", ""]
  ])("titleOf(%j) = %j", (text, title) => {
    expect(titleOf(text)).toBe(title);
  });

  it("snippets the text after the title line as one plain line, capped at 140", () => {
    expect(snippetOf("# Title\n\nFirst **line**\n- second")).toBe("First line second");
    expect(snippetOf("only title")).toBe("");
    expect(snippetOf("t\n" + "word ".repeat(100)).length).toBe(140);
  });

  it("detects blank notes", () => {
    expect(isBlank("  \n\t ")).toBe(true);
    expect(isBlank("x")).toBe(false);
  });
});

describe("notes operations", () => {
  it("adds with created and updated timestamps", () => {
    const data = add({ notes: [] }, "  hello  ", "n1", T0);
    expect(data.notes).toEqual([{ id: "n1", text: "hello", createdAt: T0, updatedAt: T0 }]);
  });

  it("updates text and timestamp, returns the same object when unchanged", () => {
    const data = add({ notes: [] }, "a", "n1", T0);
    const next = update(data, "n1", "b", T1);
    expect(next.notes[0]).toEqual({ id: "n1", text: "b", createdAt: T0, updatedAt: T1 });
    expect(update(next, "n1", "b", "2026-10-09T17:00:00.000Z")).toBe(next);
    expect(update(next, "zz", "c", T1)).toBe(next);
  });

  it("keeps the text verbatim on update (no trim) so the editor cursor does not jump", () => {
    const data = add({ notes: [] }, "a", "n1", T0);
    expect(update(data, "n1", "line \n", T1).notes[0].text).toBe("line \n");
  });

  it("removes, sorts by last edit and searches without accents", () => {
    let data = add({ notes: [] }, "Reunião", "a", T0);
    data = add(data, "Café", "b", T0);
    data = update(data, "a", "Reunião de equipe", T1);
    expect(sorted(data.notes).map((n) => n.id)).toEqual(["a", "b"]);
    expect(search(data.notes, "reuniao").map((n) => n.id)).toEqual(["a"]);
    expect(remove(data, "a").notes.map((n) => n.id)).toEqual(["b"]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/notes.test.js`
Expected: FAIL (cannot resolve `../utils/notes.js`).

**Step 3: Write minimal implementation**

`utils/notes.js`:
```js
.pragma library
.import "text.js" as Text

// Markdown notes. The title is derived from the first non-empty line.
// note: { id, text, createdAt, updatedAt }

var SNIPPET_MAX = 140;

// Markdown markup removed for list display (not a renderer).
function stripMarkup(line) {
  return String(line)
    .replace(/^\s{0,3}(#{1,6}\s+|>\s*|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+)/, "")
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/(\*\*|__|~~|`|\*|_)/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function lines(text) {
  return String(text || "").split(/\r?\n/);
}

function titleIndex(text) {
  const all = lines(text);
  for (let i = 0; i < all.length; i++) if (all[i].trim() !== "") return i;
  return -1;
}

function titleOf(text) {
  const i = titleIndex(text);
  return i < 0 ? "" : stripMarkup(lines(text)[i]);
}

function snippetOf(text) {
  const i = titleIndex(text);
  if (i < 0) return "";
  const rest = lines(text).slice(i + 1).map(stripMarkup).filter((l) => l !== "").join(" ");
  return rest.length > SNIPPET_MAX ? rest.slice(0, SNIPPET_MAX) : rest;
}

function isBlank(text) {
  return String(text || "").trim() === "";
}

function add(data, text, id, nowIso) {
  const note = { id: id, text: String(text || "").trim(), createdAt: nowIso, updatedAt: nowIso };
  return Object.assign({}, data, { notes: data.notes.concat([note]) });
}

function update(data, id, text, nowIso) {
  const target = data.notes.find((n) => n.id === id);
  if (!target || target.text === text) return data;
  return Object.assign({}, data, { notes: data.notes.map((n) => n.id !== id ? n : Object.assign({}, n, { text: text, updatedAt: nowIso })) });
}

function remove(data, id) {
  return Object.assign({}, data, { notes: data.notes.filter((n) => n.id !== id) });
}

function sorted(list) {
  return list.slice().sort((a, b) => (a.updatedAt < b.updatedAt ? 1 : a.updatedAt > b.updatedAt ? -1 : 0));
}

function search(list, query) {
  return list.filter((n) => Text.matches([n.text], query));
}
```

Note on the "sorted" test: `a` and `b` are created at the same `T0`; `a` is then updated to `T1`, so `a` sorts first.

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/notes.test.js`
Expected: PASS (all cases).

**Step 5: Commit**
Run: `/git commit`

---

### Task 8: Markdown safety pre-pass and link filter

**Requirement:** REQ-016
**Files:**
- Create: `utils/markdown.js`
- Test: `tests/markdown.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development, security-guardrails)
- Reviewers: security-reviewer, test-reviewer

**Step 1: Write the failing test**

`tests/markdown.test.js`:
```js
import { describe, it, expect } from "vitest";
import { prepare, isOpenableLink } from "../utils/markdown.js";

describe("markdown.prepare", () => {
  it("turns remote images into links with their alt text", () => {
    expect(prepare("see ![a cat](https://x.com/cat.png) here")).toBe("see [a cat](https://x.com/cat.png) here");
    expect(prepare('![](http://x.com/a.png "t")')).toBe("[http://x.com/a.png](http://x.com/a.png)");
  });

  it("keeps local images", () => {
    expect(prepare("![local](file:///opt/u/a.png)")).toBe("![local](file:///opt/u/a.png)");
    expect(prepare("![abs](/opt/u/a.png)")).toBe("![abs](/opt/u/a.png)");
  });

  it("removes raw <img> tags that point to the network", () => {
    expect(prepare('a <img src="https://x.com/t.gif"> b')).toBe("a  b");
    expect(prepare("<IMG SRC='//x.com/t.gif'/>")).toBe("");
  });

  it("returns an empty string for empty input", () => {
    expect(prepare("")).toBe("");
    expect(prepare(null)).toBe("");
  });
});

describe("markdown.isOpenableLink", () => {
  it.each([
    ["https://x.com", true],
    ["http://x.com/a", true],
    ["mailto:me@x.com", true],
    ["javascript:alert(1)", false],
    ["file:///etc/passwd", false],
    ["data:text/html,hi", false],
    ["", false]
  ])("%j -> %s", (url, expected) => {
    expect(isOpenableLink(url)).toBe(expected);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/markdown.test.js`
Expected: FAIL (cannot resolve `../utils/markdown.js`).

**Step 3: Write minimal implementation**

`utils/markdown.js`:
```js
.pragma library
.import "url.js" as Url

// Pre-pass before Qt's native Markdown renderer: a note never loads anything
// from the network by itself. Remote images become links; raw remote <img>
// tags are dropped. Links are opened by the UI only when isOpenableLink().

function prepare(text) {
  return String(text || "")
    .replace(/!\[([^\]]*)\]\(\s*((?:https?:)?\/\/[^)\s]+)(?:\s+"[^"]*")?\s*\)/gi, (whole, alt, src) => "[" + (alt || src) + "](" + src + ")")
    .replace(/<img\b[^>]*\bsrc\s*=\s*["']?\s*(?:https?:)?\/\/[^>]*>/gi, "");
}

function isOpenableLink(url) {
  const s = String(url || "").trim();
  return Url.isHttpUrl(s) || /^mailto:[^\s@]+@[^\s@]+$/i.test(s);
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/markdown.test.js`
Expected: PASS (all cases).

**Step 5: Commit**
Run: `/git commit`

---

### Task 9: Capture handlers point at bookmarks; drop `utils/inbox.js`

**Requirement:** REQ-003, REQ-017
**Files:**
- Modify: `utils/capture/link.js`
- Modify: `tests/capture.test.js` (link action name)
- Delete: `utils/inbox.js`, `tests/inbox.test.js` (replaced by `url.js` + `bookmarks.js`)

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: consequences-reviewer, test-reviewer

**Step 1: Write the failing test**

In `tests/capture.test.js`, change every expectation of the link handler's `action` from `"addLink"` to `"addBookmark"` (payload stays `{ url }`). Run `grep -n addLink tests/` to find them.

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/capture.test.js`
Expected: FAIL (`expected 'addLink' to be 'addBookmark'`).

**Step 3: Write minimal implementation**

`utils/capture/link.js`:
```js
.pragma library
.import "../url.js" as Url

// Link capture: an http(s) URL saved as a bookmark (preview fetched later).
var TYPE = "link";

function isLink(text) {
  return Url.isHttpUrl(text);
}

function build(text) {
  const url = String(text || "").trim();
  if (!Url.isHttpUrl(url)) return { ok: false, type: TYPE, error: "invalid-url" };
  return { ok: true, type: TYPE, action: "addBookmark", payload: { url: url } };
}
```

Then delete `utils/inbox.js` and `tests/inbox.test.js` (their cases now live in `tests/url.test.js` and `tests/bookmarks.test.js`). `Main.qml` still imports `inbox.js` until Task 15; that only matters at runtime, not for `npm test`.

**Step 4: Run test to verify it passes**
Run: `npm test`
Expected: PASS (whole suite; `tests/inbox.test.js` gone).

**Step 5: Commit**
Run: `/git commit`

---

### Task 10: Store v2 and the five tabs

**Requirement:** REQ-001, REQ-002
**Files:**
- Modify: `utils/store.js`
- Modify: `utils/tabs.js`
- Modify: `tests/store.test.js`, `tests/tabs.test.js`, `tests/i18n.test.js` (tab keys)

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, consequences-reviewer, test-reviewer

**Step 1: Write the failing test**

`tests/store.test.js` (replace the empty-store expectation and add the v2 cases):
```js
  it("creates an empty v2 store", () => {
    expect(VERSION).toBe(2);
    expect(createEmpty()).toEqual({ version: 2, tasks: [], eventChecks: {}, reminders: [], bookmarks: [], notes: [], focusLog: {}, ui: { lastTab: "" } });
  });

  it("drops v1 links and notes without migrating them", () => {
    const { data } = parse(JSON.stringify({ version: 1, links: [{ id: "l", url: "https://x.com" }], notes: [{ id: "n", text: "x" }], tasks: [{ id: "t", title: "keep" }] }));
    expect(data.bookmarks).toEqual([]);
    expect(data.notes).toEqual([]);
    expect(data.tasks.map((t) => t.id)).toEqual(["t"]);
    expect(data.links).toBeUndefined();
  });

  it("keeps v2 bookmarks and notes", () => {
    const b = { id: "b", url: "https://x.com", title: "x.com", description: "", image: "", imageUrl: "", status: "ok", token: 1, createdAt: "t", savedAt: "t" };
    const n = { id: "n", text: "# hi", createdAt: "t", updatedAt: "t" };
    const { data } = parse(JSON.stringify({ version: 2, bookmarks: [b], notes: [n] }));
    expect(data.bookmarks).toEqual([b]);
    expect(data.notes).toEqual([n]);
  });

  it("resets a pending bookmark fetch left over from a previous run", () => {
    const b = { id: "b", url: "https://x.com", title: "x.com", description: "", image: "", imageUrl: "", status: "pending", token: 3, createdAt: "t", savedAt: "t" };
    expect(parse(JSON.stringify({ version: 2, bookmarks: [b] })).data.bookmarks[0].status).toBe("failed");
  });
```
Also update the existing "migrates an unversioned file" test: it must expect `bookmarks: []` and no `links` key.

`tests/tabs.test.js`:
```js
  it("lists the toolbar tabs in order", () => {
    expect(TABS).toEqual(["calendar", "today", "focus", "bookmarks", "notes"]);
  });
```
and in "prefers an IPC request..." replace `"inbox"` with `"notes"`; add `expect(initialTab("", "last", "inbox")).toBe("today");`.
In `tests/i18n.test.js` change the tab list in `DYNAMIC` to `["calendar", "today", "focus", "bookmarks", "notes"]`.

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/store.test.js tests/tabs.test.js`
Expected: FAIL (`VERSION` is 1; `TABS` still has `inbox`).

**Step 3: Write minimal implementation**

`utils/store.js`:
- `var VERSION = 2;`
- `createEmpty()` returns `{ version: VERSION, tasks: [], eventChecks: {}, reminders: [], bookmarks: [], notes: [], focusLog: {}, ui: { lastTab: "" } }`.
- In `migrate(raw)`, replace the `links`/`notes` lines with:
```js
    bookmarks: raw.version >= 2 ? list(raw.bookmarks).map(normalizeBookmark) : [],
    notes: raw.version >= 2 ? list(raw.notes) : [],
```
- Add above `migrate`:
```js
// A fetch cannot survive a restart; a bookmark still "pending" on load failed.
function normalizeBookmark(b) {
  return b && b.status === "pending" ? Object.assign({}, b, { status: "failed" }) : b;
}
```
- Header comment: `// v2: links were replaced by bookmarks; v1 links/notes are dropped (test data).`

`utils/tabs.js`:
```js
var TABS = ["calendar", "today", "focus", "bookmarks", "notes"];
var FALLBACK = "today";
var ICONS = { calendar: "calendar", today: "list-check", focus: "hourglass", bookmarks: "bookmark", notes: "notes" };
```

Also rename the i18n key `tabs.inbox` to two keys `tabs.bookmarks` / `tabs.notes` in both catalogs here (Task 11 adds the rest): pt `"Favoritos"`, `"Notas"`; en `"Bookmarks"`, `"Notes"`. Remove `tabs.inbox`. Update `Settings.qml` initial-tab model list to `["calendar", "today", "focus", "bookmarks", "notes"]`.

**Step 4: Run test to verify it passes**
Run: `npm test`
Expected: PASS (whole suite).

**Step 5: Commit**
Run: `/git commit`

---

### Task 11: Translations for bookmarks, notes and the confirm bubble

**Requirement:** REQ-008 to REQ-019 (UI strings)
**Files:**
- Modify: `i18n/pt.json`, `i18n/en.json`
- Modify: `tests/i18n.test.js` (dynamic keys)

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: pt-br-accent-fix)
- Reviewers: test-reviewer

**Step 1: Write the failing test**

Append to `DYNAMIC` in `tests/i18n.test.js`:
```js
  ...["now", "minutes", "hours", "days"].map((u) => "time." + u),
  "bookmarks.saved", "bookmarks.replaced", "notes.untitled"
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/i18n.test.js`
Expected: FAIL (missing keys).

**Step 3: Write minimal implementation**

Keep the `inbox` section for now (`InboxView.qml` still uses it; Task 19 removes both). Add (pt shown; en mirrors it):

```json
  "bookmarks": {
    "title": "Favoritos",
    "search": "Buscar favoritos",
    "add-placeholder": "Cole um link https://... e Enter",
    "empty": "Nenhum favorito. Cole um link abaixo ou use a captura.",
    "no-results": "Nada encontrado.",
    "open": "Abrir",
    "copy": "Copiar URL",
    "refresh": "Atualizar prévia",
    "rename": "Editar título",
    "delete": "Excluir",
    "confirm-delete": "Excluir este favorito?",
    "saved": "Favorito salvo",
    "replaced": "Favorito atualizado",
    "invalid": "Link inválido"
  },
  "notes": {
    "title": "Notas",
    "search": "Buscar notas",
    "new": "Nova nota",
    "empty": "Nenhuma nota. Crie uma ou use /n na captura.",
    "no-results": "Nada encontrado.",
    "untitled": "Sem título",
    "copy": "Copiar",
    "delete": "Excluir",
    "confirm-delete": "Excluir esta nota?",
    "edit": "Editar",
    "preview": "Visualizar",
    "close": "Fechar",
    "edited": "Editada {time}",
    "placeholder": "Escreva em Markdown...",
    "keys": "Ctrl+E edita/visualiza · Ctrl+S salva · Esc fecha"
  },
  "confirm": {
    "ok": "OK",
    "cancel": "Cancelar"
  },
  "time": {
    "now": "agora",
    "minutes": "há {n} min",
    "hours": "há {n} h",
    "days": "há {n} d"
  },
```
en values: "Bookmarks", "Search bookmarks", "Paste an https://... link and press Enter", "No bookmarks. Paste a link below or use capture.", "Nothing found.", "Open", "Copy URL", "Refresh preview", "Edit title", "Delete", "Delete this bookmark?", "Bookmark saved", "Bookmark updated", "Invalid link"; notes: "Notes", "Search notes", "New note", "No notes. Create one or use /n in capture.", "Nothing found.", "Untitled", "Copy", "Delete", "Delete this note?", "Edit", "Preview", "Close", "Edited {time}", "Write in Markdown...", "Ctrl+E edit/preview · Ctrl+S save · Esc close"; confirm: "OK", "Cancel"; time: "now", "{n} min ago", "{n} h ago", "{n} d ago".
Also add under `settings`: pt `"fetch-previews": "Buscar prévia dos links"`, `"fetch-previews-help": "Ao salvar um favorito, baixa título, descrição e imagem da página."`; en `"Fetch link previews"`, `"When a bookmark is saved, download the page's title, description and image."`. Change `capture.saved.link` to pt `"Favorito salvo"` / en `"Bookmark saved"`.
Run the `pt-br-accent-fix` skill over the pt strings.

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/i18n.test.js`
Expected: PASS (both catalogs have the same keys, including the new dynamic ones).

**Step 5: Commit**
Run: `/git commit`

---

### Task 12: Relative time for the notes list

**Requirement:** REQ-011, REQ-012
**Files:**
- Modify: `utils/format.js`
- Modify: `tests/format.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: test-reviewer

**Step 1: Write the failing test**

Append to `tests/format.test.js` (add `relativeTime` to the import):
```js
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
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/format.test.js`
Expected: FAIL (`relativeTime` is not exported).

**Step 3: Write minimal implementation**

Append to `utils/format.js` (it already imports `dates.js` as `Dates`; if not, add `.import "dates.js" as Dates`):
```js
// "now" < 1 min (or in the future), then minutes, hours, days up to 6, else the date.
function relativeTime(iso, now) {
  const ms = now.getTime() - new Date(iso).getTime();
  const min = Math.floor(ms / 60000);
  if (min < 1) return { unit: "now", n: 0 };
  if (min < 60) return { unit: "minutes", n: min };
  const hours = Math.floor(min / 60);
  if (hours < 24) return { unit: "hours", n: hours };
  const days = Math.floor(hours / 24);
  if (days < 7) return { unit: "days", n: days };
  return { unit: "date", n: 0, date: Dates.isoDate(new Date(iso)) };
}
```
Note: `isoDate` is local-time; run tests with the repo default TZ (the existing date tests already assume local time). If the `date` case is TZ-sensitive on the CI box, use a mid-day timestamp as above.

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/format.test.js`
Expected: PASS.

**Step 5: Commit**
Run: `/git commit`

---

### Task 13: "Fetch link previews" setting

**Requirement:** REQ-019
**Files:**
- Modify: `manifest.json` (`metadata.defaultSettings.fetchPreviews: true`)
- Modify: `tests/manifest.test.js`
- Modify: `Settings.qml`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: test-reviewer

**Step 1: Write the failing test**
In `tests/manifest.test.js`, add `"fetchPreviews"` to the sorted default-settings key list.

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/manifest.test.js`
Expected: FAIL (key missing).

**Step 3: Write minimal implementation**
- `manifest.json`: add `"fetchPreviews": true` to `defaultSettings`.
- `Settings.qml`: add `property bool fetchPreviews: true`; `loadSettings()` reads `fetchPreviews = value("fetchPreviews")`; `saveSettings()` writes `s.fetchPreviews = fetchPreviews`; under the "General" header add:
```qml
  NToggle {
    label: root.tr("settings.fetch-previews")
    description: root.tr("settings.fetch-previews-help")
    checked: root.fetchPreviews
    onToggled: checked => root.fetchPreviews = checked
  }
```

**Step 4: Run test to verify it passes**
Run: `npm test`
Expected: PASS.

**Step 5: Commit**
Run: `/git commit`

---

### Task 14: Confirm bubble button

**Requirement:** REQ-018
**Files:**
- Create: `components/ui/ConfirmButton.qml`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: test-reviewer

**Step 1: Write the failing test**
Runtime check: temporarily drop `ConfirmButton { icon: "trash"; question: "Delete?"; okText: "OK"; cancelText: "Cancel"; onConfirmed: console.log("daybar confirm ok") }` into `components/TodayView.qml`'s header row, restart the shell, open Today.

**Step 2: Run test to verify it fails**
Expected: FAIL — log shows `ConfirmButton is not a type`.

**Step 3: Write minimal implementation**

`components/ui/ConfirmButton.qml`:
```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Icon button that asks before acting: a bubble anchored to it with a question,
// "OK" and "Cancel". Focus starts on Cancel; Esc or a click outside cancels.
PillButton {
  id: root

  property string question: ""
  property string okText: "OK"
  property string cancelText: "Cancel"
  signal confirmed

  danger: true
  onClicked: bubble.open()

  Popup {
    id: bubble
    // Opens below the button, right-aligned to it; flips above when there is no room.
    readonly property real gap: Math.round(6 * Style.uiScaleRatio)
    x: root.width - width
    y: root.height + gap
    margins: Style.marginS
    padding: Math.round(10 * Style.uiScaleRatio)
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onOpened: cancelButton.forceActiveFocus()

    background: Rectangle {
      radius: Math.round(12 * Style.uiScaleRatio)
      color: Color.mSurface
      border.color: Qt.alpha(Color.mOnSurface, 0.12)
      border.width: Style.borderS
    }

    contentItem: ColumnLayout {
      spacing: Math.round(8 * Style.uiScaleRatio)

      NText {
        text: root.question
        pointSize: Style.fontSizeS
        color: Color.mOnSurface
      }

      RowLayout {
        Layout.alignment: Qt.AlignRight
        spacing: Math.round(6 * Style.uiScaleRatio)

        PillButton {
          id: cancelButton
          text: root.cancelText
          onClicked: bubble.close()
        }

        PillButton {
          primary: true
          text: root.okText
          onClicked: {
            bubble.close();
            root.confirmed();
          }
        }
      }
    }
  }
}
```

**Step 4: Run test to verify it passes**
Restart the shell, open Today, click the test trash: the bubble opens under it with focus on Cancel; Esc and clicking outside close it with no log line; OK prints `daybar confirm ok` in the shell log. Then remove the temporary line from `TodayView.qml`.
Expected: PASS (no `daybar` errors; behaviour as described).

**Step 5: Commit**
Run: `/git commit`

---

### Task 15: Main services (bookmarks fetch pool, thumbnails, notes, note window)

**Requirement:** REQ-002 to REQ-007, REQ-011 to REQ-018
**Files:**
- Modify: `Main.qml`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: security-guardrails, performance-guardrails)
- Reviewers: business-logic-reviewer, security-reviewer, consequences-reviewer

**Step 1: Write the failing test**
Runtime check: `qs -c noctalia-shell ipc call plugin:daybar capture`, type `https://example.com`, Enter.

**Step 2: Run test to verify it fails**
Expected: FAIL — `executeCapture` has no `addBookmark` branch (nothing saved), and `Main.qml` still imports the deleted `utils/inbox.js` (log: module not found).

**Step 3: Write minimal implementation**

Imports: replace `import "utils/inbox.js" as Inbox` with
```qml
import "utils/url.js" as Url
import "utils/bookmarks.js" as Bookmarks
import "utils/notes.js" as Notes
import "utils/pagemeta.js" as PageMeta
import "utils/fetch.js" as Fetch
import "utils/fetchpool.js" as FetchPool
```

Replace the old inbox functions (`addLink`, `archiveLink`, `addNote`, `deleteNote`) and `openUrl` with:
```qml
  // ---------------------------------------------------------------- bookmarks

  readonly property string thumbsDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/noctalia-daybar/thumbs"
  readonly property bool fetchPreviews: setting("fetchPreviews") !== false
  property var fetchPool: FetchPool.createPool(3)

  Process {
    command: ["mkdir", "-p", root.thumbsDir]
    running: true
  }

  onFetchPreviewsChanged: if (!fetchPreviews) fetchPool = FetchPool.clearQueue(fetchPool)

  // Returns "saved", "replaced" or "invalid".
  function addBookmark(url) {
    const r = Bookmarks.add(data, url, newId(), nowIso(), fetchPreviews);
    if (!r)
      return "invalid";
    commit(r.data);
    if (fetchPreviews)
      requestPreview(r.bookmark);
    return r.replaced ? "replaced" : "saved";
  }

  function refreshBookmark(id) {
    const b = data.bookmarks.find(x => x.id === id);
    if (b)
      addBookmark(b.url);
  }

  function renameBookmark(id, title) { commit(Bookmarks.rename(data, id, title)); }

  function deleteBookmark(id) {
    const path = Fetch.thumbPath(thumbsDir, id);
    commit(Bookmarks.remove(data, id));
    if (path)
      Quickshell.execDetached(Fetch.removeArgs(path));
  }

  function requestPreview(bookmark) {
    const r = FetchPool.request(fetchPool, { id: bookmark.id, token: bookmark.token, url: bookmark.url });
    fetchPool = r.pool;
    r.start.forEach(startPreview);
  }

  function finishPreview(id) {
    const r = FetchPool.finish(fetchPool, id);
    fetchPool = r.pool;
    r.start.forEach(startPreview);
  }

  Component {
    id: pageFetcher
    Process {
      property var job: null
      stdout: StdioCollector {
        id: pageOut
      }
      onExited: function (exitCode) {
        root.onPageFetched(job, exitCode, pageOut.text);
        destroy();
      }
    }
  }

  Component {
    id: imageFetcher
    Process {
      property var job: null
      property string path: ""
      onExited: function (exitCode) {
        // Keep the file only if the bookmark still exists with this token
        // (it may have been deleted or re-saved while downloading).
        const current = root.data.bookmarks.some(b => b.id === job.id && b.token === job.token);
        if (exitCode === 0 && current)
          root.commit(Bookmarks.setImage(root.data, job.id, job.token, path));
        else if (!root.data.bookmarks.some(b => b.id === job.id))
          Quickshell.execDetached(Fetch.removeArgs(path));
        root.finishPreview(job.id);
        destroy();
      }
    }
  }

  function startPreview(job) {
    const p = pageFetcher.createObject(root, { job: job, command: Fetch.pageArgs(job.url) });
    p.running = true;
  }

  function onPageFetched(job, exitCode, html) {
    const meta = Fetch.isUsableExit(exitCode) ? PageMeta.parse(html, job.url) : null;
    if (!meta || (!meta.title && !meta.description && !meta.image)) {
      commit(Bookmarks.markFailed(data, job.id, job.token));
      finishPreview(job.id);
      return;
    }
    commit(Bookmarks.applyPreview(data, job.id, job.token, meta));
    const path = Fetch.thumbPath(thumbsDir, job.id);
    const current = data.bookmarks.find(b => b.id === job.id);
    if (!meta.image || !path || !current || current.token !== job.token) {
      finishPreview(job.id);
      return;
    }
    const img = imageFetcher.createObject(root, { job: job, path: path, command: Fetch.imageArgs(meta.image, path) });
    img.running = true;
  }

  function openUrl(url) {
    if (Url.isHttpUrl(url))
      Quickshell.execDetached(["xdg-open", url]);
  }

  // ---------------------------------------------------------------- notes

  function addNote(text) { commit(Notes.add(data, text, newId(), nowIso())); }
  function updateNote(id, text) { commit(Notes.update(data, id, text, nowIso())); }
  function deleteNote(id) {
    commit(Notes.remove(data, id));
    if (noteWindow.noteId === id)
      noteWindow.closeWindow(false);
  }

  // New notes are created on first non-blank save, so an untouched one leaves nothing behind.
  function openNote(id) { pluginApi?.withCurrentScreen(screen => noteWindow.openOn(screen, id)); }
  function newNote() { pluginApi?.withCurrentScreen(screen => noteWindow.openOn(screen, "")); }

  // Called by the note window: creates the note on first save when it is new.
  function saveNoteText(id, text) {
    if (id === "") {
      if (Notes.isBlank(text))
        return "";
      const newIdValue = newId();
      commit(Notes.add(data, text, newIdValue, nowIso()));
      return newIdValue;
    }
    updateNote(id, text);
    return id;
  }

  NoteWindow {
    id: noteWindow
    pluginApi: root.pluginApi
    mainInstance: root
  }
```
Note: `Notes.add` trims the text; `saveNoteText` for an existing note uses `update` (no trim) so the editor's cursor never jumps.

In `executeCapture`, replace the `addLink` branch:
```qml
    } else if (result.action === "addBookmark") {
      const outcome = addBookmark(p.url);
      done(outcome !== "invalid", outcome === "invalid" ? "invalid-url" : "");
```
In the clipboard `StdioCollector`, replace `Inbox.prefillFromClipboard(text, root.data)` with `Bookmarks.prefillFromClipboard(text, root.data)`.
`NoteWindow.qml` lives next to `Main.qml`, so it resolves without an import; until Task 17 creates it, keep the `NoteWindow { ... }` block commented out and enable it in Task 17.

**Step 4: Run test to verify it passes**
Restart the shell; capture `https://example.com`. Then:
`python3 -c "import json,os;d=json.load(open(os.path.expanduser('~/.local/share/noctalia-daybar/data.json')));print(d['version'],[(b['title'],b['status'],b['image']) for b in d['bookmarks']])"`
Expected: `2 [('Example Domain', 'ok', '')]` within ~10 s (example.com has a `<title>` but no `og:image`). Capturing a page with `og:image` (e.g. `https://github.com`) shows `ok` and an `image` path under `~/.cache/noctalia-daybar/thumbs/`, and that file exists. No `daybar` errors in the log.

**Step 5: Commit**
Run: `/git commit`

---

### Task 16: Bookmarks tab

**Requirement:** REQ-003, REQ-007, REQ-008, REQ-009, REQ-010, REQ-018
**Files:**
- Create: `components/BookmarksView.qml`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails, performance-guardrails)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**
Runtime check: Task 19 wires the tab; before that, temporarily instantiate `BookmarksView { pluginApi: root.pluginApi; mainInstance: root.mainInstance }` in place of `InboxView` in `Panel.qml`.

**Step 2: Run test to verify it fails**
Expected: FAIL — `BookmarksView is not a type`.

**Step 3: Write minimal implementation**

`components/BookmarksView.qml`:
```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import "ui"
import "../utils/bookmarks.js" as Bookmarks
import "../utils/url.js" as Url
import "../utils/dates.js" as Dates

// Bookmarks: browser-like rows (thumbnail, title, description, domain · date),
// search on top, add field at the bottom. Metadata is untrusted: PlainText only.
Card {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property string query: ""
  property string editingId: ""
  property string feedback: ""
  readonly property var all: mainInstance ? Bookmarks.sorted(mainInstance.data.bookmarks) : []
  readonly property var items: Bookmarks.search(all, query)

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  function finishRename(id, text) {
    if (editingId !== id)
      return;
    editingId = "";
    mainInstance.renameBookmark(id, text);
  }

  Timer {
    id: feedbackTimer
    interval: 2500
    onTriggered: root.feedback = ""
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Math.round(12 * Style.uiScaleRatio)
    spacing: Math.round(8 * Style.uiScaleRatio)

    Field {
      Layout.fillWidth: true
      placeholderText: root.tr("bookmarks.search")
      onTextChanged: root.query = text
      Keys.onEscapePressed: text = ""
    }

    NText {
      visible: root.items.length === 0
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.leftMargin: Math.round(6 * Style.uiScaleRatio)
      text: root.all.length === 0 ? root.tr("bookmarks.empty") : root.tr("bookmarks.no-results")
      pointSize: Style.fontSizeS
      color: Qt.alpha(Color.mOnSurface, 0.56)
    }

    NScrollView {
      id: scroll
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: root.items.length > 0
      contentWidth: availableWidth
      horizontalPolicy: ScrollBar.AlwaysOff

      ColumnLayout {
        width: scroll.availableWidth
        spacing: Math.round(2 * Style.uiScaleRatio)

        Repeater {
          model: root.items

          ListRow {
            id: row
            required property var modelData
            readonly property bool editing: root.editingId === modelData.id

            Rectangle {
              Layout.preferredWidth: Math.round(64 * Style.uiScaleRatio)
              Layout.preferredHeight: Math.round(40 * Style.uiScaleRatio)
              radius: Math.round(6 * Style.uiScaleRatio)
              color: Qt.alpha(Color.mOnSurface, 0.06)
              clip: true

              Image {
                id: thumb
                anchors.fill: parent
                visible: status === Image.Ready
                source: row.modelData.image ? "file://" + row.modelData.image : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize.width: 128
              }

              NIcon {
                anchors.centerIn: parent
                visible: thumb.status !== Image.Ready
                icon: row.modelData.status === "pending" ? "loader" : "world"
                pointSize: Style.fontSizeL
                color: Qt.alpha(Color.mOnSurface, 0.42)
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0

              NText {
                visible: !row.editing
                Layout.fillWidth: true
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: row.modelData.title
                pointSize: Style.fontSizeM
                font.weight: Style.fontWeightSemiBold
                color: Color.mOnSurface
              }

              Field {
                id: renameField
                visible: row.editing
                Layout.fillWidth: true
                implicitHeight: Math.round(28 * Style.uiScaleRatio)
                onVisibleChanged: {
                  if (visible) {
                    text = row.modelData.title;
                    selectAll();
                    forceActiveFocus();
                  }
                }
                onAccepted: root.finishRename(row.modelData.id, text)
                Keys.onEscapePressed: root.editingId = ""
                onActiveFocusChanged: if (!activeFocus && visible) root.finishRename(row.modelData.id, text)
              }

              NText {
                visible: row.modelData.description !== ""
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: row.modelData.description
                pointSize: Style.fontSizeS
                color: Qt.alpha(Color.mOnSurface, 0.56)
              }

              NText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: Url.domainOf(row.modelData.url) + "  ·  " + Dates.isoDate(new Date(row.modelData.savedAt))
                pointSize: Style.fontSizeXS
                color: Qt.alpha(Color.mOnSurface, 0.42)
              }
            }

            RowLayout {
              spacing: Math.round(2 * Style.uiScaleRatio)
              opacity: row.hovered || row.activeFocus ? 1 : 0
              enabled: opacity > 0

              PillButton {
                icon: "copy"
                tooltipText: root.tr("bookmarks.copy")
                onClicked: root.mainInstance.copyText(row.modelData.url)
              }
              PillButton {
                icon: "refresh"
                tooltipText: root.tr("bookmarks.refresh")
                busy: row.modelData.status === "pending"
                onClicked: root.mainInstance.refreshBookmark(row.modelData.id)
              }
              PillButton {
                icon: "pencil"
                tooltipText: root.tr("bookmarks.rename")
                onClicked: root.editingId = row.modelData.id
              }
              ConfirmButton {
                icon: "trash"
                tooltipText: root.tr("bookmarks.delete")
                question: root.tr("bookmarks.confirm-delete")
                okText: root.tr("confirm.ok")
                cancelText: root.tr("confirm.cancel")
                onConfirmed: root.mainInstance.deleteBookmark(row.modelData.id)
              }
            }

            // Clicking the row (outside the buttons) opens the link.
            TapHandler {
              enabled: !row.editing
              onTapped: root.mainInstance.openUrl(row.modelData.url)
            }
          }
        }
      }
    }

    Field {
      id: addField
      Layout.fillWidth: true
      placeholderText: root.feedback !== "" ? root.feedback : root.tr("bookmarks.add-placeholder")
      onAccepted: {
        const outcome = root.mainInstance.addBookmark(addField.text);
        if (outcome === "invalid") {
          addField.error = true;
          return;
        }
        addField.error = false;
        addField.text = "";
        root.feedback = root.tr(outcome === "replaced" ? "bookmarks.replaced" : "bookmarks.saved");
        feedbackTimer.restart();
      }
    }
  }
}
```
Check that the icons `loader`, `world`, `pencil`, `copy` exist: `grep -oE '"(loader|world|pencil|copy)":' /etc/xdg/quickshell/noctalia-shell/Commons/IconsTabler.qml`. Replace any missing one with an existing name.
The `TapHandler` must not fire when a hover button is clicked: buttons are `MouseArea`s and accept the press, so the handler does not receive it; verify at runtime.

**Step 4: Run test to verify it passes**
Restart the shell, open the toolbar on the (temporarily wired) bookmarks view: add `https://github.com` in the bottom field; within seconds the row shows a thumbnail, title and description. Hover shows the four buttons; rename (Enter saves, Esc cancels), refresh spins, delete asks with the bubble; clicking the row opens the browser. Typing in search filters; `acao` matches `Ação`. No `daybar` errors in the log.

**Step 5: Commit**
Run: `/git commit`

---

### Task 17: Note window

**Requirement:** REQ-012, REQ-013, REQ-014, REQ-015, REQ-016, REQ-018
**Files:**
- Create: `NoteWindow.qml`
- Modify: `Main.qml` (enable the `NoteWindow { ... }` block from Task 15)

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails, security-guardrails)
- Reviewers: business-logic-reviewer, security-reviewer, test-reviewer

**Step 1: Write the failing test**
Runtime check: enable the `NoteWindow` block in `Main.qml` and restart.

**Step 2: Run test to verify it fails**
Expected: FAIL — `NoteWindow is not a type`.

**Step 3: Write minimal implementation**

`NoteWindow.qml`:
```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Widgets
import "components/ui"
import "utils/notes.js" as Notes
import "utils/markdown.js" as Markdown
import "utils/format.js" as Format

// Large overlay for one note: Markdown preview by default, plain-text editor on
// demand. Saves 600 ms after the last keystroke, on Ctrl+S and on close.
PanelWindow {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property string noteId: ""      // "" = new note not saved yet
  property bool editing: false
  property string text: ""
  readonly property var note: mainInstance && noteId !== "" ? mainInstance.data.notes.find(n => n.id === noteId) || null : null
  readonly property string title: Notes.titleOf(text) || tr("notes.untitled")

  anchors.top: true
  anchors.left: true
  anchors.right: true
  anchors.bottom: true
  visible: false
  color: "transparent"

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  WlrLayershell.namespace: "noctalia-daybar-note"
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  function openOn(targetScreen, id) {
    if (visible)
      save();
    screen = targetScreen;
    noteId = id;
    const n = id !== "" ? mainInstance.data.notes.find(x => x.id === id) : null;
    text = n ? n.text : "";
    editing = id === "";
    visible = true;
    if (editing)
      Qt.callLater(focusEditor);
  }

  function focusEditor() {
    editor.text = root.text;
    editor.forceActiveFocus();
    editor.cursorPosition = editor.text.length;
  }

  function save() {
    saveTimer.stop();
    noteId = mainInstance.saveNoteText(noteId, text);
  }

  // save=false when the note was just deleted.
  function closeWindow(saveFirst) {
    if (saveFirst !== false)
      save();
    visible = false;
    editing = false;
    noteId = "";
    text = "";
  }

  function toggleEdit() {
    if (editing) {
      save();
      editing = false;
    } else {
      editing = true;
      Qt.callLater(focusEditor);
    }
  }

  function edited() {
    if (!note)
      return "";
    const r = Format.relativeTime(note.updatedAt, new Date());
    const when = r.unit === "date" ? r.date : tr("time." + r.unit).replace("{n}", r.n);
    return tr("notes.edited").replace("{time}", when);
  }

  Timer {
    id: saveTimer
    interval: 600
    onTriggered: root.save()
  }

  Shortcut {
    sequence: "Ctrl+E"
    enabled: root.visible
    onActivated: root.toggleEdit()
  }
  Shortcut {
    sequence: "Ctrl+S"
    enabled: root.visible
    onActivated: root.save()
  }
  Shortcut {
    sequence: "Escape"
    enabled: root.visible
    onActivated: root.closeWindow()
  }

  // Dimmed backdrop; a click outside the card closes (saving).
  MouseArea {
    anchors.fill: parent
    onClicked: root.closeWindow()

    Rectangle {
      anchors.fill: parent
      color: Qt.alpha(Color.mShadow, 0.35)
    }
  }

  Rectangle {
    width: Math.min(1100 * Style.uiScaleRatio, parent.width * 0.9)
    height: Math.min(800 * Style.uiScaleRatio, parent.height * 0.9)
    anchors.centerIn: parent
    radius: Style.radiusL
    color: Color.mSurface
    border.color: Qt.alpha(Color.mOnSurface, 0.08)
    border.width: Style.borderS

    MouseArea {
      anchors.fill: parent
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Math.round(18 * Style.uiScaleRatio)
      spacing: Math.round(12 * Style.uiScaleRatio)

      RowLayout {
        Layout.fillWidth: true
        spacing: Math.round(6 * Style.uiScaleRatio)

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          NText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.title
            pointSize: Style.fontSizeXL
            font.weight: Style.fontWeightSemiBold
            color: Color.mOnSurface
          }

          NText {
            visible: root.note !== null
            text: root.edited()
            pointSize: Style.fontSizeXS
            color: Qt.alpha(Color.mOnSurface, 0.42)
          }
        }

        PillButton {
          icon: root.editing ? "eye" : "pencil"
          tooltipText: root.editing ? root.tr("notes.preview") : root.tr("notes.edit")
          onClicked: root.toggleEdit()
        }
        PillButton {
          icon: "copy"
          tooltipText: root.tr("notes.copy")
          onClicked: root.mainInstance.copyText(root.text)
        }
        ConfirmButton {
          visible: root.noteId !== ""
          icon: "trash"
          tooltipText: root.tr("notes.delete")
          question: root.tr("notes.confirm-delete")
          okText: root.tr("confirm.ok")
          cancelText: root.tr("confirm.cancel")
          onConfirmed: root.mainInstance.deleteNote(root.noteId)
        }
        PillButton {
          icon: "x"
          tooltipText: root.tr("notes.close")
          onClicked: root.closeWindow()
        }
      }

      NScrollView {
        id: previewScroll
        visible: !root.editing
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: availableWidth
        horizontalPolicy: ScrollBar.AlwaysOff

        NText {
          width: previewScroll.availableWidth
          wrapMode: Text.Wrap
          markdownTextEnabled: true
          text: Markdown.prepare(root.text)
          pointSize: Style.fontSizeM
          color: Color.mOnSurface
          linkColor: Color.mPrimary
          onLinkActivated: link => {
            if (Markdown.isOpenableLink(link))
              Quickshell.execDetached(["xdg-open", link]);
          }

          TapHandler {
            onDoubleTapped: root.toggleEdit()
          }
        }
      }

      ScrollView {
        visible: root.editing
        Layout.fillWidth: true
        Layout.fillHeight: true

        TextArea {
          id: editor
          wrapMode: TextArea.Wrap
          font.family: Settings.data.ui.fontFixed
          font.pointSize: Style.fontSizeM * Style.uiScaleRatio
          color: Color.mOnSurface
          placeholderText: root.tr("notes.placeholder")
          placeholderTextColor: Qt.alpha(Color.mOnSurface, 0.42)
          selectionColor: Qt.alpha(Color.mPrimary, 0.4)
          background: Rectangle {
            radius: Math.round(12 * Style.uiScaleRatio)
            color: Qt.alpha(Color.mOnSurface, 0.05)
          }
          onTextChanged: {
            if (!root.editing || text === root.text)
              return;
            root.text = text;
            saveTimer.restart();
          }
        }
      }

      NText {
        text: root.tr("notes.keys")
        pointSize: Style.fontSizeXS
        color: Qt.alpha(Color.mOnSurface, 0.42)
      }
    }
  }
}
```
Check the icons `eye`, `pencil`, `x` exist (same grep as Task 16). If `NText` does not expose `linkColor`, drop that line (Text has it; NText extends Text). If the `Shortcut` for Escape is swallowed by the `TextArea`, add `Keys.onEscapePressed: root.closeWindow()` to `editor`.

**Step 4: Run test to verify it passes**
Restart the shell. From the QML console of a temporary button or Task 18's list: `mainInstance.newNote()` opens the window in edit mode; typing `# Title` then waiting 1 s writes a note to `data.json`; Ctrl+E shows the rendered heading; `![x](https://example.com/a.png)` renders as a link (no network request: `ss -tnp | grep qs` shows no new connection); clicking a `javascript:` link does nothing; Esc closes; a new note closed while empty leaves `data.json` unchanged. No `daybar` errors in the log.

**Step 5: Commit**
Run: `/git commit`

---

### Task 18: Notes tab

**Requirement:** REQ-011, REQ-015, REQ-018
**Files:**
- Create: `components/NotesView.qml`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**
Runtime check: temporarily instantiate `NotesView { pluginApi: root.pluginApi; mainInstance: root.mainInstance }` in `Panel.qml`'s `StackLayout`.

**Step 2: Run test to verify it fails**
Expected: FAIL — `NotesView is not a type`.

**Step 3: Write minimal implementation**

`components/NotesView.qml`:
```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import "ui"
import "../utils/notes.js" as Notes
import "../utils/format.js" as Format

// Notes list: derived title, one-line snippet, relative edit time; search and
// "New note" on top. A click opens the note window.
Card {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property string query: ""
  property date now: new Date()
  readonly property var all: mainInstance ? Notes.sorted(mainInstance.data.notes) : []
  readonly property var items: Notes.search(all, query)

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  function when(iso) {
    const r = Format.relativeTime(iso, now);
    return r.unit === "date" ? r.date : tr("time." + r.unit).replace("{n}", r.n);
  }

  Timer {
    interval: 60000
    repeat: true
    running: root.visible
    onTriggered: root.now = new Date()
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Math.round(12 * Style.uiScaleRatio)
    spacing: Math.round(8 * Style.uiScaleRatio)

    RowLayout {
      Layout.fillWidth: true
      spacing: Math.round(8 * Style.uiScaleRatio)

      Field {
        Layout.fillWidth: true
        placeholderText: root.tr("notes.search")
        onTextChanged: root.query = text
        Keys.onEscapePressed: text = ""
      }

      PillButton {
        primary: true
        implicitHeight: Math.round(34 * Style.uiScaleRatio)
        icon: "plus"
        text: root.tr("notes.new")
        onClicked: root.mainInstance.newNote()
      }
    }

    NText {
      visible: root.items.length === 0
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.leftMargin: Math.round(6 * Style.uiScaleRatio)
      text: root.all.length === 0 ? root.tr("notes.empty") : root.tr("notes.no-results")
      pointSize: Style.fontSizeS
      color: Qt.alpha(Color.mOnSurface, 0.56)
    }

    NScrollView {
      id: scroll
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: root.items.length > 0
      contentWidth: availableWidth
      horizontalPolicy: ScrollBar.AlwaysOff

      ColumnLayout {
        width: scroll.availableWidth
        spacing: Math.round(2 * Style.uiScaleRatio)

        Repeater {
          model: root.items

          ListRow {
            id: row
            required property var modelData
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: Notes.titleOf(modelData.text) || root.tr("notes.untitled")
            Keys.onReturnPressed: root.mainInstance.openNote(modelData.id)

            NIcon {
              icon: "note"
              pointSize: Style.fontSizeM
              color: Qt.alpha(Color.mOnSurface, 0.56)
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0

              NText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: Notes.titleOf(row.modelData.text) || root.tr("notes.untitled")
                pointSize: Style.fontSizeM
                font.weight: Style.fontWeightSemiBold
                color: Color.mOnSurface
              }

              NText {
                visible: text !== ""
                Layout.fillWidth: true
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: Notes.snippetOf(row.modelData.text)
                pointSize: Style.fontSizeS
                color: Qt.alpha(Color.mOnSurface, 0.56)
              }
            }

            NText {
              text: root.when(row.modelData.updatedAt)
              pointSize: Style.fontSizeXS
              color: Qt.alpha(Color.mOnSurface, 0.42)
            }

            RowLayout {
              spacing: Math.round(2 * Style.uiScaleRatio)
              opacity: row.hovered || row.activeFocus ? 1 : 0
              enabled: opacity > 0

              PillButton {
                icon: "copy"
                tooltipText: root.tr("notes.copy")
                onClicked: root.mainInstance.copyText(row.modelData.text)
              }
              ConfirmButton {
                icon: "trash"
                tooltipText: root.tr("notes.delete")
                question: root.tr("notes.confirm-delete")
                okText: root.tr("confirm.ok")
                cancelText: root.tr("confirm.cancel")
                onConfirmed: root.mainInstance.deleteNote(row.modelData.id)
              }
            }

            TapHandler {
              onTapped: root.mainInstance.openNote(row.modelData.id)
            }
          }
        }
      }
    }
  }
}
```
Check the `plus` icon exists; replace if missing.

**Step 4: Run test to verify it passes**
Restart the shell; the Notes view lists notes newest-edited first with title, snippet and "há N min"; "Nova nota" opens the window; a click opens the note; search filters; hover copy/delete work (delete asks with the bubble). No `daybar` errors in the log.

**Step 5: Commit**
Run: `/git commit`

---

### Task 19: Panel wiring and Inbox removal

**Requirement:** REQ-001
**Files:**
- Modify: `Panel.qml`
- Delete: `components/InboxView.qml`
- Modify: `i18n/pt.json`, `i18n/en.json` (remove the `inbox` section)

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: architecture-guardrails)
- Reviewers: consequences-reviewer, test-reviewer

**Step 1: Write the failing test**
Run: `grep -rn "inbox" --include=*.qml --include=*.js --include=*.json . | grep -v node_modules | grep -v "^./docs"`
Expected: FAIL (matches in `Panel.qml`, `components/InboxView.qml`, i18n).

**Step 2: Run test to verify it fails**
Same command; at least one match.

**Step 3: Write minimal implementation**
- `Panel.qml`: in the `StackLayout`, replace `InboxView { ... }` with
```qml
        BookmarksView {
          pluginApi: root.pluginApi
          mainInstance: root.mainInstance
        }

        NotesView {
          pluginApi: root.pluginApi
          mainInstance: root.mainInstance
        }
```
  (order must follow `Tabs.TABS`: calendar, today, focus, bookmarks, notes) and remove any temporary instances added in Tasks 16 and 18.
- Delete `components/InboxView.qml`.
- Remove the `inbox` section from both i18n catalogs.

**Step 4: Run test to verify it passes**
Run the Step 1 grep (expect no output), then `npm test` (expect PASS), then restart the shell and click through all five tabs: icons calendar, list-check, hourglass, bookmark, notes; the active tab shows its label; the bar icon follows the last tab. No `daybar` errors in the log.

**Step 5: Commit**
Run: `/git commit`

---

### Task 20: Docs, smoke rows and final verification

**Requirement:** all (verification)
**Files:**
- Modify: `README.md` (Capture table: Link row → "bookmark with page preview"; new "Bookmarks" and "Notes" sections; data file mentions `bookmarks`, thumbnails in `~/.cache/noctalia-daybar/thumbs/`)
- Modify: `docs/SMOKE.md` (rows below)
- Modify: `docs/specs/daybar-mvp/SPEC.md` (REQ-020 and REQ-024 superseded by this spec)
- Modify: `docs/specs/inbox-bookmarks-notes/SPEC.md` (Traceability → Done), `docs/specs/inbox-bookmarks-notes/STATE.md` (`phase: implement-complete`)

**Team:**
- Track: infra
- Implementer: infra-engineer (skills: technical-writer)
- Reviewers: consequences-reviewer

**Step 1: Write the failing test**
Run: `for i in $(seq -w 1 19); do grep -q "BN-REQ-0$i" docs/SMOKE.md || echo "missing BN-REQ-0$i"; done`
Expected: FAIL (all missing).

**Step 2: Run test to verify it fails**
Same loop; 19 lines of output.

**Step 3: Write minimal implementation**
Append to `docs/SMOKE.md` a "Bookmarks and Notes" table, one row per requirement, IDs prefixed `BN-` to keep them apart from the MVP rows:

| # | REQ | Step | Expected |
|---|-----|------|----------|
| 27 | BN-REQ-001 | Open the toolbar | Five tabs; Bookmarks and Notes after Focus |
| 28 | BN-REQ-002 | Start with a v1 `data.json` holding links/notes | `version: 2`, no links/notes |
| 29 | BN-REQ-003 | Capture `https://github.com` | Row appears at once with `github.com` |
| 30 | BN-REQ-004 | Capture `https://github.com/?utm_source=x` | Same row moves to top, refetched |
| 31 | BN-REQ-005 | Wait a few seconds | Title and description from the page |
| 32 | BN-REQ-006 | `ls ~/.cache/noctalia-daybar/thumbs/` | File named after the bookmark id |
| 33 | BN-REQ-007 | Capture `https://nonexistent.invalid` | Domain title, no toast, refresh on hover |
| 34 | BN-REQ-008 | Look at a row; click it | Thumbnail, title, 2-line description, domain · date; browser opens |
| 35 | BN-REQ-009 | Hover: copy, refresh, rename | Clipboard has URL; spinner; Enter saves title |
| 36 | BN-REQ-010 | Search `acao` with a title "Ação" | Row stays; others hidden |
| 37 | BN-REQ-011 | Open Notes | Title, snippet, "há N min", newest edit first |
| 38 | BN-REQ-012 | Click a note | Large centered window, rendered Markdown |
| 39 | BN-REQ-013 | Ctrl+E twice; double-click text | Editor (monospace) then preview; double-click edits |
| 40 | BN-REQ-014 | Type, wait 1 s, `cat data.json` | Text saved; Ctrl+S saves at once; Esc closes |
| 41 | BN-REQ-015 | New note, close without typing | No new note in data.json |
| 42 | BN-REQ-016 | Note with `![x](https://example.com/a.png)` and `[js](javascript:alert(1))` | Image shown as a link; js link does nothing |
| 43 | BN-REQ-017 | Capture `/n uma ideia` | Note "uma ideia" in Notes |
| 44 | BN-REQ-018 | Delete a note and a bookmark | Bubble with OK/Cancel; Esc cancels; OK deletes and removes the thumbnail |
| 45 | BN-REQ-019 | Turn "Fetch link previews" off, capture a link | Domain title only; no curl process |

**Step 4: Run test to verify it passes**
Run the Step 1 loop (no output). Then `npm test > /tmp/daybar-test.log 2>&1; echo "EXIT=$?"; grep -E "Tests +[0-9]+ passed" /tmp/daybar-test.log` (EXIT=0), and the source-reference guard from the MVP plan (expect `clean`). Then walk SMOKE rows 27-45 with the shell running; record any failing row in STATE.md instead of marking its REQ done.

**Step 5: Commit**
Run: `/git commit`
