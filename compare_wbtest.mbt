///|
test "comparison verifies independent encodings and descriptive records" {
  let source = synthetic(
    Array::makei(10, i => { x: i.to_double(), y: Some(i.to_double()), }),
  )
  let plain = write_spectrum(source)
  let compressed = write_spectrum(source, options={
    ..WriteOptions::default(),
    encoding: Difference,
  })
  assert_true(
    compare_documents(plain, compressed, compare_records=true).equivalent,
  )
  let altered = { ..source, points: source.points.map(p => { ..p, y: None, }), }
  let report = compare_spectra([source], [altered], max_issues=2)
  assert_true(!report.equivalent && report.truncated)
  assert_eq(report.issue_count, 10)
  assert_eq(report.issues.length(), 2)
  assert_eq(report.issues[0].point, 0)
}

///|
test "comparison requires explicit unit conversion and respects tolerance" {
  let source = synthetic([{ x: 1000.0, y: Some(1.0), }])
  assert_true(!compare_spectra([source], [convert_x(source, "NM")]).equivalent)
  let near = { ..source, points: [{ x: 1000.0000001, y: Some(1.00000001), }], }
  assert_true(compare_spectra([source], [near]).equivalent)
  let exact = {
    ..ParseOptions::default(),
    relative_tolerance: 0.0,
    absolute_tolerance: 0.0,
  }
  assert_true(!compare_spectra([source], [near], options=exact).equivalent)
}

///|
test "table-wide ASDF inference recognizes exponent-looking terminal checkpoints" {
  let text = "##TITLE=Checkpoint\n##JCAMP-DX=5.01\n##DATA TYPE=NMR SPECTRUM\n##XUNITS=HZ\n##YUNITS=ARBITRARY\n##FIRSTX=2\n##LASTX=0\n##NPOINTS=3\n##XYDATA=(X++(Y..Y))\n2D9JJ\n0E1\n##END=\n"
  assert_eq(read_spectra(text)[0].points.map(p => p.y), [
    Some(49.0),
    Some(50.0),
    Some(51.0),
  ])
}

///|
test "a one-point pair uses one semantic point of budget" {
  let source = synthetic([{ x: 1.0, y: None, }])
  let text = write_spectrum(source, options={
    ..WriteOptions::default(),
    table_style: Pairs,
  })
  let options = {
    ..ParseOptions::default(),
    limits: { ..Limits::default(), max_points: 1, },
  }
  assert_true(inspect(text, options~).valid)
}
