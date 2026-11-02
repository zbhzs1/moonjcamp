///|
fn header() -> String {
  "##TITLE=Synthetic IR\n##JCAMP-DX=5.01\n##DATA TYPE=INFRARED SPECTRUM\n##XUNITS=1/CM\n##YUNITS=ABSORBANCE\n##FIRSTX=100\n##LASTX=104\n##NPOINTS=5\n##XFACTOR=1\n##YFACTOR=0.1\n"
}

///|
test "DIF rows remove checkpoints and apply physical scaling" {
  let text = header() + "##XYDATA=(X++(Y..Y))\n100 A0JT\n102 A2JT\n##END=\n"
  let result = read_spectra(text)[0]
  assert_eq(result.points.map(p => p.x), [100.0, 101.0, 102.0, 103.0, 104.0])
  assert_true(close(result.points[4].y.unwrap(), 1.4, ParseOptions::default()))
  assert_eq(inspect(text).points, 5)
}

///|
test "DIF checkpoint corruption is a hard error with physical line" {
  let text = header() + "##XYDATA=(X++(Y..Y))\n100 A0JT\n102 A3JT\n##END=\n"
  let report = inspect(text)
  assert_true(!report.valid)
  assert_eq(report.diagnostics[0].code, "Y_CHECKPOINT")
  assert_eq(report.diagnostics[0].line, 13)
}

///|
test "AFFN rows do not remove real samples as checkpoints" {
  let text = header() + "##XYDATA=(X++(Y..Y))\n100 10 11 12\n103 13 14\n##END=\n"
  assert_eq(read_spectra(text)[0].points.length(), 5)
}

///|
test "explicit pairs support irregular descending axes and missing ordinates" {
  let text = "##TITLE=Pairs\n##JCAMP-DX=4.24\n##DATA TYPE=RAMAN SPECTRUM\n##XUNITS=1/CM\n##YUNITS=COUNTS\n##NPOINTS=3\n##XFACTOR=0.5\n##YFACTOR=2\n##XYPOINTS=(XY..XY)\n20,1; 13,?; 4,-3\n##END=\n"
  let points = read_spectra(text)[0].points
  assert_eq(points, [{x: 10.0, y: Some(2.0)}, {x: 6.5, y: None}, {x: 2.0, y: Some(-6.0)}])
}

///|
test "semantic header count scaling and unsupported tables fail closed" {
  let valid = header() + "##XYDATA=(X++(Y..Y))\n100 10 11 12 13 14\n##END="
  for input in [valid.replace_all(old="NPOINTS=5", new="NPOINTS=4"), valid.replace_all(old="YFACTOR=0.1", new="YFACTOR=0"), valid.replace_all(old="100 10", new="99 10"), valid.replace_all(old="##XYDATA=", new="##DATATABLE="), valid.replace_all(old="##NPOINTS=5", new="##NPOINTS=5\n##NPOINTS=5")] {
    assert_true(!inspect(input).valid)
  }
}

///|
test "single point spectra and aggregate LINK point budget are checked" {
  let child = "##TITLE=One\n##JCAMP-DX=5.01\n##DATA TYPE=UV/VIS SPECTRUM\n##XUNITS=NM\n##YUNITS=ABSORBANCE\n##FIRSTX=1\n##LASTX=1\n##NPOINTS=1\n##XYDATA=(X++(Y..Y))\n1 2\n##END=\n"
  let options = { ..ParseOptions::default(), limits: { ..Limits::default(), max_points: 1 } }
  assert_eq(read_spectra(child, options~)[0].points.length(), 1)
  let compound = "##TITLE=Set\n##JCAMP-DX=5.01\n##DATA TYPE=LINK\n##BLOCKS=2\n" + child + child + "##END=\n"
  assert_eq(read_spectra(compound).length(), 2)
  assert_true(!inspect(compound, options~).valid)
}
