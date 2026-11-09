#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const maxBytes = 32 * 1024 * 1024;

function boundedRead(fd, limit) {
  const chunks = [];
  let total = 0;
  for (;;) {
    const buffer = Buffer.alloc(Math.min(65536, limit - total + 1));
    const size = fs.readSync(fd, buffer, 0, buffer.length, null);
    if (!size) break;
    total += size;
    if (total > limit) throw new Error("input exceeds byte budget");
    chunks.push(buffer.subarray(0, size));
  }
  return new TextDecoder("utf-8", { fatal: true }).decode(Buffer.concat(chunks));
}

function readText(file) {
  const fd = fs.openSync(file, "r");
  try {
    if (!fs.fstatSync(fd).isFile()) throw new Error("input must be a regular file");
    return boundedRead(fd, maxBytes);
  } finally {
    fs.closeSync(fd);
  }
}

function parseArgs(args) {
  const positional = [];
  const options = new Map();
  const known = new Set(["out", "out-dir", "encoding", "table", "width", "x-factor", "y-factor", "numeric-mode", "max-points", "metadata", "actions"]);
  let literal = false;
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (literal) { positional.push(arg); continue; }
    if (arg === "--") { literal = true; continue; }
    if (!arg.startsWith("--")) { positional.push(arg); continue; }
    const name = arg.slice(2);
    if (!known.has(name) || options.has(name)) throw new Error(`unknown or repeated option: ${arg}`);
    if (++i >= args.length) throw new Error(`missing value for ${arg}`);
    options.set(name, args[i]);
  }
  return { positional, options };
}

function numeric(value, name, integer = false) {
  if (!/^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?$/.test(value)) throw new Error(`invalid ${name}`);
  const n = Number(value);
  if (!Number.isFinite(n) || (integer && !Number.isSafeInteger(n))) throw new Error(`invalid ${name}`);
  return n;
}

function makeRequest(positional, options) {
  const [command, ...files] = positional;
  const commands = ["inspect", "validate-ir", "export-ir", "audit", "summary", "batch", "to-json", "from-json", "rewrite", "split", "combine", "to-csv", "from-csv", "transform", "verify"];
  if (!commands.includes(command)) throw new Error("unknown command");
  const multiple = ["batch", "combine", "verify"].includes(command);
  if (!files.length || (!multiple && files.length !== 1)) throw new Error("unexpected number of input paths");
  if (command === "verify" && files.length !== 2) throw new Error("verify requires exactly two inputs");
  const writeCommands = ["rewrite", "export-ir", "from-json", "from-csv", "transform"];
  for (const name of options.keys()) {
    if (name === "out" && command !== "split") continue;
    if (name === "out-dir" && command === "split") continue;
    if (name === "metadata" && command === "from-csv") continue;
    if (name === "actions" && command === "transform") continue;
    if (["numeric-mode", "max-points"].includes(name) && !["from-json", "from-csv", "combine"].includes(command)) continue;
    if (["encoding", "table", "width", "x-factor", "y-factor"].includes(name) && writeCommands.includes(command)) continue;
    throw new Error(`--${name} is not applicable to ${command}`);
  }
  const request = { operation: command === "to-json" ? "read" : command };
  let total = 0;
  const texts = files.map(file => {
    const text = readText(file);
    total += text.length;
    if (total > 16000000) throw new Error("combined input exceeds text budget");
    return text;
  });
  if (command === "combine" || command === "verify") request.texts = texts;
  else if (command === "batch") request.inputs = texts.map((text, i) => ({ name: files[i], text }));
  else request.text = texts[0];
  const write = {};
  for (const [option, field, type] of [["encoding", "encoding"], ["table", "table"], ["width", "points_per_line", "int"], ["x-factor", "x_factor", "number"], ["y-factor", "y_factor", "number"]]) {
    if (options.has(option)) write[field] = type ? numeric(options.get(option), option, type === "int") : options.get(option);
  }
  if (Object.keys(write).length) request.write_options = write;
  const read = {};
  if (options.has("numeric-mode")) read.numeric_mode = options.get("numeric-mode");
  if (options.has("max-points")) read.max_points = numeric(options.get("max-points"), "max-points", true);
  if (Object.keys(read).length) request.read_options = read;
  if (command === "from-csv") {
    if (!options.has("metadata")) throw new Error("from-csv requires --metadata SIDECAR");
    request.metadata_text = readText(options.get("metadata"));
  }
  if (command === "transform") {
    if (!options.has("actions")) throw new Error("transform requires --actions JSON_FILE");
    request.actions_text = readText(options.get("actions"));
  }
  return request;
}

function writeNew(file, text) {
  fs.writeFileSync(file, text, { encoding: "utf8", flag: "wx" });
}

function outputValue(command, value, options) {
  if (command === "split" && options.has("out-dir")) {
    const directory = path.resolve(options.get("out-dir"));
    fs.mkdirSync(directory);
    for (const file of value.files) {
      if (!/^spectrum-[1-9]\d*\.jdx$/.test(file.name)) throw new Error("invalid generated filename");
      writeNew(path.join(directory, file.name), file.text);
    }
    console.log(JSON.stringify({ directory, files: value.files.length }));
    return;
  }
  if (command === "to-csv" && options.has("out")) {
    const file = options.get("out");
    if (fs.existsSync(file) || fs.existsSync(`${file}.metadata.json`)) throw new Error("output or sidecar already exists");
    writeNew(file, value.csv);
    writeNew(`${file}.metadata.json`, JSON.stringify(value.metadata, null, 2) + "\n");
    return;
  }
  const text = typeof value.text === "string" ? value.text : JSON.stringify(value, null, 2) + "\n";
  if (options.has("out")) writeNew(options.get("out"), text);
  else process.stdout.write(text);
}

const args = process.argv.slice(2);
try {
  if (!args.length || (args.length === 1 && args[0] === "--help")) {
    console.log("MoonJCAMP\n  inspect|validate-ir|summary|to-json INPUT [--out FILE]\n  rewrite|from-json INPUT [--encoding affn|pac|sqz|difdup] [--out FILE]\n  to-csv INPUT --out FILE.csv\n  from-csv INPUT --metadata SIDECAR [--out FILE]\n  transform INPUT --actions ACTIONS.json [--out FILE]\n  split INPUT --out-dir NEW_DIRECTORY\n  combine|batch INPUT... [--out FILE]\n  --protocol  (bounded UTF-8 JSON on stdin)");
    process.exit(0);
  }
  const protocolMode = args.length === 1 && args[0] === "--protocol";
  const parsed = protocolMode ? null : parseArgs(args);
  const request = protocolMode ? boundedRead(0, 2 * maxBytes) : JSON.stringify(makeRequest(parsed.positional, parsed.options));
  const entry = path.join(root, "_build", "js", "release", "build", "cmd", "main", "main.js");
  if (!fs.existsSync(entry)) throw new Error("build the CLI with moon build --target js --release");
  globalThis.__moonjcamp_request = request;
  await import(pathToFileURL(entry).href);
  const response = JSON.parse(globalThis.__moonjcamp_response);
  if (protocolMode) console.log(JSON.stringify(response));
  else if (!response.ok) console.error(JSON.stringify(response));
  else outputValue(parsed.positional[0], response.value, parsed.options);
  if (!response.ok || response.value?.valid === false || response.value?.equivalent === false || response.value?.accepted === false || response.value?.rejected > 0) process.exitCode = 1;
} catch (error) {
  console.error(JSON.stringify({ ok: false, error: { code: "HOST_IO", message: error.message } }));
  process.exitCode = 2;
}
