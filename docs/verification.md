# Verification Evidence And Limits

Local baseline: MoonBit moon 0.1.20261104 / moonc 0.10.20+65efd5b93, Node 24,
Python 3.12 and NumPy 2.4.4. Published version 0.2 contains 66 MoonBit tests;
the current 0.3 candidate contains 76, executed on JS and wasm-gc, plus 32 CLI
subprocess checks and five complete workflows. CI repeats the portable checks
on Linux and Windows with the
currently distributed stable MoonBit toolchain and records its exact version.

## Independent Reader And Writer

The primary new evidence is **30 unmodified cross-tool roundtrip cases** using
the MIT releases convert-to-jcamp 7.0.2 and jcampconverter 9.0.1. See
[conformance.md](conformance.md) for the exact target, acceptance matrix,
checked-in original/normalized files, error bounds and reproduction commands.
Unlike the Python cases below, emitted input text is never repaired.

`python scripts/interop.py` fetches nzhagen/jcamp at commit
9a4af7d3f0cf6aa8d27913426334dec1f5b06130 and verifies its SHA-256 before loading it.
Sixteen cases cover MoonBit-produced AFFN/PAC/SQZ/DIF-DUP read by Python, and
Python-produced ascending/descending AFFN with two amplitude scales read by
MoonBit. No checkpoint warnings are allowed in those synthetic cases.

The reference writer places JCAMP-DX before TITLE. The test moves only TITLE
to the first record and leaves numerical payloads unchanged. It also does not
ask that writer to emit an explicit YFACTOR, because that version duplicates
the label. These are limited interoperability checks, not proof that all output
of that Python version is accepted unchanged.

## Optional Historical Archive

```sh
python scripts/archive-check.py
```

This downloads seven pinned, SHA-256-verified files from IUPAC/JCAMP-DX commit
797bb84ece314a867b21d24242c1bc4c6775a251 into ignored .interop storage. Six files
are numerically compared with Python after only removing comments and outer
whitespace from the Python input; MoonBit sees the originals. TESTSPEC's final
SQZ checkpoint crashes the reference reader. Its scaled array truncated toward
zero is instead checked exactly against archived integer BRUKDIF data.
BRUKAFFN/PAC/SQZ are also checked against each other. BRUKDIF contains different
values and is not claimed equivalent to BRUKAFFN.

The 0.1 parser rejected historical empty-name `##=` comments. Version 0.2 adds
their parsing/rendering regression test; that does not establish compatibility
with every other record in BRUKER1.JCM. This seven-file suite has not been expanded
to certify the remaining archive.
External data is not redistributed or uploaded as a CI artifact. Run the
optional archive gate with workflow_dispatch's external_archive input.

## Remaining Limits

After publication, `node scripts/consumer-check.mjs` creates a new module whose
only dependency is registry version zbhzs1/moonjcamp@0.2.0, runs moon update,
checks it, and executes it on JS and wasm-gc without a local path override.
It exercises the new strict 4.24 exporter and validator on 32 decoded points.
Set MOON_BIN when using an isolated toolchain. The CI manual published_consumer
input enables the same registry-install check after the version is available.

This is not an official conformance suite or instrument-vendor certification.
Fully ambiguous AFFN E/exponent versus ASDF E digit tables require a caller
mode override. Arbitrary NTUPLES layouts and multidimensional data remain
future compatibility work; the implemented two-page NMR profile and its
three-file/four-encoding evidence are specified in [ntuples.md](ntuples.md).
That gate uses pinned historical files and independently compares normalized
output, reversing the independent reader's Hz/ppm and vendor-offset behavior.
It is enabled separately with the ntuples_archive workflow input.
Budgets protect ordinary offline use but
are not a sandbox or constant-memory streaming guarantee. Audit/provenance is
not cryptographic authentication. Numerical methods do not validate experimental
calibration, clinical suitability or chemical identity.
