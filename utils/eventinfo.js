.pragma library

// Details that Noctalia's CalendarService does not pass on, read from the event's
// .ics file: who is in it, the Meet link and the location.
// -> { people: [{ name, email, status }], meetUrl, location }

// RFC 5545 folding: a line break followed by a space or tab continues the line.
function unfold(text) {
  return String(text || "").replace(/\r?\n[ \t]/g, "");
}

function unescapeText(value) {
  return value.replace(/\\n/gi, " ").replace(/\\([,;\\])/g, "$1").trim();
}

// "NAME;P1=a;P2=\"b, c\":value" -> { name, params, value }; the value starts at the
// first colon outside quotes, since quoted parameters may contain colons.
function parseLine(line) {
  let inQuote = false;
  let i = 0;
  for (; i < line.length; i++) {
    const ch = line.charAt(i);
    if (ch === "\"") inQuote = !inQuote;
    else if (ch === ":" && !inQuote) break;
  }
  const parts = line.slice(0, i).match(/(?:[^;"]|"[^"]*")+/g) || [];
  const params = {};
  for (const part of parts.slice(1)) {
    const eq = part.indexOf("=");
    if (eq > 0) params[part.slice(0, eq).toUpperCase()] = part.slice(eq + 1).replace(/^"|"$/g, "");
  }
  return { name: (parts[0] || "").toUpperCase(), params: params, value: line.slice(i + 1) };
}

// People are the organizer and the attendees, once each, without the calendar owner
// (selfEmail) and without rooms or resources.
function parseEventInfo(icsText, selfEmail) {
  const info = { people: [], meetUrl: "", location: "" };
  const block = /BEGIN:VEVENT([\s\S]*?)END:VEVENT/i.exec(unfold(icsText));
  if (!block) return info;
  const self = String(selfEmail || "").toLowerCase();
  const seen = {};
  for (const raw of block[1].split(/\r?\n/)) {
    if (!raw) continue;
    const line = parseLine(raw);
    if (line.name === "ORGANIZER" || line.name === "ATTENDEE") {
      const email = line.value.replace(/^mailto:/i, "").trim();
      const key = email.toLowerCase();
      const kind = (line.params.CUTYPE || "INDIVIDUAL").toUpperCase();
      if (!email || key === self || seen[key] || (kind !== "INDIVIDUAL" && kind !== "GROUP")) continue;
      seen[key] = true;
      const status = line.params.PARTSTAT || (line.name === "ORGANIZER" ? "ACCEPTED" : "NEEDS-ACTION");
      info.people.push({ name: line.params.CN || email, email: email, status: status.toLowerCase() });
    } else if (line.name === "X-GOOGLE-CONFERENCE") {
      const url = line.value.trim();
      if (/^https:\/\/\S+$/.test(url)) info.meetUrl = url;
    } else if (line.name === "LOCATION") {
      info.location = unescapeText(line.value);
    }
  }
  return info;
}
