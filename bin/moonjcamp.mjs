#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const maxBytes = 32 * 1024 * 1024;

function readText(file) {
  const fd = fs.openSync(file, "r");
  try {
    if (!fs.fstatSync(fd).isFile()) throw new Error("input must be a regular file");
    const chunks = [];
    let total = 0;
    for (;;) {
      const buffer = Buffer.alloc(Math.min(65536, maxBytes - total + 1));
      const size = fs.readSync(fd, buffer, 0, buffer.length, null);
      if (!size) break;
      total += size;
      if (total > maxBytes) throw new Error("input exceeds byte budget");
      chunks.push(buffer.subarray(0, size));
    }
    return new TextDecoder("utf-8", { fatal: true }).decode(Buffer.concat(chunks));
  } finally {
    fs.closeSync(fd);
  }
}

const args = process.argv.slice(2);
try {
  let request;
  if (args[0] === "--protocol") {
    const buffer = fs.readFileSync(0);
    if (buffer.length > 2 * maxBytes) throw new Error("protocol input exceeds byte budget");
    request = new TextDecoder("utf-8", { fatal: true }).decode(buffer);
  } else {
    const [command, input] = args;
    if (!command || command === "--help") {
      console.log("MoonJCAMP\n  inspect INPUT\n  to-json INPUT\n  rewrite INPUT\n  from-json INPUT\n  split INPUT\n  combine INPUT...\n  --protocol");
      process.exit(0);
    }
    if (!input) throw new Error("input path is required");
    if (command === "combine") {
      const texts = args.slice(1).map(readText);
      if (texts.reduce((n, text) => n + text.length, 0) > 16000000) throw new Error("combined input exceeds text budget");
      request = JSON.stringify({ operation: "combine", texts });
    } else {
      const operation = command === "to-json" ? "read" : command;
      if (!["inspect", "read", "rewrite", "from-json", "split"].includes(operation)) throw new Error("unknown command");
      if (args.length !== 2) throw new Error("unexpected arguments");
      request = JSON.stringify({ operation, text: readText(input) });
    }
  }
  const entry = path.join(root, "_build", "js", "release", "build", "cmd", "main", "main.js");
  if (!fs.existsSync(entry)) throw new Error("build the CLI with moon build --target js --release");
  globalThis.__moonjcamp_request = request;
  await import(pathToFileURL(entry).href);
} catch (error) {
  console.error(JSON.stringify({ ok: false, error: { code: "HOST_IO", message: error.message } }));
  process.exitCode = 2;
}
