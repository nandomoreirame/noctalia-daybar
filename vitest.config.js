import { defineConfig } from "vitest/config";

// Files under utils/ are QML JavaScript libraries: they start with `.pragma library`,
// may pull other libraries with `.import "x.js" as X`, and expose bare top-level
// declarations. Node needs ES modules, so at test time only we strip the pragma,
// turn each `.import` into an ES namespace import and export every top-level
// declaration. The files on disk stay valid QML libraries.
function qmlLibraryToEsm() {
  return {
    name: "qml-library-to-esm",
    enforce: "pre",
    transform(code, id) {
      if (!/\/utils\/.+\.js$/.test(id)) return null;

      let out = code
        .replace(/^[ \t]*\.pragma[ \t].*$/gm, "")
        .replace(/^[ \t]*\.import[ \t]+"([^"]+)"[ \t]+as[ \t]+([A-Za-z_$][\w$]*)[ \t]*$/gm, (_m, path, name) => {
          const spec = path.startsWith(".") ? path : "./" + path;
          return `import * as ${name} from "${spec}";`;
        });

      const names = new Set();
      const re = /^(?:function|const|let|var)\s+([A-Za-z_$][\w$]*)/gm;
      let match;
      while ((match = re.exec(out)) !== null) names.add(match[1]);

      if (names.size > 0) out += `\nexport { ${[...names].join(", ")} };\n`;
      return { code: out, map: null };
    }
  };
}

export default defineConfig({
  plugins: [qmlLibraryToEsm()],
  test: { environment: "node" }
});
