.pragma library

// Inbox (links and notes) operations plus clipboard prefill. Pure; returns new data.

function isHttpUrl(text) {
  const s = String(text || "").trim();
  return /^https?:\/\/[^\s/$.?#][^\s]*$/i.test(s);
}

function hasLink(data, url) {
  return data.links.some((l) => l.url === url);
}

function addLink(data, url, id, nowIso) {
  const clean = String(url).trim();
  if (hasLink(data, clean)) return data;
  const link = { id: id, url: clean, archived: false, createdAt: nowIso };
  return Object.assign({}, data, { links: data.links.concat([link]) });
}

function archiveLink(data, id) {
  return Object.assign({}, data, { links: data.links.map((l) => l.id !== id ? l : Object.assign({}, l, { archived: true })) });
}

function addNote(data, text, id, nowIso) {
  const note = { id: id, text: String(text).trim(), createdAt: nowIso };
  return Object.assign({}, data, { notes: data.notes.concat([note]) });
}

function deleteNote(data, id) {
  return Object.assign({}, data, { notes: data.notes.filter((n) => n.id !== id) });
}

// Clipboard text to prefill the capture field with: a new http(s) URL, else "".
function prefillFromClipboard(clip, data) {
  const s = String(clip || "").trim();
  return isHttpUrl(s) && !hasLink(data, s) ? s : "";
}
