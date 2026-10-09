import { describe, it, expect } from "vitest";
import { isHttpUrl, normalizeUrl, domainOf, resolveUrl, isPublicHttpUrl } from "../utils/url.js";

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

describe("url.isPublicHttpUrl", () => {
  it.each([
    ["https://example.com/a.png", true],
    ["http://cdn.example.org/x", true],
    ["https://1.2.3.4/a.png", true],
    ["https://localhost/a.png", false],
    ["http://foo.localhost/x", false],
    ["http://127.0.0.1/a", false],
    ["http://127.1.2.3/a", false],
    ["http://0.0.0.0/a", false],
    ["http://10.0.0.1/a", false],
    ["http://10.255.255.255/a", false],
    ["http://172.16.0.1/a", false],
    ["http://172.31.255.1/a", false],
    ["http://172.15.0.1/a", true],
    ["http://172.32.0.1/a", true],
    ["http://192.168.1.1/a", false],
    ["http://169.254.1.1/a", false],
    ["http://[::1]/a", false],
    ["http://[fc00::1]/a", false],
    ["http://[fd12::1]/a", false],
    ["http://[fe80::1]/a", false],
    ["http://[2001:db8::1]/a", true],
    ["http://intranet/a", false],
    ["http://my-box/a", false],
    ["ftp://example.com/a", false],
    ["javascript:alert(1)", false],
    ["", false],
    ["not a url", false],
    // Non-canonical / decimal / hex IPv4 forms curl still accepts
    ["http://127.1/a", false],
    ["http://2130706433/a", false],
    ["http://0x7f.0.0.1/a", false],
    ["http://0177.0.0.1/a", false],
    ["http://0x7f000001/a", false],
    // Trailing dot on host
    ["http://localhost./a", false],
    ["http://10.0.0.1./a", false],
    // IPv6 unspecified, loopback expansions, IPv4-mapped
    ["http://[::]/a", false],
    ["http://[0:0:0:0:0:0:0:1]/a", false],
    ["http://[::ffff:127.0.0.1]/a", false],
    ["http://[::ffff:7f00:1]/a", false],
    ["http://[::ffff:10.0.0.1]/a", false],
    // Extra private / reserved IPv4 ranges
    ["http://100.64.0.1/a", false],
    ["http://100.127.255.255/a", false],
    ["http://198.18.0.1/a", false],
    ["http://198.19.255.255/a", false],
    ["http://224.0.0.1/a", false],
    ["http://255.255.255.255/a", false]
  ])("%j -> %s", (url, expected) => {
    expect(isPublicHttpUrl(url)).toBe(expected);
  });
});

describe("url.isPublicHttpUrl: hex-letter domains are real domains", () => {
  it.each(["https://cafe.de/x.png", "https://bad.de/a.png", "https://ace.be/i.jpg", "https://dead.beef.com/i.png"])("%s is public", async (u) => {
    const { isPublicHttpUrl } = await import("../utils/url.js");
    expect(isPublicHttpUrl(u)).toBe(true);
  });

  it.each(["http://127.1/", "http://0x7f.0.0.1/", "http://0177.0.0.1/", "http://2130706433/", "http://0x7f000001/"])("%s stays private", async (u) => {
    const { isPublicHttpUrl } = await import("../utils/url.js");
    expect(isPublicHttpUrl(u)).toBe(false);
  });
});
