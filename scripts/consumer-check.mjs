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
fs.writeFileSync(path.join(directory, "moon.mod"), 'name = "local/independent-consumer"\nversion = "0.1.0"\nimport {\n  "zbhzs1/moonjcamp@0.1.0",\n}\n');
fs.writeFileSync(path.join(directory, "moon.pkg"), 'import {\n  "zbhzs1/moonjcamp" @jcamp,\n}\noptions("is-main": true)\n');
const input = fs.readFileSync(path.join(root, "examples/data/ir-compressed.jdx"), "utf8");
fs.writeFileSync(path.join(directory, "main.mbt"), `///|\nfn main {\n  let response = @jcamp.handle_request({"operation": "read", "text": ${JSON.stringify(input)}})\n  println(response.stringify())\n}\n`);
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
  assert.equal(json.ok, true);
  assert.equal(json.value.spectra[0].points.length, 9);
  assert.ok(Math.abs(json.value.spectra[0].points[8].y - 1.8) < 1e-12);
}
const report = {module: "zbhzs1/moonjcamp", version: "0.1.0", targets: ["js", "wasm-gc"], directory,
  local_path_override: false, result: "passed"};
const out = path.join(root, "evidence/generated");
fs.mkdirSync(out, {recursive: true});
fs.writeFileSync(path.join(out, "consumer.json"), JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify(report, null, 2));
