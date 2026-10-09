import { describe, it, expect } from "vitest";
import { prepare, isOpenableLink } from "../utils/markdown.js";

describe("markdown.prepare", () => {
  it("turns remote images into links with their alt text", () => {
    expect(prepare("see ![a cat](https://x.com/cat.png) here")).toBe("see [a cat](https://x.com/cat.png) here");
    expect(prepare('![](http://x.com/a.png "t")')).toBe("[http://x.com/a.png](http://x.com/a.png)");
  });

  it("keeps local images", () => {
    expect(prepare("![local](file:///opt/u/a.png)")).toBe("![local](file:///opt/u/a.png)");
    expect(prepare("![abs](/opt/u/a.png)")).toBe("![abs](/opt/u/a.png)");
  });

  it("removes raw <img> tags that point to the network", () => {
    expect(prepare('a <img src="https://x.com/t.gif"> b')).toBe("a  b");
    expect(prepare("<IMG SRC='//x.com/t.gif'/>")).toBe("");
  });

  it("returns an empty string for empty input", () => {
    expect(prepare("")).toBe("");
    expect(prepare(null)).toBe("");
  });
});

describe("markdown.isOpenableLink", () => {
  it.each([
    ["https://x.com", true],
    ["http://x.com/a", true],
    ["mailto:me@x.com", true],
    ["javascript:alert(1)", false],
    ["file:///etc/passwd", false],
    ["data:text/html,hi", false],
    ["", false]
  ])("%j -> %s", (url, expected) => {
    expect(isOpenableLink(url)).toBe(expected);
  });
});

describe("markdown.prepare: every remote image form", () => {
  it.each([
    ["![a](https://x/p.png 'tit')", "[a](https://x/p.png)"],
    ["![a](https://x/p.png (tit))", "[a](https://x/p.png)"],
    ["![a](<https://x/p.png>)", "[a](https://x/p.png)"],
    ["![a](//x/p.png)", "[a](//x/p.png)"]
  ])("%j -> %j", (input, expected) => {
    expect(prepare(input)).toBe(expected);
  });

  it("turns reference-style remote images into links", () => {
    const md = "![logo][r] and ![r] and ![r][]\n\n[r]: https://tracker/pixel.png";
    expect(prepare(md)).toBe("[logo][r] and [r] and [r][]\n\n[r]: https://tracker/pixel.png");
  });

  it("keeps reference-style local images", () => {
    const md = "![logo][l]\n\n[l]: /data/u/logo.png";
    expect(prepare(md)).toBe(md);
  });

  it("drops any <img> that is not local, whatever the quoting", () => {
    expect(prepare("a <img src=https://x/t.gif> b")).toBe("a  b");
    expect(prepare('<img alt="x" src="file:///data/u/a.png">')).toBe('<img alt="x" src="file:///data/u/a.png">');
  });
});
