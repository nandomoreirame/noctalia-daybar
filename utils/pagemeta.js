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
