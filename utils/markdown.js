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
