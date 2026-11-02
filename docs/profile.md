# Version 0.1 Compatibility Profile

Status: implemented and locally verified for version 0.1.0, not a complete
standards-conformance claim. See verification.md for independent test limits.

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
| DIF row transitions | Repeated terminal Y checkpoint and matching X position |
| LINK compound blocks | Nesting, BLOCKS cardinality, split/combine and metadata preservation |
| Rewriting | Declared encoding, derived axis fields and read-back equivalence |
| File workflows | Instrument import, batch admission checks, and transformed re-export |

NTUPLES, multidimensional/complex NMR, FID processing, molecular structures,
vendor-private binary payloads and measurement calibration are future work.
Recognized out-of-profile tables must produce an unsupported-feature error,
not an apparently successful empty spectrum. Unknown descriptive labels are
retained. Source-private records are data, never executable instructions.

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
Audit history is descriptive provenance, not a cryptographic signature.
