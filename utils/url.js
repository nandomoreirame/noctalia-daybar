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
