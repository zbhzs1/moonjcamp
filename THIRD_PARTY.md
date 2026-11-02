# Standards, References And Data

## Standard

- IUPAC JCAMP-DX archive: https://github.com/IUPAC/JCAMP-DX
- Standard landing page: https://iupac.org/what-we-do/digital-standards/JCAMP-DX

The official archive identifies JCAMP-DX as an existing IUPAC spectral data
exchange format. Its test-data directory includes historical copyright
notices. Public availability does not make those datasets MIT licensed.
External archive data is fetched only during optional interoperability checks,
not included in this source package or counted as project code.

## Independent Reference

- Python jcamp: https://github.com/nzhagen/jcamp
- Pinned reference commit: 9a4af7d3f0cf6aa8d27913426334dec1f5b06130
- Reference code license: MIT, see upstream LICENSE.txt.

The reference runs as a separate test tool. Its Python implementation is not
embedded in, translated line-by-line into, or required at runtime by MoonJCAMP.
Standard token tables and observable file behavior inform compatibility tests.
No license for upstream third-party spectral samples is inferred from the
reference code's MIT license.

Java reference project https://github.com/fracpete/jcamp-dx was identified
during research. Its implementation is not included or used as product code.

## Project Data

Checked-in fixtures are synthetic spectra created for this project and are
covered by the repository MIT license. They are not real measurements or
evidence of chemical identification accuracy.

Development is AI-assisted. The repository owner is responsible for reviewing,
understanding and maintaining the implementation and competition materials.
