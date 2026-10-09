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

// Canonical dotted-decimal only: four octets 0-255, no leading zeros.
function ipv4Octets(host) {
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
  if (!m) return null;
  const raw = [m[1], m[2], m[3], m[4]];
  if (raw.some((o) => o.length > 1 && o.charAt(0) === "0")) return null;
  const parts = raw.map((o) => parseInt(o, 10));
  return parts.every((n) => n <= 255) ? parts : null;
}

function isPrivateIpv4(ip) {
  if (ip[0] === 127 || ip[0] === 0) return true;
  if (ip[0] === 10) return true;
  if (ip[0] === 192 && ip[1] === 168) return true;
  if (ip[0] === 169 && ip[1] === 254) return true;
  if (ip[0] === 172 && ip[1] >= 16 && ip[1] <= 31) return true;
  // CGNAT / Tailscale
  if (ip[0] === 100 && ip[1] >= 64 && ip[1] <= 127) return true;
  // Benchmarking
  if (ip[0] === 198 && (ip[1] === 18 || ip[1] === 19)) return true;
  // Multicast and reserved (224.0.0.0/4 and above), including broadcast
  if (ip[0] >= 224) return true;
  return false;
}

// Expand ::ffff:XXXX:XXXX into four IPv4 octets, or null when not that form.
function ipv4MappedFromHex(a, b) {
  const hi = parseInt(a, 16);
  const lo = parseInt(b, 16);
  if (isNaN(hi) || isNaN(lo) || a.length > 4 || b.length > 4) return null;
  return [(hi >> 8) & 255, hi & 255, (lo >> 8) & 255, lo & 255];
}

// True when an IPv6 literal is loopback, unspecified, or IPv4-mapped private.
function isPrivateOrLocalIpv6(bare) {
  if (bare === "::" || bare === "::1") return true;
  // Fully written loopback (and any zero-padded equivalent of ::1).
  if (/^(0+:){7}1$/.test(bare)) return true;
  // IPv4-mapped: ::ffff:a.b.c.d
  const dotted = /^::ffff:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/i.exec(bare);
  if (dotted) {
    const ip = ipv4Octets(dotted[1]);
    return !ip || isPrivateIpv4(ip);
  }
  // IPv4-mapped: ::ffff:XXXX:XXXX
  const hex = /^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$/i.exec(bare);
  if (hex) {
    const ip = ipv4MappedFromHex(hex[1], hex[2]);
    return !ip || isPrivateIpv4(ip);
  }
  if (/^f[cd][0-9a-f]{2}:/i.test(bare)) return true;
  if (/^fe[89ab][0-9a-f]:/i.test(bare)) return true;
  return false;
}

function isPrivateOrLocalHost(host) {
  let h = String(host || "").toLowerCase();
  if (!h) return true;
  // Trailing dots are DNS root markers; strip before every check.
  while (h.length > 0 && h.charAt(h.length - 1) === ".") h = h.slice(0, -1);
  if (!h) return true;
  if (h === "localhost" || h.endsWith(".localhost")) return true;
  if (h.indexOf(":") >= 0 || (h.charAt(0) === "[" && h.charAt(h.length - 1) === "]")) {
    const bare = h.charAt(0) === "[" ? h.slice(1, -1) : h;
    return isPrivateOrLocalIpv6(bare);
  }
  const ip = ipv4Octets(h);
  if (ip) return isPrivateIpv4(ip);
  // Every label numeric (decimal, octal or 0x-hex) but not canonical IPv4:
  // curl still accepts it as an address (127.1, 0x7f.0.0.1, 0177.0.0.1,
  // 2130706433). Real domains such as "cafe.de" have non-numeric labels.
  if (h.split(".").every((label) => /^(0x[0-9a-f]*|[0-9]+)$/i.test(label))) return true;
  // Bare hostnames without a dot are local/LAN services.
  return h.indexOf(".") < 0;
}

// True for http(s) URLs whose host is publicly routable. Used to refuse
// downloading untrusted og:image URLs that point at private/link-local hosts.
function isPublicHttpUrl(url) {
  const s = String(url || "").trim();
  if (!isHttpUrl(s)) return false;
  const m = /^https?:\/\/(\[[^\]]+\]|[^/?#:]+)/i.exec(s);
  if (!m) return false;
  return !isPrivateOrLocalHost(m[1]);
}
