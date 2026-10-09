.pragma library
.import "text.js" as Text

// Markdown notes. The title is derived from the first non-empty line.
// note: { id, text, createdAt, updatedAt }

var SNIPPET_MAX = 140;

// Markdown markup removed for list display (not a renderer).
function stripMarkup(line) {
  return String(line)
    .replace(/^\s{0,3}(#{1,6}\s+|>\s*|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+)/, "")
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/(\*\*|__|~~|`|\*|_)/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function lines(text) {
  return String(text || "").split(/\r?\n/);
}

function titleIndex(text) {
  const all = lines(text);
  for (let i = 0; i < all.length; i++) if (all[i].trim() !== "") return i;
  return -1;
}

function titleOf(text) {
  const i = titleIndex(text);
  return i < 0 ? "" : stripMarkup(lines(text)[i]);
}

function snippetOf(text) {
  const i = titleIndex(text);
  if (i < 0) return "";
  const rest = lines(text).slice(i + 1).map(stripMarkup).filter((l) => l !== "").join(" ");
  return rest.length > SNIPPET_MAX ? rest.slice(0, SNIPPET_MAX) : rest;
}

function isBlank(text) {
  return String(text || "").trim() === "";
}

function add(data, text, id, nowIso) {
  const note = { id: id, text: String(text || "").trim(), createdAt: nowIso, updatedAt: nowIso };
  return Object.assign({}, data, { notes: data.notes.concat([note]) });
}

function update(data, id, text, nowIso) {
  const target = data.notes.find((n) => n.id === id);
  if (!target || target.text === text) return data;
  return Object.assign({}, data, { notes: data.notes.map((n) => n.id !== id ? n : Object.assign({}, n, { text: text, updatedAt: nowIso })) });
}

function remove(data, id) {
  return Object.assign({}, data, { notes: data.notes.filter((n) => n.id !== id) });
}

function sorted(list) {
  return list.slice().sort((a, b) => (a.updatedAt < b.updatedAt ? 1 : a.updatedAt > b.updatedAt ? -1 : 0));
}

function search(list, query) {
  return list.filter((n) => Text.matches([n.text], query));
}
