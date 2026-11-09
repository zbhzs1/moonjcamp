import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "moonjcamp-cli-"));
let checks = 0;
function run(args, expected = 0, input) {
  const result = spawnSync(process.execPath, ["bin/moonjcamp.mjs", ...args], {cwd: root, encoding: "utf8", input, timeout: 30000});
  assert.equal(result.status, expected, `${args.join(" ")}\n${result.stdout}\n${result.stderr}`);
  checks++;
  return result.stdout;
}
const file = name => path.join(tmp, name);
const ir = "examples/data/ir-compressed.jdx";
const raman = "examples/data/raman-pairs.jdx";
try {
  // Scenario 1: compressed instrument-style import -> JSON -> normalized export.
  assert.equal(JSON.parse(run(["inspect", ir])).points, 9);
  run(["to-json", ir, "--out", file("ir.json")]);
  run(["from-json", file("ir.json"), "--out", file("ir.jdx"), "--encoding", "sqz", "--y-factor", "0.1"]);
  assert.equal(JSON.parse(run(["verify", ir, file("ir.jdx")])).equivalent, true);
  run(["rewrite", ir, "--out", file("ir.jdx")], 2);
  // Scenario 2: compound collection -> split -> CSV with metadata sidecar.
  run(["combine", ir, raman, "--out", file("collection.jdx")]);
  run(["split", file("collection.jdx"), "--out-dir", file("parts")]);
  assert.equal(JSON.parse(run(["inspect", file("parts/spectrum-2.jdx")])).missing, 1);
  run(["to-csv", file("parts/spectrum-2.jdx"), "--out", file("raman.csv")]);
  run(["from-csv", file("raman.csv"), "--metadata", file("raman.csv.metadata.json"), "--out", file("raman.jdx")]);
  assert.equal(JSON.parse(run(["verify", raman, file("raman.jdx")])).equivalent, true);
  // Scenario 3: explicit transformations -> quality gate -> provenance audit.
  run(["transform", ir, "--actions", "examples/actions.json", "--out", file("converted.jdx")]);
  assert.equal(JSON.parse(run(["summary", file("converted.jdx")])).accepted, true);
  const json = JSON.parse(run(["to-json", file("converted.jdx")]));
  assert.equal(json.spectra[0].points.length, 13);
  assert.equal(json.spectra[0].x_units, "NM");
  assert.equal(JSON.parse(json.spectra[0].records.find(r => r.label === "$MOONJCAMP.HISTORY").value).length, 4);
  run(["batch", ir, raman], 1);
  fs.writeFileSync(file("invalid.jdx"), "##TITLE=Unfinished\n");
  run(["inspect", file("invalid.jdx")], 1);
  run(["inspect", ir, "--width", "4"], 2);
  run(["rewrite", ir, "--width", "NaN"], 2);
  run(["inspect", ir, "--max-points", "1"], 1);
  run(["--protocol"], 1, '{"operation":"inspect","operation":"read","text":""}');
  fs.writeFileSync(file("duplicate.json"), '[{"operation":"crop","minimum":1,"minimum":2,"maximum":3}]');
  run(["transform", ir, "--actions", file("duplicate.json")], 1);
  fs.writeFileSync(file("invalid-utf8.jdx"), Buffer.from([0xff,0xfe,0x00]));
  run(["inspect", file("invalid-utf8.jdx")], 2);
  run(["inspect", tmp], 2);
  // Strict conformance is deliberately distinct from tolerant legacy parsing.
  const original = "examples/roundtrip/producer-original.jdx";
  const normalized = "examples/roundtrip/moon-normalized.jdx";
  assert.equal(JSON.parse(run(["validate-ir", normalized])).valid, true);
  run(["validate-ir", original], 1);
  run(["export-ir", original, "--out", file("strict.jdx")]);
  assert.equal(JSON.parse(run(["validate-ir", file("strict.jdx")])).valid, true);
  assert.equal(JSON.parse(run(["verify", original, file("strict.jdx")])).equivalent, true);
  run(["export-ir", ir], 1); // No OWNER supplied: do not invent provenance.
  console.log(`Four complete workflows and ${checks} CLI process checks passed.`);
} finally {
  // Only the fresh directory created by mkdtemp above is removed.
  fs.rmSync(tmp, {recursive: true, force: true});
}
