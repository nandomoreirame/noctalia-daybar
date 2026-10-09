.pragma library
.import "url.js" as Url
.import "text.js" as Text

// Bookmark operations. Pure; every function returns a NEW data object (or the
// same one when nothing changes). `token` increases on every (re)save so results
// from a superseded fetch are ignored.
// bookmark: { id, url, title, description, image, imageUrl, status, token,
//             createdAt, savedAt, customTitle? }
// status: "pending" (fetch queued/running), "ok", "failed", "off" (fetching disabled)

function findByUrl(data, url) {
  const key = Url.normalizeUrl(url);
  return key ? data.bookmarks.find((b) => Url.normalizeUrl(b.url) === key) || null : null;
}

function hasUrl(data, url) {
  return findByUrl(data, url) !== null;
}

// Returns { data, bookmark, replaced } or null for an invalid URL.
function add(data, rawUrl, id, nowIso, fetchEnabled) {
  const url = String(rawUrl || "").trim();
  if (!Url.isHttpUrl(url)) return null;
  const existing = findByUrl(data, url);
  const bookmark = {
    id: existing ? existing.id : id,
    url: url,
    title: Url.domainOf(url),
    description: "",
    image: "",
    imageUrl: "",
    status: fetchEnabled ? "pending" : "off",
    token: existing ? existing.token + 1 : 1,
    createdAt: existing ? existing.createdAt : nowIso,
    savedAt: nowIso
  };
  const rest = data.bookmarks.filter((b) => b.id !== bookmark.id);
  return { data: Object.assign({}, data, { bookmarks: [bookmark].concat(rest) }), bookmark: bookmark, replaced: !!existing };
}

function update(data, id, token, patch) {
  const target = data.bookmarks.find((b) => b.id === id);
  if (!target || (token !== null && target.token !== token)) return data;
  return Object.assign({}, data, { bookmarks: data.bookmarks.map((b) => b.id !== id ? b : Object.assign({}, b, patch(b))) });
}

function applyPreview(data, id, token, meta) {
  return update(data, id, token, (b) => {
    const patch = {
      description: meta.description || "",
      imageUrl: meta.image || "",
      status: "ok"
    };
    if (!b.customTitle)
      patch.title = meta.title || Url.domainOf(b.url);
    return patch;
  });
}

function setImage(data, id, token, path) {
  return update(data, id, token, () => ({ image: path }));
}

function markFailed(data, id, token) {
  return update(data, id, token, () => ({ status: "failed" }));
}

// A queued fetch dropped because fetching was turned off.
function markOff(data, id, token) {
  return update(data, id, token, () => ({ status: "off" }));
}

// True while a fetch job still belongs to a live bookmark (not deleted or re-saved).
function isCurrent(data, id, token) {
  return data.bookmarks.some((b) => b.id === id && b.token === token);
}

// Refresh bumps the token and requeues a fetch without clearing title /
// description / image and without moving the bookmark to the top.
function refresh(data, id, nowIso, fetchEnabled) {
  const target = data.bookmarks.find((b) => b.id === id);
  if (!target) return null;
  if (!fetchEnabled) {
    return { data: data, bookmark: target };
  }
  const bookmark = Object.assign({}, target, {
    status: "pending",
    token: target.token + 1
  });
  return {
    data: Object.assign({}, data, {
      bookmarks: data.bookmarks.map((b) => b.id === id ? bookmark : b)
    }),
    bookmark: bookmark
  };
}

function rename(data, id, title) {
  const clean = String(title || "").replace(/\s+/g, " ").trim();
  if (!clean) return data;
  return update(data, id, null, () => ({ title: clean, customTitle: true }));
}

function remove(data, id) {
  return Object.assign({}, data, { bookmarks: data.bookmarks.filter((b) => b.id !== id) });
}

function sorted(list) {
  return list.slice().sort((a, b) => (a.savedAt < b.savedAt ? 1 : a.savedAt > b.savedAt ? -1 : 0));
}

function search(list, query) {
  return list.filter((b) => Text.matches([b.title, b.description, b.url], query));
}

// Clipboard text to prefill the capture field with: a new http(s) URL, else "".
function prefillFromClipboard(clip, data) {
  const s = String(clip || "").trim();
  return Url.isHttpUrl(s) && !hasUrl(data, s) ? s : "";
}
