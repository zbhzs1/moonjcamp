///|
test "crop preserves missing values and removes stale derived metadata" {
  let original = synthetic([{x: 4.0,y: Some(1.0)}, {x: 3.0,y: None}, {x: 2.0,y: Some(3.0)}])
  let source = { ..original, records: set_record(original.records, "NPOINTS", "999") }
  let result = crop(source, 2.0, 3.0)
  assert_eq(result.points.length(), 2)
  assert_eq(result.points[0].y, None)
  assert_eq(record_value(result.records, "NPOINTS"), None)
  assert_eq(record_value(source.records, "NPOINTS"), Some("999"))
  assert_true(record_value(result.records, "$MOONJCAMP.HISTORY") is Some(_))
  assert_eq(read_spectra(write_spectrum(result))[0].points, result.points)
}

///|
test "resampling handles descending axes exact hits and missing intervals" {
  let source = synthetic([{x: 4.0,y: Some(8.0)}, {x: 2.0,y: Some(4.0)}, {x: 0.0,y: None}])
  let result = resample(source, 4.0, 0.0, 5)
  assert_eq(result.points.map(p => p.y), [Some(8.0),Some(6.0),Some(4.0),None,None])
  for bad in [synthetic([{x: 1.0,y: None}]), synthetic([{x: 1.0,y: None},{x: 1.0,y: None}])] {
    let failed = try { ignore(resample(bad, 0.0, 2.0, 5)); false } catch { Invalid(_) => true }
    assert_true(failed)
  }
  let failed = try { ignore(resample(source, -1.0, 4.0, 5)); false } catch { Invalid(d) => d.code == "RESAMPLE_EXTRAPOLATION" }
  assert_true(failed)
}

///|
test "explicit wavelength wavenumber and transmittance conversions" {
  let source = synthetic([{x: 1000.0, y: Some(1.0)}, {x: 2000.0, y: None}])
  let converted = convert_x(source, "NM")
  assert_eq(converted.points[0].x, 10000.0)
  assert_eq(convert_x(converted, "1/CM").points, source.points)
  let transmission = convert_y(source, "%TRANSMITTANCE")
  assert_true((transmission.points[0].y.unwrap() - 10.0).abs() < 1.0e-10)
  assert_true((convert_y(transmission, "ABSORBANCE").points[0].y.unwrap() - 1.0).abs() < 1.0e-10)
  assert_eq(transmission.points[1].y, None)
  assert_eq(read_spectra(write_spectrum(transmission))[0].y_units, "%TRANSMITTANCE")
}

///|
test "unit conversion rejects unknown calibration and invalid physical domain" {
  for source in [synthetic([{x: 0.0, y: Some(1.0)}]), synthetic([{x: -1.0, y: Some(1.0)}])] {
    let failed = try { ignore(convert_x(source, "NM")); false } catch { Invalid(d) => d.code == "UNIT_DOMAIN" }
    assert_true(failed)
  }
  let source = { ..synthetic([{x: 1.0,y: Some(0.0)}]), y_units: "TRANSMITTANCE" }
  let failed = try { ignore(convert_y(source, "ABSORBANCE")); false } catch { Invalid(d) => d.code == "UNIT_DOMAIN" }
  assert_true(failed)
}
