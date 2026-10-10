import { describe, it, expect } from "vitest";
import { render, inline } from "../utils/mdrender.js";

const T = { text: "#eeeeee", dim: "#999999", link: "#ff88aa", codeBg: "#333333", codeFg: "#ffcc66", border: "#444444" };

describe("mdrender.inline", () => {
  it("escapes raw HTML before any markup", () => {
    expect(inline("<script>alert(1)</script> & co", T)).toBe("&lt;script&gt;alert(1)&lt;/script&gt; &amp; co");
  });

  it("renders bold, italic, strike and code spans", () => {
    const out = inline("**b** _i_ *j* ~~s~~ `a<b>*c*`", T);
    expect(out).toContain("<b>b</b>");
    expect(out).toContain("<i>i</i>");
    expect(out).toContain("<i>j</i>");
    expect(out).toContain("<s>s</s>");
    expect(out).toContain(">a&lt;b&gt;*c*</code>");
    expect(out).toContain("background-color:#333333");
  });

  it("links only http(s) and mailto, colored with the theme", () => {
    expect(inline("[site](https://x.com/a?b=1&c=2)", T)).toBe('<a href="https://x.com/a?b=1&amp;c=2" style="color:#ff88aa; text-decoration:none;">site</a>');
    expect(inline("[js](javascript:alert(1))", T)).toBe("js");
    expect(inline("[m](mailto:me@x.com)", T)).toContain('href="mailto:me@x.com"');
    expect(inline("<https://x.com>", T)).toContain('href="https://x.com"');
  });

  it("does not let a quote in the URL break out of the attribute", () => {
    expect(inline('[x](https://x.com/"onmouseover="y)', T)).not.toContain('"onmouseover="');
  });

  it("turns remote images into links and keeps absolute local images", () => {
    expect(inline("![cat](https://x.com/c.png)", T)).toContain('<a href="https://x.com/c.png"');
    expect(inline("![cat](https://x.com/c.png)", T)).not.toContain("<img");
    expect(inline("![l](/data/u/a.png)", T)).toBe('<img src="file:///data/u/a.png" alt="l">');
    expect(inline("![l](file:///data/u/a.png)", T)).toBe('<img src="file:///data/u/a.png" alt="l">');
  });
});

describe("mdrender.render blocks", () => {
  it("renders headings with a rule under h1 and h2", () => {
    const out = render("# Title\n## Sub\n### Third", T);
    expect(out).toMatch(/<h1[^>]*>Title<\/h1>\s*<hr/);
    expect(out).toMatch(/<h2[^>]*>Sub<\/h2>\s*<hr/);
    expect(out).toMatch(/<h3[^>]*>Third<\/h3>/);
    expect(out).not.toMatch(/<h3[^>]*>Third<\/h3>\s*<hr/);
  });

  it("joins paragraph lines and separates paragraphs", () => {
    const out = render("one\ntwo\n\nthree", T);
    expect(out).toMatch(/<p[^>]*>one two<\/p>\s*<p[^>]*>three<\/p>/);
  });

  it("renders fenced code verbatim and escaped on a tinted block", () => {
    const out = render("```js\nconst a = '<b>';\n**not bold**\n```", T);
    expect(out).toContain("const a = '&lt;b&gt;';");
    expect(out).toContain("**not bold**");
    expect(out).toContain("background-color:#333333");
    expect(out).toContain("<pre");
  });

  it("renders unordered, ordered and task lists", () => {
    const out = render("- a\n- [x] done\n- [ ] todo\n\n1. one\n2. two", T);
    expect(out).toMatch(/<ul[^>]*>\s*<li>a<\/li>\s*<li>☑ done<\/li>\s*<li>☐ todo<\/li>\s*<\/ul>/);
    expect(out).toMatch(/<ol[^>]*>\s*<li>one<\/li>\s*<li>two<\/li>\s*<\/ol>/);
  });

  it("nests indented list items", () => {
    const out = render("- a\n  - b\n- c", T);
    expect(out).toMatch(/<li>a\s*<ul[^>]*>\s*<li>b<\/li>\s*<\/ul>\s*<\/li>\s*<li>c<\/li>/);
  });

  it("renders blockquotes dimmed", () => {
    const out = render("> quoted **text**", T);
    expect(out).toContain("<blockquote");
    expect(out).toContain("<b>text</b>");
    expect(out).toContain("color:#999999");
  });

  it("renders GFM tables with header cells, borders and padding", () => {
    const out = render("| A | B |\n|---|:-:|\n| `x` | 2 |", T);
    expect(out).toContain('cellpadding="8"');
    expect(out).toContain("<th");
    expect(out).toMatch(/<td[^>]*><code[^>]*>x<\/code><\/td>/);
    expect(out).toContain('align="center"');
  });

  it("renders horizontal rules", () => {
    expect(render("a\n\n---\n\nb", T)).toContain("<hr");
  });

  it("returns an empty string for empty input", () => {
    expect(render("", T)).toBe("");
    expect(render(null, T)).toBe("");
  });
});

describe("mdrender link destinations", () => {
  it("keeps one level of parentheses in URLs", () => {
    expect(inline("[w](https://en.wikipedia.org/wiki/Foo_(bar))", T)).toContain('href="https://en.wikipedia.org/wiki/Foo_(bar)"');
  });
});
