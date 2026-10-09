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
