.pragma library
.import "url.js" as Url

// Pre-pass before Qt's native Markdown renderer: a note never loads anything
// from the network by itself. Every image whose source is not local (inline,
// reference-style or raw <img>) becomes a link or is dropped. Links are opened
// by the UI only when isOpenableLink().

// Decode a few HTML entities that can hide a scheme in <img src> values.
// Numeric forms are accepted with or without a trailing semicolon (HTML parsers
// accept both).
function decodeEntities(src) {
  return String(src || "")
    .replace(/&#x([0-9a-f]+);?/gi, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/&#([0-9]+);?/g, (_, d) => String.fromCharCode(parseInt(d, 10)))
    .replace(/&colon;/gi, ":")
    .replace(/&sol;/gi, "/")
    .replace(/&amp;/gi, "&");
}

// Strip ASCII whitespace and controls so " http://" / "\x00http://" cannot
// sneak past the local-source checks.
function scrubSrc(src) {
  return String(src || "").replace(/[\x00-\x20]+/g, "");
}

// Local = file:// URL, data: URI, or a path with no scheme and no "//" host.
// Used for Markdown image syntax (![…](…)).
function isLocalSource(src) {
  const s = String(src || "").trim();
  if (/^file:\/\//i.test(s) || /^data:/i.test(s)) return true;
  return !/^[a-z][a-z0-9+.-]*:/i.test(s) && s.indexOf("//") !== 0;
}

// Strict local check for raw <img> tags only: file://, data:image/, or an
// absolute path starting with a single "/".
function isStrictLocalImgSrc(src) {
  const s = scrubSrc(decodeEntities(src));
  if (/^file:\/\//i.test(s)) return true;
  if (/^data:image\//i.test(s)) return true;
  return s.charAt(0) === "/" && s.charAt(1) !== "/";
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
    // inline: ![alt](dest) with one level of nested brackets in alt, and
    // <dest with spaces> or bare dest; optional title in " " / ' ' / ( ).
    .replace(/!\[((?:[^\[\]]|\[[^\[\]]*\])*)\]\(\s*(?:<([^>]+)>|([^\s)>]+))(?:\s+(?:"[^"]*"|'[^']*'|\([^)]*\)))?\s*\)/g,
      (whole, alt, angle, bare) => {
        const src = angle !== undefined ? angle : bare;
        return isLocalSource(src) ? whole : "[" + (alt || src) + "](" + src + ")";
      })
    // reference: ![alt][ref] and collapsed ![ref][]
    .replace(/!\[((?:[^\[\]]|\[[^\[\]]*\])*)\]\[([^\]]*)\]/g,
      (whole, alt, ref) => remoteRef(ref || alt) ? whole.slice(1) : whole)
    // shortcut: ![ref] not followed by ( or [
    .replace(/!\[([^\]]+)\](?![(\[])/g,
      (whole, label) => remoteRef(label) ? whole.slice(1) : whole)
    // raw HTML images: strict local only (entities + controls scrubbed first)
    .replace(/<img\b[^>]*>/gi, (tag) => {
      const m = /\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i.exec(tag);
      const raw = m ? (m[1] !== undefined ? m[1] : (m[2] !== undefined ? m[2] : m[3])) : "";
      return raw && isStrictLocalImgSrc(raw) ? tag : "";
    });
}

function isOpenableLink(url) {
  const s = String(url || "").trim();
  return Url.isHttpUrl(s) || /^mailto:[^\s@]+@[^\s@]+$/i.test(s);
}
