import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const require = createRequire(import.meta.url);
const { convert } = require("jcampconverter");
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const text = fs.readFileSync(path.join(root, "examples/data/complex-fid-ntuples.jdx"), "utf8");
function moon(operation, fields) {
  const result = spawnSync(process.execPath, ["bin/moonjcamp.mjs", "--protocol"], {
    cwd: root, input: JSON.stringify({operation, ...fields}),
    encoding: "utf8", timeout: 30000, maxBuffer: 1000000,
  });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const response = JSON.parse(result.stdout);
  assert.equal(response.ok, true);
  return response.value;
}
const source = moon("read-ntuples", {text});
const cases = [];
for (const encoding of ["affn", "pac", "sqz", "difdup"]) {
  for (const width of [1, 2, 8]) {
    const output = moon("rewrite-ntuples", {
      text, write_options: {encoding, points_per_line: width},
    }).text;
    const decoded = moon("read-ntuples", {text: output});
    assert.deepEqual(decoded.pages, source.pages);
    assert.equal(decoded.variables[1].form, encoding === "affn" ? "AFFN" : "ASDF");
    const external = convert(output, {keepSpectra: true, xy: true});
    assert.deepEqual(external.logs, []);
    assert.equal(external.flatten.length, 1);
    const spectra = external.flatten[0].spectra;
    assert.equal(spectra.length, 2);
    for (let i = 0; i < 2; i++) {
      assert.equal(spectra[i].pageValue, i + 1);
      assert.deepEqual(spectra[i].data.x, source.pages[i].points.map(point => point.x));
      assert.deepEqual(spectra[i].data.y, source.pages[i].points.map(point => point.y));
    }
    cases.push({encoding, width, pages: 2, points_per_page: 4, result: "passed"});
  }
}
const report = {
  source: "examples/data/complex-fid-ntuples.jdx",
  independent_reader: "jcampconverter@9.0.1",
  cases,
  limitation: "Synthetic writer-output checks, not full 5.00/5.01 conformance or independent NTUPLES production.",
};
const directory = path.join(root, "evidence/generated");
fs.mkdirSync(directory, {recursive: true});
fs.writeFileSync(path.join(directory, "ntuple-roundtrip.json"), JSON.stringify(report, null, 2) + "\n");
console.log("12 synthetic NTUPLES output cases passed independent reading and exact page-array checks.");
