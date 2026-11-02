# Reproducible Workflows

Build with `moon build --target js --release` first. Run these commands in a
fresh checkout, with output names that do not already exist. All checked-in
samples are synthetic and do not identify a real chemical sample.

## Compressed Import And Normalization

```sh
node bin/moonjcamp.mjs inspect examples/data/ir-compressed.jdx
node bin/moonjcamp.mjs to-json examples/data/ir-compressed.jdx --out ir.json
node bin/moonjcamp.mjs from-json ir.json --encoding sqz --y-factor 0.1 --out ir.jdx
node bin/moonjcamp.mjs verify examples/data/ir-compressed.jdx ir.jdx
```

Expected: 9 points, no missing values, and `equivalent: true`. This path checks
DIF/DUP expansion, row checkpoints, scale factors, JSON interchange and a
different output encoding, not only a demonstration printout.

## Compound Collections And CSV

```sh
node bin/moonjcamp.mjs combine examples/data/ir-compressed.jdx examples/data/raman-pairs.jdx --out collection.jdx
node bin/moonjcamp.mjs split collection.jdx --out-dir split-spectra
node bin/moonjcamp.mjs to-csv split-spectra/spectrum-2.jdx --out raman.csv
node bin/moonjcamp.mjs from-csv raman.csv --metadata raman.csv.metadata.json --out raman.jdx
node bin/moonjcamp.mjs verify examples/data/raman-pairs.jdx raman.jdx
```

Expected: two split files, four Raman points including one missing ordinate,
and semantic equivalence. CSV alone does not carry title, units or private
records; its JSON sidecar is required for lossless semantic reconstruction.
Parent LINK descriptions are retained as `$MOONJCAMP.CONTAINERS` on split leaves.

## Transformation And Admission

```sh
node bin/moonjcamp.mjs transform examples/data/ir-compressed.jdx --actions examples/actions.json --out converted.jdx
node bin/moonjcamp.mjs summary converted.jdx
node bin/moonjcamp.mjs audit converted.jdx
node bin/moonjcamp.mjs batch examples/data/ir-compressed.jdx examples/data/raman-pairs.jdx
```

Expected: 13 converted points, X units NM, Y units %TRANSMITTANCE, and four
history steps. Audit warns about missing OWNER in these synthetic samples.
The batch command deliberately exits 1: the Raman sample's 25% missing fraction
exceeds the default 10% admission threshold even though the file parses.

`node scripts/cli-test.mjs` runs all three paths in a fresh temporary directory
and checks failures, no-overwrite behavior, duplicate JSON keys, numeric limits
and invalid UTF-8. It is the cross-platform regression test for these workflows.
