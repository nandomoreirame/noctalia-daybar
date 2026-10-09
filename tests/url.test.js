import { describe, it, expect } from "vitest";
import { isHttpUrl, normalizeUrl, domainOf, resolveUrl } from "../utils/url.js";

describe("url.isHttpUrl", () => {
  it.each([
    ["https://example.com", true],
    ["http://example.com/a?b=c#d", true],
    ["  https://example.com/x  ", true],
    ["ftp://example.com", false],
    ["https://", false],
    ["veja https://example.com", false],
    ["javascript:alert(1)", false],
    ["", false]
  ])("%j -> %s", (text, expected) => {
    expect(isHttpUrl(text)).toBe(expected);
  });
});

describe("url.normalizeUrl", () => {
  it.each([
    ["https://Example.COM/Path/", "https://example.com/Path"],
    ["https://example.com/a#section", "https://example.com/a"],
    ["https://example.com/a?utm_source=x&id=7&UTM_medium=y", "https://example.com/a?id=7"],
    ["https://example.com/?utm_campaign=z", "https://example.com"],
    ["  http://example.com  ", "http://example.com"]
  ])("%j -> %j", (input, expected) => {
    expect(normalizeUrl(input)).toBe(expected);
  });

  it("returns an empty string for non-http input", () => {
    expect(normalizeUrl("javascript:alert(1)")).toBe("");
    expect(normalizeUrl("")).toBe("");
  });
});

describe("url.domainOf", () => {
  it("returns the host without www and port", () => {
    expect(domainOf("https://www.GitHub.com/a")).toBe("github.com");
    expect(domainOf("http://localhost:8080/x")).toBe("localhost");
    expect(domainOf("not a url")).toBe("");
  });
});

describe("url.resolveUrl", () => {
  const page = "https://site.com/blog/post.html?x=1";
  it.each([
    ["https://cdn.com/a.png", "https://cdn.com/a.png"],
    ["//cdn.com/a.png", "https://cdn.com/a.png"],
    ["/img/a.png", "https://site.com/img/a.png"],
    ["a.png", "https://site.com/blog/a.png"],
    ["  /x.png  ", "https://site.com/x.png"],
    ["data:image/png;base64,AAA", ""],
    ["javascript:alert(1)", ""],
    ["", ""]
  ])("%j -> %j", (ref, expected) => {
    expect(resolveUrl(ref, page)).toBe(expected);
  });
});
