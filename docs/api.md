# API Contracts

The generated `pkg.generated.mbti` is the authoritative list of public types
and signatures. The standard-library-only core works without Node or Python.

## Models And Errors

`Document` contains top-level `Block` objects. A block has ordered label
records, numeric tables and nested blocks. `Spectrum` contains physical X/Y
points after factors have been applied, descriptive records, title and units.
`Point.y = None` means missing, never zero. A spectrum must be nonempty and
bounded; all present numeric values must be finite binary64 numbers.

`Invalid(Diagnostic)` carries severity, code, message, line and column. Text
positions are 1-based; zero denotes constructed data. Semantic errors use the
relevant record/table/row position, not necessarily the precise offending byte.
Resource limits are per document or explicitly aggregate for batches.

## Reading And Writing

`parse_document` retains structure; `spectra_from_document` interprets the
supported profile. `read_spectra` performs both. `inspect` returns the first
structural/numerical failure as a report. `audit` additionally collects optional
metadata inconsistencies; it does not certify measurement accuracy.

`write_spectrum` and `write_collection` default to version 5.01 and recompute
axis/extrema fields. `WriteOptions` controls table shape, encoding, row width
and factors. SQZ/DIF require factors that represent ordinates as integers
without material rounding; they fail rather than silently quantizing.
`render_document` preserves raw supported table data, while `rewrite_document`
re-encodes it. These are not byte-exact archival operations.

`split_document` and `combine_documents` preserve nested metadata; `read_options`
can be supplied for ambiguous legacy number streams. Split provenance uses a
reserved private label and refuses collisions rather than overwriting it.

## Exchange And Transformations

`export_json` / `import_json` use `moonjcamp/spectra/1`. Every exported point
has numeric x and numeric-or-null y. `parse_interchange` rejects duplicate keys,
unknown fields, invalid schemas and aggregate point-budget overflow.
Do not substitute compiler-derived serialization for this versioned contract.

`export_csv` returns `CsvBundle { csv, metadata }`; `import_csv` requires both.
The CSV header is exactly x,y, empty Y means missing, quoted fields follow
CSV escaping, and malformed/ragged input is rejected. No spreadsheet formulas
are emitted because table cells are numeric only; descriptive text is JSON.

`crop` is inclusive and keeps measured order. `resample` performs linear
interpolation with explicit start/end/count and never extrapolates. `convert_x`
and `convert_y` accept only the units in profile.md. Operations return new
points/records and append bounded provenance. `edit_metadata` accepts Set/Remove
edits, protects structural/scaling/unit/history fields, and normalizes a checked
new spectrum. It does not mutate the source.

`summarize` applies `QualityPolicy` to one spectrum. `inspect_batch` records
file-local failures while bounding total input text/points. Default policy
requires >=2 points, strictly monotone axes and <=10% missing values; uniform
sampling is optional. A failed batch result is not a successful admission.

`compare_spectra` / `compare_documents` compare ordered spectra/points, title,
type, unit labels and missingness under explicit numerical tolerances. Optional
descriptive-record comparison preserves order. No implicit unit conversion or
title-based realignment occurs. Reports cap stored diagnostics while counting
all mismatches; spectrum/point indices are zero-based, -1 means not applicable.

## Request Protocol

The executable exposes `protocol(text)` and `handle_request(Json)`. Successful
responses have `ok: true, value: ...`; rejected requests have `ok: false, error`.
Accepted operations: read, inspect, audit, summary, batch, write, from-json,
rewrite, split, combine, to-csv, from-csv, transform and verify.

```json
{"operation":"transform","text":"...JCAMP...","actions":[{"operation":"crop","minimum":1000,"maximum":2000}]}
```

`read_options` accepts numeric_mode, max_points, relative_tolerance and
absolute_tolerance. `write_options` accepts encoding, table, points_per_line,
x_factor and y_factor. Summary/batch accept a `policy` object. Library-only
AuditPolicy controls stricter provenance and audit limits.

Transform actions: crop, resample, convert-x, convert-y, edit-metadata. The last
uses `edits: [{"action":"set","label":"OWNER","value":"..."}]` or remove.
`actions_text` / `metadata_text` can replace the corresponding parsed JSON
field, but cannot coexist with it. Nested JSON also rejects duplicate keys.
Protocol stdin is read incrementally with a byte budget before decoding UTF-8.
## Strict IR Exchange (0.2)

`validate_ir_424(text, options~, pure_compound~)` returns `Report` without raising.
It checks the explicitly documented JCAMP-DX 4.24 simple-IR CORE target; it is
not interchangeable with the tolerant `inspect` operation. A failure includes
the first failing diagnostic and source line. `pure_compound=true` additionally
requires a supplied CLASS record.

`write_ir_424(spectrum, options~, pure_compound~)` raises `JcampError` on missing
CORE provenance, unsupported units, invalid first data, or metadata that cannot
fit printable ASCII/80-column lines. It sets version 4.24, narrows numerical
rows when needed, emits CRLF, validates its own output, and never manufactures
an owner or changes the measured interval. General `WriteOptions.version`
accepts 4.24, 5.00 or 5.01; its default remains 5.01 for compatibility.

Protocol operations: `validate-ir` accepts `text`, optional `read_options` and
`pure_compound`; `write-ir` accepts a structured `spectrum`, optional
`write_options` and `pure_compound`; `export-ir` accepts an existing compatible
single-spectrum `text` and normalizes it strictly. CLI file commands are
`validate-ir INPUT` and `export-ir INPUT [--encoding ...] [--out FILE]`.
All use the existing result envelope and nonzero failure exit conventions.

See [conformance.md](conformance.md) for units, limits, the standard matrix,
and raw cross-tool examples. The broader API above remains supported.
