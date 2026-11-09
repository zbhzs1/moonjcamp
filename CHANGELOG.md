# Changelog

## 0.2.0

- Define the exact JCAMP-DX 4.24 simple IR spectrum CORE exchange target and
  executable standard/behavior/evidence matrix.
- Add strict `validate_ir_424`, `write_ir_424`, `validate-ir`, `export-ir` and
  a runnable pure-MoonBit IR exchange example.
- Correct DIF overlap selection, emit a final absolute checkpoint, decode
  signed AFFN exponents in ASDF streams, normalize slashes in labels, and
  preserve unnamed comment records. Treat DELTAX as nominal, not authoritative.
- Add 14 MoonBit regressions, six CLI checks, and 30 unmodified cross-tool
  roundtrips with pinned MIT tools, checked-in examples and CI evidence.
- Keep broad 5.00/5.01 compatibility separate from strict IR conformance;
  document numerical limits, producer rounding and retained Python adaptations.
- Align derive formatting with MoonBit 0.10.20; verify against the current stable
  toolchain used in Linux and Windows CI.

## 0.1.0

- Scoped 1D JCAMP-DX 4.24/5.00/5.01 reader and normalized 5.01 writer.
- Bounded AFFN/PAC/SQZ/DIF/DUP decoding and four write encodings.
- Physical factors, axis/point validation, DIF row checkpoints and missing data.
- Nested LINK document preservation, splitting, combination and rewriting.
- Versioned JSON and CSV-plus-sidecar interchange.
- Metadata audits, protected edits and bounded transformation provenance.
- Crop, monotone linear resampling and explicit spectral unit conversions.
- Quality admission, batch diagnostics and semantic equivalence reports.
- Offline CLI, pure MoonBit example and three reproducible file workflows.
- Cross-target tests, independent Python interoperability and optional pinned
  historical archive checks. Compatibility limits are explicitly documented.
