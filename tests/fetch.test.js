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
