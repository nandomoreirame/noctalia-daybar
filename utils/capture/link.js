.pragma library
.import "../inbox.js" as Inbox

// Link capture: read-later http(s) URL in the Inbox.
var TYPE = "link";

function isLink(text) {
  return Inbox.isHttpUrl(text);
}

function build(text) {
  const url = String(text || "").trim();
  if (!Inbox.isHttpUrl(url)) return { ok: false, type: TYPE, error: "invalid-url" };
  return { ok: true, type: TYPE, action: "addLink", payload: { url: url } };
}
