///|
fn main raise {
  let source = "##TITLE=Synthetic complex NMR FID\n" +
    "##JCAMP-DX=5.01\n" +
    "##DATA TYPE=NMR FID\n" +
    "##DATA CLASS=NTUPLES\n" +
    "##ORIGIN=MoonJCAMP synthetic example\n" +
    "##OWNER=Project example data\n" +
    "##NTUPLES=NMR FID\n" +
    "##VAR_NAME=TIME,FID/REAL,FID/IMAG,PAGE NUMBER\n" +
    "##SYMBOL=X,R,I,N\n" +
    "##VAR_TYPE=INDEPENDENT,DEPENDENT,DEPENDENT,PAGE\n" +
    "##VAR_FORM=AFFN,ASDF,ASDF,AFFN\n" +
    "##VAR_DIM=4,4,4,2\n" +
    "##UNITS=SECONDS,ARBITRARY UNITS,ARBITRARY UNITS,\n" +
    "##FIRST=0,1,10,1\n" +
    "##LAST=3,4,40,2\n" +
    "##MIN=0,1,10,1\n" +
    "##MAX=3,4,40,2\n" +
    "##FACTOR=1,1,1,1\n" +
    "##PAGE=N=1\n" +
    "##DATA TABLE=(X++(R..R)), XYDATA\n" +
    "0 1 2 3 4\n" +
    "##PAGE=N=2\n" +
    "##DATA TABLE=(X++(I..I)), XYDATA\n" +
    "0 10 20 30 40\n" +
    "##END NTUPLES=NMR FID\n" +
    "##END=\n"
  let dataset = @jcamp.read_ntuples(source)
  assert_true(dataset.pages.length() == 2)
  let rewritten = @jcamp.rewrite_ntuples(source, write_options={
    ..@jcamp.NtupleWriteOptions::default(),
    encoding: @jcamp.Difference,
  })
  let result = @jcamp.read_ntuples(rewritten)
  assert_true(result.pages == dataset.pages)
  assert_true(result.variables[1].form == "ASDF")
  println(
    "5.01 complex NMR FID: 2 typed pages, 4 points each, roundtrip passed",
  )
}
