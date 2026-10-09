.pragma library

// Search helpers. String.prototype.normalize is not guaranteed in the QML JS
// engine, so accents are folded with an explicit table.

var FOLD = [
  [/[áàâãäå]/g, "a"], [/[éèêë]/g, "e"], [/[íìîï]/g, "i"], [/[óòôõö]/g, "o"],
  [/[úùûü]/g, "u"], [/ç/g, "c"], [/ñ/g, "n"]
];

function fold(value) {
  let s = String(value === null || value === undefined ? "" : value).toLowerCase();
  for (const [re, plain] of FOLD) s = s.replace(re, plain);
  return s;
}

// True when every whitespace-separated word of `query` appears in some field.
function matches(fields, query) {
  const words = fold(query).split(/\s+/).filter((w) => w.length > 0);
  if (words.length === 0) return true;
  const haystack = fields.map(fold).join("\n");
  return words.every((w) => haystack.indexOf(w) >= 0);
}
