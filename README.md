# MoonJCAMP

JCAMP-DX spectral data interchange and validation in MoonBit.

This repository is under active development toward its first release. The
declared compatibility profile is in [docs/profile.md](docs/profile.md).
Features are only release-supported after their tests and interoperability
checks pass. It is not a complete NMR processing or substance-identification
system.

## Development

MoonBit compiler 0.10.16 or later is required. The core uses only MoonBit's
standard library. Node.js is the filesystem adapter for the portable CLI;
Python is used only by independent tests.

```sh
moon check --target js --deny-warn
moon test --target js
moon test --target wasm-gc
moon build --target js
```

## Scope And Sources

The central task is standard file interchange: labels, data tables, compressed
numeric streams, compound documents, and explicit diagnostics. General FFT,
optical simulation, resampling, CSV conversion, and CLI wrappers are not claimed
as novel algorithms. See [docs/related.md](docs/related.md).

MIT licensed. Normative sources, reference tools and external-data restrictions
are listed in [THIRD_PARTY.md](THIRD_PARTY.md).
