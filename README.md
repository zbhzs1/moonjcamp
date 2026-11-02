# MoonJCAMP

JCAMP-DX spectral data interchange and validation in MoonBit.

MoonJCAMP 0.1.0 reads, checks and rewrites one-dimensional real spectra. It
implements JCAMP-DX label records, scaled XYDATA and explicit pairs,
AFFN/PAC/SQZ/DIF/DUP numbers, DIF checkpoints, and nested LINK documents.
It includes metadata audits, compound split/combine, versioned JSON and CSV
exchange, bounded transformations, quality admission and semantic comparison.

This is a scoped implementation, not complete JCAMP-DX certification, an
instrument driver, a full NMR processor or a chemical-identification system.
See the [compatibility profile](docs/profile.md) and [related work](docs/related.md).

## Install And Use

Requires MoonBit compiler 0.10.16 or newer. The core has no third-party runtime
dependencies and is tested on JavaScript and wasm-gc. The filesystem CLI also
requires Node.js 24. Python/NumPy are test-only dependencies.

```sh
moon add zbhzs1/moonjcamp@0.1.0
```

Add `"zbhzs1/moonjcamp" @jcamp` to your package's import block in `moon.pkg`.
The [runnable MoonBit example](examples/basic/main.mbt) demonstrates reading,
cropping, writing and checking a spectrum:

```moonbit
let spectra = @jcamp.read_spectra(text)
let selected = @jcamp.crop(spectra[0], 1001.0, 1002.0)
let output = @jcamp.write_spectrum(selected)
```

These functions raise `@jcamp.JcampError`; catch `@jcamp.Invalid(diagnostic)`
to obtain its stable error code and source line. `inspect`, `audit`,
`handle_request` and `protocol` instead return diagnostic results.

For the CLI, clone this repository and build once:

```sh
git clone https://github.com/zbhzs1/moonjcamp.git
cd moonjcamp
moon build --target js --release
node bin/moonjcamp.mjs inspect examples/data/ir-compressed.jdx
node bin/moonjcamp.mjs to-json examples/data/ir-compressed.jdx --out spectrum.json
node bin/moonjcamp.mjs from-json spectrum.json --out normalized.jdx
node bin/moonjcamp.mjs verify examples/data/ir-compressed.jdx normalized.jdx
moon run examples/basic --target js
```

Outputs are created exclusively: existing files are not overwritten. Exit
codes are 0 for success, 1 for invalid data or rejected policy, and 2 for host
I/O/usage failures. A split/CSV operation can leave partial new output files
if the filesystem fails partway through; it does not provide a transaction.
`--protocol` accepts bounded UTF-8 JSON on stdin and returns one result envelope.

Three reproducible file workflows are in [docs/workflows.md](docs/workflows.md).
Public API contracts and request examples are in [docs/api.md](docs/api.md).

## Development

MoonBit compiler 0.10.16 or later is required. The core uses only MoonBit's
standard library. Node.js is the filesystem adapter for the portable CLI;
Python is used only by independent tests.

```sh
moon check --target js --deny-warn
moon test --target js
moon test --target wasm-gc
moon build --target js --release
node scripts/cli-test.mjs
python -m pip install numpy==2.4.4
python scripts/interop.py
node scripts/source-count.mjs
```

## Scope And Sources

The central task is standard file interchange: labels, data tables, compressed
numeric streams, compound documents, and explicit diagnostics. General FFT,
optical simulation, resampling, CSV conversion, and CLI wrappers are not claimed
as novel algorithms. See [docs/related.md](docs/related.md).

The CI checks formatting, strict type checking, building, JS/wasm-gc tests,
both example targets, three complete CLI workflows, and a pinned independent
Python reader/writer. Verification limits are in [docs/verification.md](docs/verification.md).

MIT licensed. Standards references, independent tools and external-data restrictions
are listed in [THIRD_PARTY.md](THIRD_PARTY.md).
