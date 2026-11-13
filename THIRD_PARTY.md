# Standards, References And Data

## Standard

The exact publication versions, sections reviewed, source URLs and SHA-256
identifiers are recorded in [docs/conformance.md](docs/conformance.md).
Primary sources: McDonald/Wilks 1988, DOI 10.1366/0003702884428734;
IUPAC 1991 recommendations, DOI 10.1351/pac199163121781;
IUPAC 5.01 extension, DOI 10.1351/pac199971081549 (copyright 1999 IUPAC).
The publications are referenced, not relicensed or redistributed as MIT assets.

- IUPAC JCAMP-DX archive: https://github.com/IUPAC/JCAMP-DX
- Standard landing page: https://iupac.org/what-we-do/digital-standards/JCAMP-DX

The official archive identifies JCAMP-DX as an existing IUPAC spectral data
exchange format. Its test-data directory includes historical copyright
notices. Public availability does not make those datasets MIT licensed.
External archive data is fetched only during optional interoperability checks,
not included in this source package or counted as project code.
The NTUPLES check fetches TESTFID.DX, TESTNTUP.DX and BRUKNTUP.DX from the
pinned IUPAC archive revision and verifies SHA-256, subject to the same data
restrictions. See docs/ntuples.md for numerical comparisons and reader limits.

## Independent Reference

- Python jcamp: https://github.com/nzhagen/jcamp
- Pinned reference commit: 9a4af7d3f0cf6aa8d27913426334dec1f5b06130
- Reference code license: MIT, see upstream LICENSE.rst.

The reference runs as a separate test tool. Its Python implementation is not
embedded in, translated line-by-line into, or required at runtime by MoonJCAMP.
Standard token tables and observable file behavior inform compatibility tests.
No license for upstream third-party spectral samples is inferred from the
reference code's MIT license.

Additional test-only tools, pinned with transitive integrity values in
`package-lock.json`:

- convert-to-jcamp 7.0.2, MIT: https://github.com/cheminfo/convert-to-jcamp
- jcampconverter 9.0.1, MIT: https://www.npmjs.com/package/jcampconverter/v/9.0.1

The newer jcampconverter 12.5.11 uses CC-BY-NC-SA-4.0 and is **not** the version
used or included here. No JavaScript reference source is embedded in the MoonBit
implementation. Test packages retain their own licenses and are excluded from
the Mooncakes runtime library; a development install does not relicense them.

Java reference project https://github.com/fracpete/jcamp-dx was identified
during research. Its implementation is not included or used as product code.

## Project Data

Checked-in fixtures are synthetic spectra created for this project and are
covered by the repository MIT license. They are not real measurements or
evidence of chemical identification accuracy.

Development is AI-assisted. The repository owner is responsible for reviewing,
understanding and maintaining the implementation and competition materials.
