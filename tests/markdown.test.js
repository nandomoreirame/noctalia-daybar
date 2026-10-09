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
