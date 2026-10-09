import { describe, it, expect } from "vitest";
import { parse, decodeEntities } from "../utils/pagemeta.js";

const PAGE = "https://site.com/blog/post";

describe("pagemeta.decodeEntities", () => {
  it("decodes named and numeric entities", () => {
    expect(decodeEntities("A &amp; B &lt;3&gt; &quot;x&quot; &#39;y&#39; &#x41;&#66; caf&eacute;")).toBe("A & B <3> \"x\" 'y' AB café");
  });

  it("leaves unknown entities and invalid code points alone", () => {
    expect(decodeEntities("&bogus; &#xFFFFFFFF;")).toBe("&bogus; &#xFFFFFFFF;");
  });
});

describe("pagemeta.parse", () => {
  it("prefers Open Graph tags", () => {
    const html = `<html><head><title>Plain</title>
      <meta property="og:title" content="OG Title">
      <meta content="OG description" property="og:description" />
      <meta property='og:image' content='/img/cover.png'>
      <meta name="description" content="Meta description"></head></html>`;
    expect(parse(html, PAGE)).toEqual({ title: "OG Title", description: "OG description", image: "https://site.com/img/cover.png" });
  });

  it("falls back to twitter tags, <title> and meta description", () => {
    const html = `<TITLE>  Fallback
      title </TITLE><meta name="Description" content="Desc">
      <meta name="twitter:image" content="https://cdn.com/t.jpg">`;
    expect(parse(html, PAGE)).toEqual({ title: "Fallback title", description: "Desc", image: "https://cdn.com/t.jpg" });
  });

  it("decodes entities, strips tags and treats markup as text", () => {
    const html = `<meta property="og:title" content="&lt;script&gt;alert(1)&lt;/script&gt; Tom &amp; Jerry">`;
    expect(parse(html, PAGE).title).toBe("alert(1) Tom & Jerry");
  });

  it("caps title at 200 and description at 400 characters", () => {
    const long = "x".repeat(1000);
    const r = parse(`<meta property="og:title" content="${long}"><meta property="og:description" content="${long}">`, PAGE);
    expect(r.title.length).toBe(200);
    expect(r.description.length).toBe(400);
  });

  it("ignores non-http images and returns empty fields for empty input", () => {
    expect(parse(`<meta property="og:image" content="data:image/png;base64,AAAA">`, PAGE).image).toBe("");
    expect(parse("", PAGE)).toEqual({ title: "", description: "", image: "" });
    expect(parse(null, PAGE)).toEqual({ title: "", description: "", image: "" });
  });
});
