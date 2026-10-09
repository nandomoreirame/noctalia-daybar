.pragma library
.import "../calc.js" as Calc

// Calculation capture ("=2+2"): Enter copies the result and keeps the overlay open.
var TYPE = "calculation";

function build(expr) {
  const r = Calc.evaluate(expr);
  if (!r.ok) return { ok: false, type: TYPE, error: r.error };
  return { ok: true, type: TYPE, action: "copy", payload: { value: r.value, display: Calc.formatNumber(r.value) } };
}
