import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { fromJSON } from "convert-to-jcamp";

const require = createRequire(import.meta.url);
const { convert } = require("jcampconverter");
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const generated = path.join(root, "evidence/generated/roundtrip");
fs.mkdirSync(generated, { recursive: true });
const sha = text => createHash("sha256").update(text).digest("hex");
const cases = [];
const refresh = process.argv.includes("--refresh-examples");
const exampleDirectory = path.join(root, "examples/roundtrip");

function example(original, exported, points, producerTolerance) {
  const expected = JSON.stringify({
    description: "Synthetic spectrum; raw independent producer output is not repaired.",
    producer: "convert-to-jcamp@7.0.2", reader: "jcampconverter@9.0.1",
    originalSha256: sha(original), normalizedSha256: sha(exported),
    points, producerTolerance,
  }, null, 2) + "\n";
  for (const [name, text] of [["producer-original.jdx", original], ["moon-normalized.jdx", exported], ["expected.json", expected]]) {
    const file = path.join(exampleDirectory, name);
    if (refresh) {
      fs.mkdirSync(exampleDirectory, { recursive: true });
      fs.writeFileSync(file, text);
    } else {
      assert.equal(fs.readFileSync(file, "utf8"), text, `checked-in example drift: ${name}`);
    }
  }
}

function moon(operation, fields) {
  const result = spawnSync(process.execPath, ["bin/moonjcamp.mjs", "--protocol"], {
    cwd: root, input: JSON.stringify({ operation, ...fields }),
    encoding: "utf8", timeout: 30000,
  });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const response = JSON.parse(result.stdout);
  assert.equal(response.ok, true, JSON.stringify(response));
  return response.value;
}

function independent(text) {
  const result = convert(text, { keepSpectra: true, xy: true });
  assert.deepEqual(result.logs, [], "independent reader emitted diagnostics");
  assert.equal(result.flatten.length, 1);
  assert.equal(result.flatten[0].spectra.length, 1);
  return { ...result.flatten[0].spectra[0], title: result.flatten[0].title };
}

function arrays(actual, expected, tolerance = 1e-12) {
  assert.equal(actual.length, expected.length);
  let maximum = 0;
  for (let i = 0; i < actual.length; i++) {
    assert.ok(Number.isFinite(actual[i]) && Number.isFinite(expected[i]));
    const error = Math.abs(actual[i] - expected[i]);
    assert.ok(error <= tolerance, `point ${i}: ${actual[i]} != ${expected[i]}; tolerance ${tolerance}`);
    maximum = Math.max(maximum, error);
  }
  return maximum;
}

function info(title) {
  return {
    title, dataType: "INFRARED SPECTRUM", origin: "MoonJCAMP interoperability test",
    owner: "Synthetic data, MIT", xUnits: "1/CM", yUnits: "ABSORBANCE",
  };
}

function producer(data, title, encoding) {
  // Call the public upstream API; no header, newline or payload repair follows.
  // Omit optional explicit factors: upstream 7.0.2 duplicates those header labels.
  return fromJSON(data, { xyEncoding: encoding, info: info(title) });
}

const encodings = { FIX: "affn", PAC: "pac", SQZ: "sqz", DIFDUP: "difdup" };
for (const descending of [false, true]) {
  for (const amplitude of [1, 0.25]) {
    for (const [upstreamEncoding, encoding] of Object.entries(encodings)) {
      const x = Array.from({ length: 32 }, (_, i) => 100 + (descending ? 31 - i : i));
      const y = x.map((_, i) => ([2, 3, 4, 5, 4, 3, 0, -2][i % 8]) * amplitude);
      const name = `producer-${encoding}-${descending ? "descending" : "ascending"}-${amplitude}`;
      const original = producer({ x, y }, name, upstreamEncoding);
      const before = independent(original);
      const imported = moon("read", { text: original }).spectra[0];
      const decodedX = imported.points.map(p => p.x);
      const decodedY = imported.points.map(p => p.y);
      const xError = arrays(decodedX, before.data.x, 1e-9);
      const yError = arrays(decodedY, before.data.y, 1e-12);
      arrays(decodedX, x, 1e-9);
      const yFactor = Number(imported.records.find(r => r.label.toUpperCase() === "YFACTOR").value);
      const quantization = Math.abs(yFactor) / 2 + 1e-12;
      const producerError = arrays(decodedY, y, quantization);
      const exported = moon("write-ir", {
        spectrum: imported, write_options: { encoding, y_factor: yFactor, points_per_line: 5 },
      }).text;
      assert.equal(moon("validate-ir", { text: exported }).valid, true);
      const after = independent(exported);
      arrays(after.data.x, decodedX, 1e-9);
      arrays(after.data.y, decodedY, 1e-12);
      assert.equal(after.xUnits, imported.x_units);
      assert.equal(after.yUnits, imported.y_units);
      assert.equal(after.title, imported.title);
      if (name === "producer-difdup-ascending-0.25") {
        example(original, exported, imported.points, quantization);
      }
      fs.writeFileSync(path.join(generated, `${name}-original.jdx`), original);
      fs.writeFileSync(path.join(generated, `${name}-exported.jdx`), exported);
      cases.push({
        name, direction: "convert-to-jcamp -> MoonJCAMP -> jcampconverter",
        points: x.length, inputChanged: false, inputSha256: sha(original),
        outputSha256: sha(exported), xError, yError,
        producerQuantizationError: producerError, allowedProducerQuantization: quantization,
      });
    }
  }
}

