///|
fn synthetic(points : Array[Point]) -> Spectrum {
  { title: "Synthetic", data_type: "INFRARED SPECTRUM", x_units: "1/CM", y_units: "ABSORBANCE", points, records: [{label: "$SOURCE", value: "synthetic fixture", line: 0}], source_line: 0 }
}

///|
test "all encoders roundtrip regular spectra across short rows" {
  let source = synthetic([{x: 10.0, y: Some(0.0)}, {x: 11.0, y: Some(1.0)}, {x: 12.0, y: Some(2.0)}, {x: 13.0, y: Some(3.0)}, {x: 14.0, y: Some(5.0)}])
  for encoding in [Plain, Packed, Squeezed, Difference] {
    for width in [1, 2, 3, 8] {
      let options = { ..WriteOptions::default(), encoding, points_per_line: width }
      let output = write_spectrum(source, options~)
      let result = read_spectra(output)[0]
      assert_eq(result.points, source.points)
      assert_eq(record_value(result.records, "$SOURCE"), Some("synthetic fixture"))
    }
  }
}

///|
test "writer selects explicit pairs for an irregular axis" {
  let source = synthetic([{x: 1.0, y: Some(2.0)}, {x: 3.0, y: None}, {x: 10.0, y: Some(-3.0)}])
  let output = write_spectrum(source)
  assert_true(output.contains("##XYPOINTS="))
  assert_eq(read_spectra(output)[0].points, source.points)
}

///|
test "DIF missing values reset delta anchors without losing points" {
  let source = synthetic(Array::makei(9, i => {x: i.to_double(), y: if i == 2 || i == 3 || i == 6 { None } else { Some(i.to_double()) }}))
  for width in [1, 2, 3, 4] {
    let options = { ..WriteOptions::default(), encoding: Difference, points_per_line: width }
    assert_eq(read_spectra(write_spectrum(source, options~))[0].points, source.points)
  }
}

///|
test "ASDF scaling is explicit and rejects material quantization" {
  let source = synthetic([{x: 1.0, y: Some(0.25)}, {x: 2.0, y: Some(-0.5)}])
  let options = { ..WriteOptions::default(), encoding: Squeezed, y_factor: 0.25 }
  assert_eq(read_spectra(write_spectrum(source, options~))[0].points, source.points)
  let invalid = { ..WriteOptions::default(), encoding: Squeezed }
  let failed = try { ignore(write_spectrum(source, options=invalid)); false } catch { Invalid(d) => d.code == "WRITE_ASDF_SCALE" }
  assert_true(failed)
}

///|
test "decimal serialization avoids ASDF exponent ambiguity" {
  for value in [0.00000000000000000001, 1.0e25, -1.0e25, 1.2345e-12] {
    let spelling = decimal(value)
    assert_true(!spelling.contains("e") && !spelling.contains("E"))
    assert_eq(number(spelling), value)
  }
}

///|
test "writing rejects label injection and does not mutate input metadata" {
  let source = synthetic([{x: 1.0, y: Some(2.0)}])
  let malicious = { ..source, title: "name\n##END=" }
  let failed = try { ignore(write_spectrum(malicious)); false } catch { Invalid(d) => d.code == "WRITE_INJECTION" }
  assert_true(failed)
  ignore(write_spectrum(source))
  assert_eq(source.records.length(), 1)
}
