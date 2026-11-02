///|
test "CSV sidecar preserves semantic metadata and missing ordinates" {
  let source = synthetic([{x: -1.0,y: Some(0.000001)},{x: 3.0,y: None}])
  let bundle = export_csv(source)
  let result = import_csv(bundle.csv, bundle.metadata)
  assert_eq(result.points, source.points)
  assert_eq(result.records, source.records)
  assert_eq(parse_csv("\uFEFF\"x\",y\r\n\"a,\"\"b\"\"\",c\n\"line\nbreak\",d"), [["x","y"],["a,\"b\"","c"],["line\nbreak","d"]])
}

///|
test "CSV refuses malformed quoting ragged rows and nonfinite numbers" {
  for text in ["x,y\n1,2,3", "x,y\n1,NaN", "x,y\n1,\"2\"x", "x,y\n1,\"2", "x,z\n1,2", "x,y\n1,2\n\n"] {
    let metadata = export_csv(synthetic([{x: 1.0,y: Some(2.0)}])).metadata
    let failed = try { ignore(import_csv(text, metadata)); false } catch { Invalid(_) => true }
    assert_true(failed)
  }
}

///|
test "quality policy distinguishes structural validity from admission" {
  let source = synthetic([{x: 1.0,y: Some(1.0)},{x: 3.0,y: None},{x: 2.0,y: None},{x: 4.0,y: Some(3.0)}])
  let summary = summarize(source)
  assert_true(!summary.accepted)
  assert_eq(summary.missing, 2)
  assert_eq(summary.longest_missing_run, 2)
  assert_eq(summary.y_mean, Some(2.0))
  assert_eq(summary.diagnostics.map(d => d.code), ["QUALITY_MISSING","QUALITY_AXIS"])
  let permissive = { ..QualityPolicy::default(), max_missing_fraction: 1.0, require_monotone: false }
  assert_true(summarize(source, policy=permissive).accepted)
}

///|
test "batch records failures without hiding valid neighbors" {
  let good = write_spectrum(synthetic([{x: 1.0,y: Some(2.0)},{x: 2.0,y: Some(3.0)}]))
  let report = inspect_batch([{name: "good",text: good},{name: "bad",text: "not JCAMP"}])
  assert_eq(report.accepted, 1)
  assert_eq(report.rejected, 1)
  assert_eq(report.items[1].diagnostics[0].code, "LABEL_PREFIX")
  let failed = try { ignore(inspect_batch([{name: "a",text: good},{name: "a",text: good}])); false } catch { Invalid(d) => d.code == "BATCH_NAME" }
  assert_true(failed)
}
