.pragma library

// argv builders for preview fetching. Always arrays (Process.command), URL last
// after "--", http/https only, bounded in time, size and redirects.

var UA = "Mozilla/5.0 (X11; Linux x86_64) Daybar/0.2";
// --fail: an HTTP 4xx/5xx exits 22 with no body, so error pages never become previews.
var LIMITS = ["--fail", "--proto", "=http,https", "--proto-redir", "=http,https", "--max-time", "8", "--max-filesize", "2000000", "--max-redirs", "5"];
// curl -w writes the URL it ended at (after -L redirects) after this marker.
var URL_MARKER = "\u0001daybar-url:";

function pageArgs(url) {
  return ["curl", "-sSL"].concat(LIMITS, ["-A", UA, "-H", "Accept-Language: pt-BR,pt;q=0.9,en;q=0.8", "-w", "\n" + URL_MARKER + "%{url_effective}", "--", url]);
}

// Splits curl stdout into the page HTML and the final URL (falls back to the
// requested one when the marker is missing or the final URL is not http(s)).
function splitPageOutput(stdout, requestedUrl) {
  const s = String(stdout || "");
  const i = s.lastIndexOf("\n" + URL_MARKER);
  if (i < 0) return { html: s, finalUrl: requestedUrl };
  const finalUrl = s.slice(i + 1 + URL_MARKER.length).trim();
  return { html: s.slice(0, i), finalUrl: /^https?:\/\//i.test(finalUrl) ? finalUrl : requestedUrl };
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
