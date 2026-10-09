import { describe, it, expect } from "vitest";
import { pageArgs, imageArgs, thumbPath, removeArgs, isUsableExit } from "../utils/fetch.js";

const LIMITS = ["--proto", "=http,https", "--proto-redir", "=http,https", "--max-time", "8", "--max-filesize", "2000000", "--max-redirs", "5"];

describe("fetch argv", () => {
  it("fetches a page with protocol, time and size limits, URL after --", () => {
    const args = pageArgs("https://site.com/a");
    expect(args.slice(0, 2)).toEqual(["curl", "-sSL"]);
    expect(args).toEqual(expect.arrayContaining(LIMITS));
    expect(args.slice(-2)).toEqual(["--", "https://site.com/a"]);
  });

  it("downloads an image to a given path with the same limits", () => {
    const args = imageArgs("https://cdn.com/a.png", "/tmp/thumbs/abc");
    expect(args).toEqual(expect.arrayContaining(LIMITS));
    expect(args).toEqual(expect.arrayContaining(["-o", "/tmp/thumbs/abc"]));
    expect(args.slice(-2)).toEqual(["--", "https://cdn.com/a.png"]);
  });

  it("keeps a hostile URL as one inert argument", () => {
    const args = pageArgs("https://x.com/;rm -rf ~");
    expect(args[args.length - 1]).toBe("https://x.com/;rm -rf ~");
  });

  it("builds thumbnail paths from internal ids only", () => {
    expect(thumbPath("/c/thumbs", "lz3k-9f")).toBe("/c/thumbs/lz3k-9f");
    expect(thumbPath("/c/thumbs", "../etc/passwd")).toBe("");
    expect(removeArgs("/c/thumbs/lz3k-9f")).toEqual(["rm", "-f", "--", "/c/thumbs/lz3k-9f"]);
  });

  it("accepts a clean exit and a truncated-at-cap exit", () => {
    expect(isUsableExit(0)).toBe(true);
    expect(isUsableExit(63)).toBe(true);
    expect(isUsableExit(28)).toBe(false);
    expect(isUsableExit(6)).toBe(false);
  });
});

describe("fetch error handling and final URL", () => {
  it("fails on HTTP errors instead of parsing an error page", async () => {
    const { pageArgs, imageArgs, isUsableExit } = await import("../utils/fetch.js");
    expect(pageArgs("https://x.com")).toContain("--fail");
    expect(imageArgs("https://x.com/a.png", "/t/a")).toContain("--fail");
    expect(isUsableExit(22)).toBe(false);
  });

  it("appends the effective URL after a marker and splits it back", async () => {
    const { pageArgs, splitPageOutput, URL_MARKER } = await import("../utils/fetch.js");
    const args = pageArgs("https://bit.ly/x");
    expect(args[args.indexOf("-w") + 1]).toBe("\n" + URL_MARKER + "%{url_effective}");
    expect(splitPageOutput("<html>a</html>\n" + URL_MARKER + "https://site.com/post", "https://bit.ly/x")).toEqual({ html: "<html>a</html>", finalUrl: "https://site.com/post" });
    expect(splitPageOutput("<html>no marker</html>", "https://bit.ly/x")).toEqual({ html: "<html>no marker</html>", finalUrl: "https://bit.ly/x" });
    expect(splitPageOutput("x\n" + URL_MARKER + "javascript:1", "https://bit.ly/x").finalUrl).toBe("https://bit.ly/x");
  });
});
