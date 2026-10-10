.pragma library
.import "markdown.js" as Markdown

// Markdown -> Qt rich text for the note preview. Qt's native MarkdownText takes
// no styling, so this renders a CommonMark/GFM subset with inline styles from a
// theme { text, dim, link, codeBg, codeFg, border } of "#rrggbb" strings.
// Safety: all source text is HTML-escaped; links only for http(s)/mailto; a
// remote image becomes a link (nothing loads from the network); only absolute
// local images are shown.

var P = "\u0000";

// Text content: & < >. Attribute values additionally need both quotes.
function esc(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function escAttr(s) {
  return esc(s).replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

// Link destination: no spaces, one level of balanced parentheses (wiki URLs,
// "javascript:alert(1)" is still consumed whole and then refused).
var DEST = "<?((?:[^()\\s<>]|\\([^()\\s]*\\))+)>?";

function linkHtml(url, labelHtml, t) {
  return '<a href="' + escAttr(url) + '" style="color:' + t.link + '; text-decoration:none;">' + labelHtml + "</a>";
}

function emphasis(html) {
  return html
    .replace(/\*\*(?=\S)([\s\S]*?\S)\*\*/g, "<b>$1</b>")
    .replace(/(^|[^\w])__(?=\S)([\s\S]*?\S)__(?=[^\w]|$)/g, "$1<b>$2</b>")
    .replace(/~~(?=\S)([\s\S]*?\S)~~/g, "<s>$1</s>")
    .replace(/(^|[^*])\*(?=[^\s*])([^*]*?[^\s*])\*(?!\*)/g, "$1<i>$2</i>")
    .replace(/(^|[^\w])_(?=[^\s_])([^_]*?[^\s_])_(?=[^\w]|$)/g, "$1<i>$2</i>");
}

function imageHtml(alt, src, t) {
  const s = String(src || "").trim();
  if (/^file:\/\//i.test(s)) return '<img src="' + escAttr(s) + '" alt="' + escAttr(alt) + '">';
  if (s.charAt(0) === "/" && s.charAt(1) !== "/") return '<img src="file://' + escAttr(s) + '" alt="' + escAttr(alt) + '">';
  // Remote (or unresolvable) image: a link at most, never a fetch.
  return Markdown.isOpenableLink(s) ? linkHtml(s, esc(alt || s), t) : esc(alt || s);
}

// Inline markup of one block. `refs` maps lowercase labels to URLs.
function inline(text, t, refs) {
  const defs = refs || {};
  const slots = [];
  const keep = (html) => {
    slots.push(html);
    return P + (slots.length - 1) + P;
  };
  const link = (label, url) => Markdown.isOpenableLink(url) ? keep(linkHtml(url, emphasis(esc(label)), t)) : keep(emphasis(esc(label)));
  let s = String(text || "");
  s = s.replace(/`([^`]+)`/g, (m, code) => keep('<code style="background-color:' + t.codeBg + "; color:" + t.codeFg + ';">' + esc(code) + "</code>"));
  s = s.replace(new RegExp("!\\[([^\\]]*)\\]\\(\\s*" + DEST + "(?:\\s+(?:\"[^\"]*\"|'[^']*'))?\\s*\\)", "g"), (m, alt, src) => keep(imageHtml(alt, src, t)));
  s = s.replace(/!\[([^\]]*)\]\[([^\]]*)\]/g, (m, alt, ref) => {
    const url = defs[String(ref || alt).toLowerCase()];
    return url ? keep(imageHtml(alt, url, t)) : m;
  });
  s = s.replace(new RegExp("\\[([^\\]]+)\\]\\(\\s*" + DEST + "(?:\\s+(?:\"[^\"]*\"|'[^']*'))?\\s*\\)", "g"), (m, label, url) => link(label, url));
  s = s.replace(/\[([^\]]+)\]\[([^\]]*)\]/g, (m, label, ref) => {
    const url = defs[String(ref || label).toLowerCase()];
    return url ? link(label, url) : m;
  });
  s = s.replace(/<((?:https?:\/\/|mailto:)[^\s>]+)>/gi, (m, url) => link(url, url));
  s = emphasis(esc(s));
  return s.replace(new RegExp(P + "(\\d+)" + P, "g"), (m, i) => slots[Number(i)]);
}

var RE_FENCE = /^\s{0,3}(```|~~~)/;
var RE_HEADING = /^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$/;
var RE_HR = /^\s{0,3}([-*_])(?:\s*\1){2,}\s*$/;
var RE_LIST = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/;
var RE_QUOTE = /^\s{0,3}>\s?(.*)$/;
var RE_TABLE_SEP = /^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/;
var RE_DEF = /^\s{0,3}\[([^\]]+)\]:\s*<?(\S+?)>?(?:\s+.*)?$/;

function cells(line) {
  return line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((c) => c.trim());
}

function tableHtml(head, sep, rows, t, refs) {
  const align = cells(sep).map((c) => (/^:-+:$/.test(c) ? "center" : /-+:$/.test(c) ? "right" : "left"));
  const cell = (tag, text, i) => "<" + tag + ' align="' + (align[i] || "left") + '">' + inline(text, t, refs) + "</" + tag + ">";
  let html = '<table border="1" cellspacing="0" cellpadding="8" style="border-color:' + t.border + '; border-style:solid; margin-bottom:12px;">';
  html += "<tr>" + cells(head).map((c, i) => cell("th", c, i)).join("") + "</tr>";
  for (const r of rows) html += "<tr>" + cells(r).map((c, i) => cell("td", c, i)).join("") + "</tr>";
  return html + "</table>";
}

function taskPrefix(text) {
  const m = /^\[([ xX])\]\s+(.*)$/.exec(text);
  return m ? (m[1] === " " ? "☐ " : "☑ ") + m[2] : text;
}

// items: [{ indent, ordered, text }] -> nested <ul>/<ol>
function listHtml(items, start, t, refs) {
  const base = items[start].indent;
  const tag = items[start].ordered ? "ol" : "ul";
  let html = "<" + tag + ' style="margin-top:0px; margin-bottom:12px;">';
  let i = start;
  while (i < items.length && items[i].indent >= base) {
    if (items[i].indent > base) {
      const nested = listHtml(items, i, t, refs);
      html = html.replace(/<\/li>$/, "") + nested.html + "</li>";
      i = nested.next;
      continue;
    }
    html += "<li>" + inline(taskPrefix(items[i].text), t, refs) + "</li>";
    i++;
  }
  return { html: html + "</" + tag + ">", next: i };
}

function render(source, t) {
  const lines = String(source || "").split(/\r?\n/);
  const refs = {};
  for (const l of lines) {
    const d = RE_DEF.exec(l);
    if (d) refs[d[1].trim().toLowerCase()] = d[2];
  }
  const out = [];
  let para = [];
  const flush = () => {
    if (para.length === 0) return;
    const text = para.map((l, k) => (k < para.length - 1 && / {2,}$/.test(l) ? l.trim() + P + "br" + P : l.trim())).join(" ");
    out.push('<p style="margin-top:0px; margin-bottom:12px;">' + inline(text, t, refs).split(P + "br" + P).join("<br/>") + "</p>");
    para = [];
  };
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (line.trim() === "" || RE_DEF.test(line)) {
      flush();
      i++;
      continue;
    }
    if (RE_FENCE.test(line)) {
      flush();
      const fence = RE_FENCE.exec(line)[1];
      const code = [];
      i++;
      while (i < lines.length && lines[i].trim().indexOf(fence) !== 0) code.push(lines[i++]);
      i++;
      out.push('<table width="100%" cellspacing="0" cellpadding="12" style="background-color:' + t.codeBg + '; margin-bottom:12px;"><tr><td><pre style="color:' + t.text + ';">' + esc(code.join("\n")) + "</pre></td></tr></table>");
      continue;
    }
    const h = RE_HEADING.exec(line);
    if (h) {
      flush();
      const n = h[1].length;
      out.push("<h" + n + ' style="margin-top:' + (n <= 2 ? 16 : 12) + 'px; margin-bottom:' + (n <= 2 ? 4 : 6) + 'px;">' + inline(h[2], t, refs) + "</h" + n + ">");
      if (n <= 2) out.push('<hr style="margin-bottom:10px;"/>');
      i++;
      continue;
    }
    if (RE_HR.test(line)) {
      flush();
      out.push("<hr/>");
      i++;
      continue;
    }
    if (line.indexOf("|") >= 0 && i + 1 < lines.length && RE_TABLE_SEP.test(lines[i + 1]) && lines[i + 1].indexOf("-") >= 0) {
      flush();
      const head = line;
      const sep = lines[i + 1];
      const rows = [];
      i += 2;
      while (i < lines.length && lines[i].indexOf("|") >= 0 && lines[i].trim() !== "") rows.push(lines[i++]);
      out.push(tableHtml(head, sep, rows, t, refs));
      continue;
    }
    if (RE_QUOTE.test(line)) {
      flush();
      const inner = [];
      while (i < lines.length && RE_QUOTE.test(lines[i])) inner.push(RE_QUOTE.exec(lines[i++])[1]);
      out.push('<blockquote style="color:' + t.dim + '; margin-left:12px;">' + render(inner.join("\n"), t) + "</blockquote>");
      continue;
    }
    if (RE_LIST.test(line)) {
      flush();
      const items = [];
      while (i < lines.length && RE_LIST.test(lines[i])) {
        const m = RE_LIST.exec(lines[i++]);
        items.push({ indent: m[1].replace(/\t/g, "    ").length, ordered: /\d/.test(m[2]), text: m[3] });
      }
      out.push(listHtml(items, 0, t, refs).html);
      continue;
    }
    para.push(line);
    i++;
  }
  flush();
  return out.join("\n");
}
