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

describe("markdown.prepare: remote-image bypasses", () => {
  it("turns images with nested brackets in the alt text into links", () => {
    expect(prepare("![a [b] c](http://evil/x.png)")).toBe("[a [b] c](http://evil/x.png)");
  });

  it("turns angle-bracket destinations that contain spaces into links", () => {
    expect(prepare("![a](<http://evil/a b.png>)")).toBe("[a](http://evil/a b.png)");
  });

  it("drops <img> whose src is a remote URL hidden behind HTML entities", () => {
    expect(prepare('<img src="&#104;ttp://evil/x.png">')).toBe("");
    expect(prepare('<img src="&#x68;ttp://evil/x.png">')).toBe("");
    expect(prepare('<img src="http&colon;//evil/x.png">')).toBe("");
    expect(prepare('<img src="http:&sol;&sol;evil/x.png">')).toBe("");
  });

  it("drops <img> whose src hides a scheme via numeric entities without a semicolon", () => {
    expect(prepare('<img src="&#104ttp://evil/x.png">')).toBe("");
    expect(prepare('<img src="&#x68ttp://evil/x.png">')).toBe("");
  });

  it("drops <img> whose src has leading whitespace or control chars before a remote scheme", () => {
    expect(prepare('<img src=" http://evil/x.png">')).toBe("");
  });

  it("drops relative and unknown-scheme <img> src; keeps absolute local paths", () => {
    expect(prepare('<img src="rel/a.png">')).toBe("");
    expect(prepare('<img src="/data/u/a.png">')).toBe('<img src="/data/u/a.png">');
    expect(prepare('<img src="file:///data/u/a.png">')).toBe('<img src="file:///data/u/a.png">');
  });

  it("keeps local <img> even when the path uses an entity for an ampersand", () => {
    expect(prepare('<img src="/data/u/a&amp;b.png">')).toBe('<img src="/data/u/a&amp;b.png">');
  });

  it("keeps relative markdown images under the existing isLocalSource rule", () => {
    expect(prepare("![a](rel/a.png)")).toBe("![a](rel/a.png)");
  });
});
