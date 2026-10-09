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
