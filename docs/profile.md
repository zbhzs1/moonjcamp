# Version 0.2 Compatibility Profile

The standard target and executable requirements are now defined separately in
[conformance.md](conformance.md): JCAMP-DX 4.24 simple IR spectrum CORE exchange.
This page describes the broader compatibility API, not full 5.00/5.01 conformance.
See verification.md for independent test limits.

The first release targets one-dimensional real-valued JCAMP-DX spectral
interchange. Raw label/data records retain original labels and decoded values;
writing normalizes spacing and line endings, not byte-for-byte layout.

Implemented release surfaces:

| Surface | Acceptance evidence |
| --- | --- |
| TITLE, JCAMP-DX, DATA TYPE, END and label continuation | Structural and negative parser tests |
| XYDATA=(X++(Y..Y)) | Scaled X/Y arrays, point-count and row-anchor checks |
| XYPOINTS=(XY..XY) and PEAK TABLE=(XY..XY) | Explicit pairs, irregular axes and missing ordinates |
| AFFN/PAC/SQZ/DIF/DUP | Per-token fixtures, bounded expansion and independent differential tests |
| DIF row transitions | Repeated terminal Y only after a DIF-ending row; final absolute checkpoint on output |
| LINK compound blocks | Nesting, BLOCKS cardinality, split/combine and metadata preservation |
| Rewriting | Declared encoding, derived axis fields and read-back equivalence |
| File workflows | Instrument import, batch admission checks, and transformed re-export |

NTUPLES, PAGE, NMR FID components, multidimensional/complex NMR, molecular
structures, vendor-private binary payloads and measurement calibration are not
implemented by this release. Recognized out-of-profile tables must produce an
unsupported-feature error, not an apparently successful empty spectrum.
Unknown descriptive labels are retained. Source-private records are data,
never executable instructions.

## Planned Roadmap

These are proposed additions, not current API behavior or a claim of full
JCAMP-DX conformance:

1. Define separate executable conformance profiles for 4.24 simple IR, the
   5.00 NMR protocol and its 5.01 extension. Validate datatype-specific records
   rather than treating a version declaration as proof of support; preserve
   unsupported labels without assigning invented semantics.
2. Add a typed NTUPLES model for variable names, roles, forms, dimensions,
   units, factors and ranges. Parse and write the published 5.01 PAGE example
   for one-dimensional NMR FID real/imaginary components, validate page indices
   and dimensions, and prove parse-write-parse equivalence with checked-in
   fixtures and independent readers where available.
3. Survey published, interoperable multidimensional NMR conventions before
   defining a separately named extension profile. Its first bounded target is
   real-valued 2D data with explicit axis order, shape, units, factors, page
   mapping and resource limits. Include roundtrip and malformed-shape tests.

The 1999 JCAMP-DX 5.01 recommendation (DOI
[10.1351/pac199971081549](https://doi.org/10.1351/pac199971081549), sections
5-6) includes a one-dimensional NMR FID NTUPLES/PAGE example and describes a
multidimensional protocol as future work that had not yet been defined or
tested. Accordingly, a project-defined 2D profile must be labeled as an
extension, not as official 5.01 multidimensional conformance. Each milestone
will publish its supported subset, explicit rejection behavior, examples and
CI results before its scope is advertised as implemented.

AFFN exponent notation and ASDF E/e digit codes can be ambiguous in legacy
files. Automatic decoding selects ASDF for an entire table if any row needs
coded syntax; otherwise it prefers complete AFFN syntax. Standalone
decode_numbers applies this choice to its single input row. Explicit numeric
mode (CLI --numeric-mode asdf|affn, or ParseOptions) resolves fully ambiguous
tables. Automatic mode cannot infer absent format intent. No guessed chemical
meaning or physical calibration is applied.

Default resource budgets limit text length, physical lines, line length,
records, nesting, blocks, points and numeric expansion. Errors carry a stable
code and 1-based source position; position zero means a constructed object.

Numerical transformations operate only on explicitly supported units. They
must preserve or update the corresponding axis metadata. Resampling does not
claim to increase experimental resolution.

Linear interpolation requires a strictly monotone measured axis, propagates
missing intervals, refuses extrapolation and rejects collapsed binary64 grids.
X conversion supports 1/CM, NM and MICROMETERS; Y conversion supports absorbance,
fractional transmittance and percent transmittance in a conservative physical
domain. It does not infer instrument calibration from unit spelling.

Structural inspection is separate from metadata audit and admission policy.
For example, inspect can accept a parseable file with stale MAXY; audit reports
the mismatch, and summary/batch evaluate missingness and sampling policies.
Missing ORIGIN/OWNER is a warning unless a library AuditPolicy requires it.
The strict `validate_ir_424` gate requires both and complete CORE metadata;
`inspect` does not. General writers allow LF/Unicode descriptive metadata, while
`write_ir_424` requires printable ASCII and emits <=80-column CRLF lines.
Audit history is descriptive provenance, not a cryptographic signature.
