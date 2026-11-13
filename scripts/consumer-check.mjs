import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const parent = path.join(root, ".interop");
fs.mkdirSync(parent, {recursive: true});
const directory = fs.mkdtempSync(path.join(parent, "consumer-"));
const moon = process.env.MOON_BIN || "moon";
const version = process.env.MOONJCAMP_VERSION || "0.3.0";
assert.match(version, /^\d+\.\d+\.\d+$/);
fs.writeFileSync(path.join(directory, "moon.mod"), `name = "local/independent-consumer"\nversion = "0.1.0"\nimport {\n  "zbhzs1/moonjcamp@${version}",\n}\n`);
fs.writeFileSync(path.join(directory, "moon.pkg"), 'import {\n  "zbhzs1/moonjcamp" @jcamp,\n}\noptions("is-main": true)\n');
const input = fs.readFileSync(path.join(root, "examples/roundtrip/moon-normalized.jdx"), "utf8");
const fid = fs.readFileSync(path.join(root, "examples/data/complex-fid-ntuples.jdx"), "utf8");
fs.writeFileSync(path.join(directory, "main.mbt"), [
  "///|",
  "fn main raise {",
  "  let text = " + JSON.stringify(input),
  "  let spectra = @jcamp.read_spectra(text)",
  "  let output = @jcamp.write_ir_424(spectra[0])",
  "  let report = @jcamp.validate_ir_424(output)",
  "  assert_true(report.valid)",
  "  let source = " + JSON.stringify(fid),
  "  let ntuples = @jcamp.read_ntuples(source)",
  "  let normalized = @jcamp.write_ntuples(ntuples)",
  "  let checked = @jcamp.read_ntuples(normalized)",
  "  assert_true(checked.pages == ntuples.pages)",
  "  assert_true(checked.variables[1].form == \"ASDF\")",
  "  let result : Json = {",
  "    \"valid\": Json(report.valid),",
  "    \"points\": Json(report.points),",
  "    \"ntuples_pages\": Json(checked.pages.length()),",
  "    \"ntuples_points_per_page\": Json(checked.pages[0].points.length()),",
  "  }",
  "  println(result.stringify())",
  "}",
  "",
].join("\n"));
function run(args) {
  const result = spawnSync(moon, args, {cwd: directory, encoding: "utf8", timeout: 120000, env: process.env});
  if (result.status !== 0) throw new Error(`${args.join(" ")}: ${result.error || ""}\n${result.stdout}\n${result.stderr}`);
  return result.stdout;
}
run(["update"]);
run(["check", "--target", "js", "--deny-warn"]);
for (const target of ["js", "wasm-gc"]) {
  const output = run(["run", ".", "--target", target]);
  const json = JSON.parse(output.trim());
  assert.equal(json.valid, true);
  assert.equal(json.points, 32);
  assert.equal(json.ntuples_pages, 2);
  assert.equal(json.ntuples_points_per_page, 4);
}
const report = {module: "zbhzs1/moonjcamp", version, targets: ["js", "wasm-gc"],
  local_path_override: false, ir_points: 32, ntuples_pages: 2, ntuples_points_per_page: 4,
  result: "passed"};
const out = path.join(root, "evidence/generated");
fs.mkdirSync(out, {recursive: true});
fs.writeFileSync(path.join(out, "consumer.json"), JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify(report, null, 2));
