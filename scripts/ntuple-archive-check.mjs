import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { convert } = require("jcampconverter");
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const revision = "797bb84ece314a867b21d24242c1bc4c6775a251";
const expectedHashes = {
  "TESTFID.DX": "692b07e38e66760d6b4901f2025170062cac67309951bcd9d448670f91e35aca",
  "TESTNTUP.DX": "0f9ada4e073d8b77f9b6a0bf2c114d296fd57ae0848ddbc3e99ae57c063c126d",
  "BRUKNTUP.DX": "2d4749ba0e94dc355b2fe619f71bd0ed8e59e5fa731f572db993f97ebd441449",
};
const directory = path.join(root, ".interop");
fs.mkdirSync(directory, {recursive: true});
function call(operation, fields) {
  const result = spawnSync(process.execPath, ["bin/moonjcamp.mjs", "--protocol"], {
    cwd: root, encoding: "utf8", input: JSON.stringify({operation, ...fields}),
    maxBuffer: 32 * 1024 * 1024, timeout: 60000,
  });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  const response = JSON.parse(result.stdout);
  assert.equal(response.ok, true, JSON.stringify(response));
  return response.value;
}
function compareArrays(actual, expected, label, relativeTolerance = 1e-12, absoluteTolerance = 1e-7) {
  assert.equal(actual.length, expected.length, label + " point count differs");
  let maximumAbsoluteError = 0;
  for (let i = 0; i < expected.length; i++) {
    assert.ok(Number.isFinite(actual[i]) && Number.isFinite(expected[i]));
    const error = Math.abs(actual[i] - expected[i]);
    const tolerance = Math.max(absoluteTolerance, Math.abs(expected[i]) * relativeTolerance);
    assert.ok(error <= tolerance,
      label + "[" + i + "]: " + actual[i] + " != " + expected[i] + ", tolerance " + tolerance);
    maximumAbsoluteError = Math.max(maximumAbsoluteError, error);
  }
  return maximumAbsoluteError;
}
const results = [];
for (const name of ["TESTFID.DX", "TESTNTUP.DX", "BRUKNTUP.DX"]) {
  const target = path.join(directory, name);
  if (!fs.existsSync(target)) {
    const response = await fetch(`https://api.github.com/repos/IUPAC/JCAMP-DX/contents/jcamp-dx.org_test_data/${name}?ref=${revision}`, {
      headers: {Accept: "application/vnd.github.raw+json"},
      signal: AbortSignal.timeout(30000),
    });
    assert.equal(response.status, 200);
    fs.writeFileSync(target, Buffer.from(await response.arrayBuffer()));
  }
  const bytes = fs.readFileSync(target);
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  assert.equal(sha256, expectedHashes[name], "fixture hash differs from pinned archive revision");
  const text = new TextDecoder("utf-8", {fatal: true}).decode(bytes);
  const input = call("read-ntuples", {text});
  assert.equal(input.pages.length, 2);
  assert.equal(input.pages[0].points.length, 16384);
  const outputs = [];
  for (const encoding of ["affn", "pac", "sqz", "difdup"]) {
    const output = call("rewrite-ntuples", {text, write_options: {encoding, points_per_line: 12}}).text;
    const decoded = call("read-ntuples", {text: output});
    assert.deepEqual(decoded.pages, input.pages);
    const expectedForm = encoding === "affn" ? "AFFN" : "ASDF";
    assert.deepEqual(decoded.variables.map(v => [v.symbol, v.role, v.form, v.dimension, v.units, v.factor]),
      input.variables.map((v, index) => [v.symbol, v.role,
        index === 1 || index === 2 ? expectedForm : v.form,
        v.dimension, v.units, v.factor]));
    const external = convert(output, {keepSpectra: true, xy: true});
    assert.deepEqual(external.logs, [], name + " " + encoding + ": independent reader diagnostics");
    assert.equal(external.flatten.length, 1);
    const spectra = external.flatten[0].spectra;
    assert.equal(spectra.length, 2);
    const frequency = Number(input.records.find(record =>
      record.label.toUpperCase().replace(/[^A-Z0-9]/g, "") === "OBSERVEFREQUENCY")?.value);
    const comparisons = [];
    for (let page = 0; page < 2; page++) {
      const spectrum = spectra[page];
      assert.equal(spectrum.pageValue, page + 1);
      const sourceUnits = input.variables[0].units.toUpperCase();
      const axisScale = sourceUnits === "HZ" &&
        String(spectrum.xUnits).toUpperCase().includes("PPM") ? frequency : 1;
      assert.ok(Number.isFinite(axisScale) && axisScale > 0);
      const offsetRecord = input.records.find(record => record.label.toUpperCase() === "$OFFSET");
      const offset = offsetRecord ? Number(offsetRecord.value) : 0;
      assert.ok(Number.isFinite(offset));
      const reverseOffset = offset ? input.variables[0].first - offset * axisScale : 0;
      const expectedX = input.pages[page].points.map(point => point.x);
      const expectedY = input.pages[page].points.map(point => point.y);
      comparisons.push({
        x: compareArrays(spectrum.data.x.map(value => value * axisScale + reverseOffset), expectedX,
          name + "/" + encoding + "/page-" + (page + 1) + "/x"),
        y: compareArrays(spectrum.data.y, expectedY,
          name + "/" + encoding + "/page-" + (page + 1) + "/y"),
        external_x_units: spectrum.xUnits,
        external_y_units: spectrum.yUnits,
        reversed_axis_scale: axisScale,
        reversed_axis_offset: reverseOffset,
      });
    }
    outputs.push({encoding, independent_reader: "jcampconverter@9.0.1", comparisons});
  }
  results.push({name, sha256,
    version: input.version, data_type: input.data_type, pages: input.pages.length,
    points_per_page: input.pages[0].points.length, encodings: outputs});
}
const report = {archive: `IUPAC/JCAMP-DX@${revision}`, cases: results,
  comparison_tolerance: {absolute: 1e-7, relative: 1e-12, rule: "max(absolute, abs(expected)*relative)"},
  limits: "Historical examples, not a complete conformance suite. Independent-reader Hz/ppm and vendor-offset transformations are explicitly reversed. External files remain ignored and are not redistributed."};
fs.mkdirSync(path.join(root, "evidence/generated"), {recursive: true});
fs.writeFileSync(path.join(root, "evidence/generated/ntuple-archive.json"), JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify(report, null, 2));
