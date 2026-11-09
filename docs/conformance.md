# Standard Target And Interoperability

## Exact Delivery Target

MoonJCAMP 0.2 targets **JCAMP-DX 4.24 simple infrared spectrum exchange**:
the CORE records and all numerical forms required to reconstruct a single
real infrared spectrum, including uniformly sampled XYDATA and irregular
XYPOINTS. The basis is McDonald and Wilks, *Applied Spectroscopy* 42 (1988),
151-162, DOI [10.1366/0003702884428734](https://doi.org/10.1366/0003702884428734),
especially scope 2.3.1-2.3.4, Tables IIa/VII and sections 3-7.
The IUPAC 1991 recommendations are DOI
[10.1351/pac199163121781](https://doi.org/10.1351/pac199163121781).

This is a specific published standard and application, not a promise to implement
every datatype in the JCAMP family. Infrared interferograms, transformed-domain
RADATA, arbitrary peak-assignment strings, complex/FID/NTUPLES NMR, and chemical
structure records are separate application/extension work. They are not silently
interpreted as complete IR spectra. Existing peak-pair and LINK support is an
additional compatibility surface, not part of the simple-spectrum target.

The general reader also accepts 5.00/5.01 declarations. Their declaration alone
does **not** imply conformance to their entire NMR or mass-spectrometry protocols.
The 5.01 paper explicitly adds to the original protocols (section 2.1); its
generic IUPAC NAME, LONG DATE and AUDIT TRAIL records are optional (section 3).
They are retained as descriptive metadata, not certified timestamps or signatures.
See DOI [10.1351/pac199971081549](https://doi.org/10.1351/pac199971081549).

## Executable Acceptance Matrix

`validate_ir_424` / CLI `validate-ir` enforce the target. `inspect` is the broader
compatibility parser and must not be used as a substitute conformance claim.

| Standard requirement | Implemented behavior | Reproduction |
| --- | --- | --- |
| 3.2, 6.1: simple block, TITLE first, version second, one END | One simple IR spectrum; named LDR uniqueness; reject wrong version/type/order | `conformance_wbtest.mbt` |
| Table IIa, 6.2, 7.1: complete CORE | Nonempty ORIGIN/OWNER, units, factors, endpoints, FIRSTY, NPOINTS; no fabricated owner | Missing-field, provenance and endpoint tests |
| 7.1.1: CLASS for pure compounds | Caller supplies `pure_compound=true`; missing CLASS fails, classification accuracy remains the caller's responsibility | Pure-compound test; protocol `validate-ir` |
| 4.1, 4.3: printable ASCII, <=80 characters, CRLF | Strict input checks; strict writer reduces numeric row width or refuses unrepresentable metadata | ASCII/width/line-ending tests |
| 4.4, 7.5.1: label normalization, unnamed comments | Ignore label case/spaces/hyphens/slashes/underscores; retain `##=` notes | Slash/comment roundtrip regression |
| 4.5.3, 5.3-5.10: AFFN/PAC/SQZ/DIF/DUP and `?` | Mixed decoding, signed exponents, missing-value reset, bounded DUP expansion | `numeric_wbtest.mbt`, mixed-ASDF tests |
| 5.8: X and Y checkpoints | Repeat terminal Y only when the preceding row ends with DIF (or DIF-DUP); require final absolute checkpoint | Mixed-ending and corrupt/final-checkpoint tests |
| 5.1.1, 6.2.5, 6.4.1: scaled uniform axis | Reconstruct interval from FIRSTX/LASTX/NPOINTS, not nominal DELTAX; accept either axis order | Scaling/nominal-DELTAX tests and cross-tool cases |
| 6.4.1: first ordinate must be valid | Reject strict output/input beginning with missing Y, without cropping silently | First-missing test |
| 6.4.2: irregular XYPOINTS | Complete AFFN pairs, retained order, no interpolation during exchange | Irregular descending pairs test |
| 2.3.4, 9.5: numerical roundtrip comparison | Repeated no-transform cycles retain decoded arrays; compare independent output numerically | Five-cycle regression and 30 external cases |

The validator reports the first failing condition with a stable diagnostic code.
It checks CORE consistency and optional declared extrema. It does not determine
chemical identity, truth of ownership, or the scientific quality of CLASS values.
Unknown descriptive NOTES are retained rather than assigned invented semantics.

The internal numerical representation is finite IEEE-754 binary64; exact coded
integers are limited to 2^53-1. Resource budgets are explicit. The default reader
tolerance is `1e-8 + 1e-6 * max(abs(a), abs(b))`; callers can supply stricter
`ParseOptions`. These limits are not unlimited-precision or vendor certification.
With the default Auto setting the strict gate uses the 4.24 ASDF interpretation:
an exponent has an explicit sign, while unsigned E/e is a SQZ pseudo-digit.
The broad compatibility reader instead permits unsigned vendor exponent forms;
this is why its automatic table inference is not a strict conformance decision.

## Unmodified Cross-Tool Exchange

Run from a clean clone after installing MoonBit and Node:

```sh
moon build --target js --release
npm ci --ignore-scripts
node scripts/roundtrip.mjs
node bin/moonjcamp.mjs validate-ir examples/roundtrip/moon-normalized.jdx
node bin/moonjcamp.mjs verify examples/roundtrip/producer-original.jdx examples/roundtrip/moon-normalized.jdx
```

The independent producer is **convert-to-jcamp 7.0.2 (MIT)**; the independent
reader is **jcampconverter 9.0.1 (MIT)**. The latter is deliberately pinned to
the MIT release, not the newer noncommercial-licensed release. `package-lock.json`
pins the complete test dependency graph and npm integrity values. Neither tool
is included in, translated into, or required at runtime by the MoonBit library.

The 30 automated cases include:

- 16 producer -> MoonBit -> independent reader exchanges: four encodings,
  ascending/descending axes, integer/fractional amplitudes.
- 2 additional exchanges with **both XFACTOR and YFACTOR different from one**.
- 12 MoonBit -> independent reader -> independent producer -> MoonBit cycles:
  four encodings at three row widths, descending axes, exact integer data.

All input text is passed **unchanged**, including third-party LF endings and
longer rows. Those files pass the compatibility reader, not the strict gate.
MoonBit's normalized export passes the strict 4.24 gate before independent reading.
Source arrays, decoded arrays, factors, point counts, titles, units and tolerances
are checked. There is no experimental calibration or chemical assertion.

`examples/roundtrip/producer-original.jdx` and `moon-normalized.jdx` are checked-in,
synthetic representative inputs/outputs, with hashes and expected points in
`expected.json`. The script checks that these exact bytes still match reproduction;
`.gitattributes` prevents newline rewriting of the `.jdx` examples on Windows.
The full run produces `evidence/generated/roundtrip.json` and per-case files.
CI publishes the JSON evidence for both Linux and Windows.

The independent producer's auto-factor selection quantizes fractional values.
Its difference from the requested array is bounded separately by `abs(YFACTOR)/2`
plus `1e-12`; MoonBit's output is compared to the already decoded array with
`1e-12` ordinate tolerance. This does not attribute upstream rounding to MoonBit
or label quantized input as mathematically lossless. Optional explicit producer
factors are not requested because that release duplicates their header labels;
no emitted text is repaired to make a test pass.

The older Python test has disclosed header adaptation and remains a **separate**
limited test. Seven historical IUPAC samples remain useful compatibility evidence,
not proof of strict conformance for all historical instrument files.

## Standard Source Audit

On 2026-11-09, the original 12-page IR paper and corrected 8-page 5.01 paper
were retrieved and read from the legacy JCAMP site's public protocol directory:
`http://www.jcamp-dx.org/protocols/dxir01.pdf` and
`http://www.jcamp-dx.org/protocols/dx5-01-correctedv2.pdf`.
The site's HTTPS requests failed; the HTTP copies are not authenticated downloads.
Their publication titles/authors/DOIs were cross-checked against bibliographic
records. Local SHA-256 values identify the exact copies reviewed, not an
officially signed standard:

- IR: `a7adeb78a0a1fad646dcd39521d8348eb91a6f502507ff268f91b1958807b92d`
- 5.01: `ae776f60f3bf4e64146c52e5e4865b374839d18c9e8c103ca1e9a6dccd0f19f1`

The papers and third-party historical measurements are not redistributed under
this project's MIT license. Standards implementation is not IUPAC endorsement.
