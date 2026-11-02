import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const rows = [];
for (const name of fs.readdirSync(root).filter(n => n.endsWith(".mbt") && !n.includes("test"))) {
  const lines = fs.readFileSync(path.join(root, name), "utf8").split(/\r?\n/);
  const code = lines.filter(line => line.trim() && !line.trimStart().startsWith("//")).length;
  rows.push({file: name, lines: lines.length - (lines.at(-1) === "" ? 1 : 0), nonblank_noncomment: code});
}
console.log(JSON.stringify({basis: "Root production .mbt only; excludes tests, examples, FFI CLI, generated interfaces, third-party code. Line counts are not a quality or acceptance claim.", files: rows,
  total_lines: rows.reduce((n, r) => n + r.lines, 0), nonblank_noncomment: rows.reduce((n, r) => n + r.nonblank_noncomment, 0)}, null, 2));
