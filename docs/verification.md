# Verification Evidence And Limits

Local baseline: MoonBit moon 0.1.20261016 / moonc 0.10.16+b1a0e846e, Node 24,
Python 3.12 and NumPy 2.4.4. The initial suite contains 52 MoonBit tests,
executed on JS and wasm-gc, plus 23 CLI subprocess checks and three complete
workflows. CI repeats the portable checks on Linux and Windows with the
currently distributed stable MoonBit toolchain and records its exact version.

## Independent Reader And Writer

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

An additional historical BRUKER1.JCM has an empty label name on line 4 and is
rejected by this strict profile. It is not included as a passing fixture.
External data is not redistributed or uploaded as a CI artifact. Run the
optional archive gate with workflow_dispatch's external_archive input.

## Remaining Limits

After publication, `node scripts/consumer-check.mjs` creates a new module whose
only dependency is registry version zbhzs1/moonjcamp@0.1.0, runs moon update,
checks it, and executes it on JS and wasm-gc without a local path override.
Set MOON_BIN when using an isolated toolchain. The CI manual published_consumer
input enables the same registry-install check after the version is available.

This is not an official conformance suite or instrument-vendor certification.
Fully ambiguous AFFN E/exponent versus ASDF E digit tables require a caller
mode override. Legacy nonstandard headers, NTUPLES and multidimensional data
remain future compatibility work. Budgets protect ordinary offline use but
are not a sandbox or constant-memory streaming guarantee. Audit/provenance is
not cryptographic authentication. Numerical methods do not validate experimental
calibration, clinical suitability or chemical identity.
