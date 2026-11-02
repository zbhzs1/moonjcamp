# Version 0.1 Compatibility Profile

Status: implementation and verification in progress, not a conformance claim.

The first release targets one-dimensional real-valued JCAMP-DX spectral
interchange. Raw label/data records retain original labels and decoded values;
writing normalizes spacing and line endings, not byte-for-byte layout.

Planned release gates:

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

AFFN exponent notation and the ASDF E/e digit codes can be ambiguous in unusual
legacy files. Automatic decoding prefers syntactically complete AFFN numbers;
an explicit ASDF mode is provided for such inputs. This choice must be included
in CLI inspection output and tests. No guessed chemical meaning or physical
calibration is applied.

Default resource budgets limit text length, physical lines, line length,
records, nesting, blocks, points and numeric expansion. Errors carry a stable
code and 1-based source position; position zero means a constructed object.

Numerical transformations operate only on explicitly supported units. They
must preserve or update the corresponding axis metadata. Resampling does not
claim to increase experimental resolution.
