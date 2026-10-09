import { describe, it, expect } from "vitest";
import { removeFileArgs } from "../utils/cmd.js";

describe("cmd.removeFileArgs", () => {
  it("builds rm -f with the path after --", () => {
    expect(removeFileArgs("/c/thumbs/lz3k-9f")).toEqual(["rm", "-f", "--", "/c/thumbs/lz3k-9f"]);
  });
});
