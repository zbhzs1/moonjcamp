# Bounded NMR NTUPLES Profile

## Release Status

The published Mooncakes package 0.2.0 does not include this feature. It is
implemented in the current GitHub source as a 0.3.0 candidate; the package must
be released before registry users can import these APIs. This is a constrained
interop profile, not a claim that MoonJCAMP implements all JCAMP-DX 5.00/5.01
protocols.

## Supported Shape

The profile follows the one-dimensional complex NMR FID/SPECTRUM NTUPLES and
PAGE example in the 1999 JCAMP-DX 5.01 recommendation, DOI
[10.1351/pac199971081549](https://doi.org/10.1351/pac199971081549), section 5:

- One top-level NTUPLES block with matching DATA TYPE, NTUPLES and END NTUPLES.
- DATA TYPE is NMR FID or NMR SPECTRUM. The legacy declaration 5.0 is accepted
  and normalized to 5.00 when written.
- Four variables in order: X (INDEPENDENT), R and I (DEPENDENT), N (PAGE).
- X and N use AFFN. R and I may use AFFN or ASDF; writer output keeps VAR_FORM
  synchronized with the selected encoding.
- Exactly two pages, numbered 1 and 2, mapped to R then I.
- Each page contains one XYDATA DATA TABLE using the matching
  (X++(R..R)) or (X++(I..I)) descriptor. Both pages share a finite uniform
  independent axis and equal dimensions.
- Variable names, symbols, roles, forms, dimensions, units, factors, ranges,
  page/table order and end records are checked. FIRST/LAST/MIN/MAX are checked
  against scaled values. Every real/imaginary sample must be present and finite.
- The default aggregate point budget is one million points across both pages.

The parser rejects duplicate required labels, late metadata, PAGE/table
misordering, unsupported table descriptors, mismatched dimensions or axes,
invalid page maps, stale ranges and data exceeding configured limits. The
ordinary one-dimensional spectrum API does not flatten NTUPLES into a real
spectrum.

## Explicit Limits

This is not general-purpose NTUPLES support. Arbitrary variable counts and
orders, more than two pages, other PAGE semantics, multidimensional arrays,
nonuniform axes, missing complex samples, non-XYDATA NTUPLES tables and
multiple top-level blocks are unsupported. The profile does not validate every
NMR-specific record, interpret calibration, perform Fourier transforms, or
claim full 5.00/5.01 conformance. A future 2D format requires a separately
researched and named extension profile.

The 5.01 paper itself describes a multidimensional NMR protocol as work that
had not yet been defined and tested at publication time. A project-defined 2D
layout must not be presented as official 5.01 multidimensional conformance.
JCAMP LINK compound blocks are a separate mechanism and are not PAGE arrays.

## API And Examples

Core APIs are read_ntuples, write_ntuples and rewrite_ntuples. The CLI provides
read-ntuples and rewrite-ntuples. Rewrite accepts encoding (affn, pac, sqz or
difdup) and points_per_line; it recalculates ranges, writes matching VAR_FORM
declarations, and reads the result back before returning it.

Run the bundled synthetic example with:

    moon run examples/ntuples --target js
    moon run examples/ntuples --target wasm-gc
    node bin/moonjcamp.mjs read-ntuples examples/data/complex-fid-ntuples.jdx
    node bin/moonjcamp.mjs rewrite-ntuples examples/data/complex-fid-ntuples.jdx --encoding difdup --out normalized-fid.jdx

The example is synthetic and does not represent measured chemical data.

## Reproducible Interoperability Check

The regular CI gate, node scripts/ntuple-roundtrip.mjs, uses the checked-in
synthetic FID source with four encodings and three row widths. It requires
exact page-array equality both on MoonJCAMP read-back and on independent
jcampconverter 9.0.1 reading of the normalized output. No archive download or
licensed measurement data is needed for these 12 cases.

node scripts/ntuple-archive-check.mjs fetches TESTFID.DX, TESTNTUP.DX and
BRUKNTUP.DX from IUPAC/JCAMP-DX commit
797bb84ece314a867b21d24242c1bc4c6775a251. SHA-256 is checked before use.
The source samples are retained only under ignored .interop storage and are
not included in the repository, Mooncakes package or CI artifacts.

Each sample has 16,384 points on each of two pages. MoonJCAMP rewrites all
three in AFFN, PAC, SQZ and DIF-DUP; MoonJCAMP then reads them back and compares
all page arrays, metadata shape, forms, page mapping and dimensions. The pinned
MIT jcampconverter 9.0.1 independently reads each normalized output. Its
automatic Hz-to-ppm conversion and application of the vendor $OFFSET are
explicitly reversed for axis comparison. MoonJCAMP itself preserves physical
coordinates and does not execute vendor calibration records. BRUKNTUP's
independent-reader offset before this reversal is approximately 0.00092001 Hz;
the adjustment is recorded in the report, not hidden by tolerance. The check
uses max(1e-7, abs(expected) * 1e-12) for axes and ordinates. Measured maximum
ordinate differences were 1.1921e-7 on values of order 1e9, within the relative
bound. The report records the error for each page and encoding.

The independent reader did not expose spectra for the original TESTFID and
TESTNTUP files, although it accepted MoonJCAMP's normalized output. Thus these
cases prove writer-output interoperability and MoonJCAMP source roundtrips,
not independent-reader acceptance of those unmodified originals or complete
bidirectional conformance. These three historical samples are not an official
complete conformance suite. Run the check after npm ci; CI exposes it as a
manual ntuples_archive workflow input.
