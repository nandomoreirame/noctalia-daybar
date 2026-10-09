.pragma library

// Note capture: free text kept verbatim in the Inbox.
var TYPE = "note";

function build(text) {
  const body = String(text || "").trim();
  if (!body) return { ok: false, type: TYPE, error: "empty" };
  return { ok: true, type: TYPE, action: "addNote", payload: { text: body } };
}
