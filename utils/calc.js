.pragma library

// Safe arithmetic evaluator for the "=" capture. Shunting-yard over a whitelisted
// token set; never uses eval/Function. Identifiers are rejected by the tokenizer.
//   evaluate("2+3*4")   -> { ok: true, value: 14 }
//   evaluate("200*15%") -> { ok: true, value: 30 }   (postfix percent)
//   evaluate("2/0")     -> { ok: false, error: "division-by-zero" }

var OPS = {
  "+": { prec: 1, right: false, unary: false },
  "-": { prec: 1, right: false, unary: false },
  "*": { prec: 2, right: false, unary: false },
  "/": { prec: 2, right: false, unary: false },
  "neg": { prec: 3, right: true, unary: true },
  "^": { prec: 4, right: true, unary: false }
};

// pt-BR first: a comma is the decimal mark and dots are thousands separators.
// Without a comma, dots grouping exact thousands ("1.000", "1.000.000") are
// thousands separators too; any other single dot is a decimal mark.
// "2,5" -> 2.5, "1.234,5" -> 1234.5, "1.000" -> 1000, "2.5" -> 2.5, "1.2.3" -> null
function parseNumber(raw) {
  let norm = raw;
  if (/^[1-9]\d{0,2}(\.\d{3})+$/.test(raw)) {
    norm = raw.replace(/\./g, "");
  } else if (raw.indexOf(",") >= 0) {
    if (raw.split(",").length > 2) return null;
    norm = raw.replace(/\./g, "").replace(",", ".");
  } else if (raw.split(".").length > 2) {
    return null;
  }
  if (!/^(\d+\.?\d*|\.\d+)$/.test(norm)) return null;
  return Number(norm);
}

function tokenize(src) {
  const tokens = [];
  let i = 0;
  while (i < src.length) {
    const c = src[i];
    if (c === " " || c === "\t") {
      i++;
    } else if (/[0-9.,]/.test(c)) {
      let j = i;
      while (j < src.length && /[0-9.,]/.test(src[j])) j++;
      const value = parseNumber(src.slice(i, j));
      if (value === null) return null;
      tokens.push({ t: "num", v: value });
      i = j;
    } else if ("+-*/^%()".indexOf(c) >= 0) {
      tokens.push({ t: c });
      i++;
    } else {
      return null;
    }
  }
  return tokens;
}

function toRpn(tokens) {
  const out = [];
  const stack = [];
  let prev = null;
  for (const tok of tokens) {
    if (tok.t === "num") {
      if (prev === "num" || prev === ")" || prev === "%") return null;
      out.push(tok);
      prev = "num";
    } else if (tok.t === "(") {
      if (prev === "num" || prev === ")" || prev === "%") return null;
      stack.push(tok);
      prev = "(";
    } else if (tok.t === ")") {
      while (stack.length && stack[stack.length - 1].t !== "(") out.push(stack.pop());
      if (!stack.length || prev === "(") return null;
      stack.pop();
      prev = ")";
    } else if (tok.t === "%") {
      if (prev !== "num" && prev !== ")" && prev !== "%") return null;
      out.push({ t: "pct" });
      prev = "%";
    } else {
      let op = tok.t;
      const unary = prev === null || prev === "(" || OPS.hasOwnProperty(prev);
      if (unary) {
        if (op === "+") continue;
        if (op !== "-") return null;
        op = "neg";
      }
      const o1 = OPS[op];
      while (!o1.unary && stack.length) {
        const top = stack[stack.length - 1].t;
        if (top === "(") break;
        const o2 = OPS[top];
        if (o2.prec > o1.prec || (o2.prec === o1.prec && !o1.right)) out.push(stack.pop());
        else break;
      }
      stack.push({ t: op });
      prev = op;
    }
  }
  while (stack.length) {
    const tok = stack.pop();
    if (tok.t === "(") return null;
    out.push(tok);
  }
  return out;
}

function evalRpn(rpn) {
  const st = [];
  for (const tok of rpn) {
    if (tok.t === "num") {
      st.push(tok.v);
    } else if (tok.t === "pct") {
      st.push(st.pop() / 100);
    } else if (tok.t === "neg") {
      if (st.length < 1) return { ok: false, error: "syntax" };
      st.push(-st.pop());
    } else {
      if (st.length < 2) return { ok: false, error: "syntax" };
      const b = st.pop();
      const a = st.pop();
      if (tok.t === "/" && b === 0) return { ok: false, error: "division-by-zero" };
      if (tok.t === "+") st.push(a + b);
      else if (tok.t === "-") st.push(a - b);
      else if (tok.t === "*") st.push(a * b);
      else if (tok.t === "/") st.push(a / b);
      else st.push(Math.pow(a, b));
    }
  }
  if (st.length !== 1) return { ok: false, error: "syntax" };
  if (!isFinite(st[0])) return { ok: false, error: "overflow" };
  return { ok: true, value: st[0] };
}

function evaluate(expr) {
  const src = String(expr || "").trim();
  if (!src) return { ok: false, error: "empty" };
  const tokens = tokenize(src);
  if (!tokens) return { ok: false, error: "syntax" };
  const rpn = toRpn(tokens);
  if (!rpn) return { ok: false, error: "syntax" };
  return evalRpn(rpn);
}

// pt-BR display/copy format: comma decimal, float noise rounded away. Rounds to
// 12 significant digits, so the cleanup scales with the magnitude of the result.
function formatNumber(value) {
  const rounded = Number(value.toPrecision(12));
  return String(rounded).replace(".", ",");
}