for (const descending of [false, true]) {
  const x = Array.from({ length: 20 }, (_, i) => 100 + (descending ? 19 - i : i) / 2);
  const y = x.map((_, i) => 1 + (i % 4) / 4);
  const original = producer({ x, y }, "Both axes scaled", "DIFDUP");
  const imported = moon("read", { text: original }).spectra[0];
  const factors = Object.fromEntries(imported.records.map(r => [r.label.toUpperCase(), Number(r.value)]));
  assert.notEqual(factors.XFACTOR, 1);
  assert.notEqual(factors.YFACTOR, 1);
  const before = independent(original);
  arrays(imported.points.map(p => p.x), before.data.x, 1e-7);
  arrays(imported.points.map(p => p.y), before.data.y, 1e-12);
  arrays(imported.points.map(p => p.x), x, 1e-12);
  arrays(imported.points.map(p => p.y), y, Math.abs(factors.YFACTOR) / 2 + 1e-12);
  const exported = moon("write-ir", {
    spectrum: imported, write_options: { encoding: "difdup", y_factor: factors.YFACTOR, points_per_line: 5 },
  }).text;
  const after = independent(exported);
  arrays(after.data.x, x, 1e-12);
  arrays(after.data.y, imported.points.map(p => p.y), 1e-12);
  cases.push({ name: `both-axes-scaled-${descending}`, direction: "convert-to-jcamp -> MoonJCAMP -> jcampconverter", inputChanged: false, points: x.length, inputSha256: sha(original), outputSha256: sha(exported) });
}

for (const encoding of Object.values(encodings)) {
  for (const width of [2, 5, 8]) {
    const x = Array.from({ length: 24 }, (_, i) => 400 - i);
    const y = x.map((_, i) => [1, 2, 3, 4, 8, 16, 12, 3][i % 8]);
    const name = `moon-${encoding}-width-${width}`;
    const spectrum = {
      title: name, data_type: "INFRARED SPECTRUM", x_units: "1/CM", y_units: "ABSORBANCE",
      points: x.map((value, i) => ({ x: value, y: y[i] })),
      records: [
        { label: "ORIGIN", value: info(name).origin, line: 0 },
        { label: "OWNER", value: info(name).owner, line: 0 },
      ],
    };
    const original = moon("write-ir", { spectrum, write_options: { encoding, points_per_line: width } }).text;
    const read = independent(original);
    arrays(read.data.x, x);
    arrays(read.data.y, y);
    const returned = producer(read.data, name, "DIFDUP");
    const roundtrip = moon("read", { text: returned }).spectra[0];
    arrays(roundtrip.points.map(p => p.x), x);
    arrays(roundtrip.points.map(p => p.y), y);
    assert.equal(roundtrip.x_units, spectrum.x_units);
    assert.equal(roundtrip.y_units, spectrum.y_units);
    cases.push({
      name, direction: "MoonJCAMP -> jcampconverter -> convert-to-jcamp -> MoonJCAMP",
      points: x.length, inputChanged: false, inputSha256: sha(original), outputSha256: sha(returned),
    });
  }
}

const report = {
  target: "JCAMP-DX 4.24 simple infrared spectrum CORE exchange",
  producer: "convert-to-jcamp@7.0.2 (MIT)", reader: "jcampconverter@9.0.1 (MIT)",
  lockSha256: sha(fs.readFileSync(path.join(root, "package-lock.json"))),
  passed: cases.length, cases,
  limits: [
    "Synthetic IR spectra, not instrument certification or all JCAMP data types.",
    "Raw producer LF endings are accepted in compatibility mode, not labelled strict 4.24.",
    "Producer auto-scaling can quantize nonintegers; its error is measured separately.",
    "Optional explicit producer factors are not requested due to upstream duplicate headers.",
  ],
};
fs.writeFileSync(path.join(root, "evidence/generated/roundtrip.json"), JSON.stringify(report, null, 2) + "\n");
console.log(`${report.passed} unmodified cross-tool roundtrip cases passed.`);
