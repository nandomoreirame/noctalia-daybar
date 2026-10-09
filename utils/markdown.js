.pragma library
.import "url.js" as Url

// Pre-pass before Qt's native Markdown renderer: a note never loads anything
// from the network by itself. Every image whose source is not local (inline,
// reference-style or raw <img>) becomes a link or is dropped. Links are opened
// by the UI only when isOpenableLink().

// Local = file:// URL, data: URI, or a path with no scheme and no "//" host.
function isLocalSource(src) {
  const s = String(src || "").trim();
  if (/^file:\/\//i.test(s) || /^data:/i.test(s)) return true;
  return !/^[a-z][a-z0-9+.-]*:/i.test(s) && s.indexOf("//") !== 0;
}

// [label]: destination  (CommonMark link reference definitions)
function referenceDefinitions(text) {
  const defs = {};
  const re = /^ {0,3}\[([^\]]+)\]:\s*<?([^\s>]+)>?/gm;
  let m;
  while ((m = re.exec(text)) !== null) defs[m[1].trim().toLowerCase()] = m[2];
  return defs;
}

function prepare(text) {
  const source = String(text || "");
  const defs = referenceDefinitions(source);
  const remoteRef = (label) => {
    const url = defs[String(label).trim().toLowerCase()];
    return url !== undefined && !isLocalSource(url);
  };
  return source
    // inline: ![alt](dest "t") / ('t') / ((t)) / (<dest>)
    .replace(/!\[([^\]]*)\]\(\s*<?([^\s)>]+)>?(?:\s+(?:"[^"]*"|'[^']*'|\([^)]*\)))?\s*\)/g,
      (whole, alt, src) => isLocalSource(src) ? whole : "[" + (alt || src) + "](" + src + ")")
    // reference: ![alt][ref] and collapsed ![ref][]
    .replace(/!\[([^\]]*)\]\[([^\]]*)\]/g,
      (whole, alt, ref) => remoteRef(ref || alt) ? whole.slice(1) : whole)
    // shortcut: ![ref] not followed by ( or [
    .replace(/!\[([^\]]+)\](?![(\[])/g,
      (whole, label) => remoteRef(label) ? whole.slice(1) : whole)
    // raw HTML images unless clearly local
    .replace(/<img\b[^>]*>/gi, (tag) => {
      const m = /\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i.exec(tag);
      const src = m ? (m[1] !== undefined ? m[1] : (m[2] !== undefined ? m[2] : m[3])) : "";
      return src && isLocalSource(src) ? tag : "";
    });
}

function isOpenableLink(url) {
  const s = String(url || "").trim();
  return Url.isHttpUrl(s) || /^mailto:[^\s@]+@[^\s@]+$/i.test(s);
}
