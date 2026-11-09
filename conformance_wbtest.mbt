///|
fn ir_fixture(points : Array[Point]) -> Spectrum {
  let source = synthetic(points)
  {
    ..source,
    records: [
      { label: "ORIGIN", value: "MoonJCAMP synthetic test", line: 0, },
      { label: "OWNER", value: "Synthetic data, MIT", line: 0, },
      { label: "$NOTE", value: "not measured data", line: 0, },
    ],
  }
}

///|
test "strict 424 IR export includes CORE and decodes all four encodings" {
  let source = ir_fixture(
    Array::makei(15, i => {
      x: 100.0 + i.to_double() / 2.0,
      y: Some((i - 5).to_double() / 4.0),
    }),
  )
  for encoding in [Plain, Packed, Squeezed, Difference] {
    let text = write_ir_424(source, options={
      ..WriteOptions::default(),
      encoding,
      x_factor: 0.5,
      y_factor: 0.25,
    })
    assert_true(validate_ir_424(text).valid)
    assert_true(text.contains("##JCAMP-DX=4.24\r\n"))
    assert_eq(read_spectra(text)[0].points, source.points)
    for line in text.split("\r\n") {
      assert_true(line.length() <= 80)
    }
  }
}

///|
test "DIF writer emits dedicated terminal absolute checkpoint" {
  let source = ir_fixture([
    { x: 3.0, y: Some(1.0), },
    { x: 2.0, y: Some(2.0), },
    { x: 1.0, y: Some(3.0), },
  ])
  let text = write_ir_424(source, options={
    ..WriteOptions::default(),
    encoding: Difference,
  })
  assert_true(text.contains("\r\n1 C\r\n##END="))
  assert_true(validate_ir_424(text).valid)
  let incomplete = text.replace_all(old="1 C\r\n", new="")
  assert_true(inspect(incomplete).valid)
  assert_eq(
    validate_ir_424(incomplete).diagnostics[0].code,
    "IR_FINAL_CHECKPOINT",
  )
}

///|
test "mixed ASDF ending in absolute or missing does not overlap next row" {
  let prefix = "##TITLE=Mixed\n##JCAMP-DX=4.24\n##DATA TYPE=INFRARED SPECTRUM\n##XUNITS=1/CM\n##YUNITS=ABSORBANCE\n##FIRSTX=0\n##LASTX=4\n##NPOINTS=5\n##XYDATA=(X++(Y..Y))\n"
  for ending in ["C", "?"] {
    let text = prefix + "0 AJ" + ending + "\n3 D E\n##END=\n"
    let result = read_spectra(text)[0].points
    assert_eq(result.length(), 5)
    assert_eq(result[3].y, Some(4.0))
    assert_eq(result[2].y, if ending == "?" { None } else { Some(3.0) })
  }
}

///|
test "ASDF stream accepts signed AFFN exponent tokens among coded numbers" {
  assert_eq(decode_numbers("0 1E+02A2J", mode=Asdf), [
    Some(0.0),
    Some(100.0),
    Some(12.0),
    Some(13.0),
  ])
}

///|
test "label normalization follows slashes and unnamed comment records survive" {
  assert_eq(
    canonical_label("SpecTrometer / Data-System"),
    "SPECTROMETERDATASYSTEM",
  )
  let source = ir_fixture([{ x: 1.0, y: Some(2.0), }])
  let text = write_ir_424(source).replace_all(
    old="##XUNITS=",
    new="##=comment\r\n##X/UNITS=",
  )
  assert_true(validate_ir_424(text).valid)
  assert_true(render_document(parse_document(text)).contains("##=comment"))
  assert_eq(convert_x(source, "NM").points[0].x, 10000000.0)
}

///|
test "strict IR gate distinguishes parseability from complete CORE" {
  let text = write_ir_424(ir_fixture([{ x: 1.0, y: Some(2.0), }]))
  for label in ["ORIGIN", "OWNER", "XFACTOR", "YFACTOR", "FIRSTY"] {
    let lines = text.split("\r\n").map(s => s.to_owned())
    let incomplete = lines
      .filter(s => !s.has_prefix("##" + label + "="))
      .join("\r\n")
    assert_true(inspect(incomplete).valid)
    assert_eq(
      validate_ir_424(incomplete).diagnostics[0].code,
      "IR_CORE_MISSING",
    )
  }
  assert_true(!validate_ir_424(text.replace_all(old="4.24", new="5.01")).valid)
  assert_true(!validate_ir_424(text.replace_all(old="\r\n", new="\n")).valid)
}

///|
test "strict IR gate rejects nonASCII wide lines duplicate metadata and bad extrema" {
  let text = write_ir_424(ir_fixture([{ x: 1.0, y: Some(2.0), }]))
  for
    (replacement, code) in [
      ("##$NOTE=\u00e9", "IR_ASCII"),
      ("##$NOTE=" + "a".repeat(81), "IR_LINE_WIDTH"),
      ("##$NOTE=a\r\n##$N/OTE=b", "IR_DUPLICATE"),
    ] {
    let invalid = text.replace_all(
      old="##$NOTE=not measured data",
      new=replacement,
    )
    assert_eq(validate_ir_424(invalid).diagnostics[0].code, code)
  }
  let stale = text.replace_all(old="##MAXY=2", new="##MAXY=999")
  assert_eq(validate_ir_424(stale).diagnostics[0].code, "AUDIT_DERIVED_VALUE")
}

///|
test "IR pure compound classification is explicit and never fabricated" {
  let source = ir_fixture([{ x: 1.0, y: Some(2.0), }])
  assert_eq(
    validate_ir_424(write_ir_424(source), pure_compound=true).diagnostics[0].code,
    "IR_CLASS",
  )
  let classified = {
    ..source,
    records: set_record(source.records, "CLASS", "Coblentz 3, IUPAC B"),
  }
  assert_true(
    validate_ir_424(
      write_ir_424(classified, pure_compound=true),
      pure_compound=true,
    ).valid,
  )
  let failed = try {
    ignore(write_ir_424(synthetic(source.points)))
    false
  } catch {
    Invalid(d) => d.code == "IR_CORE_MISSING"
  }
  assert_true(failed)
}

///|
test "strict explicit pairs preserve irregular descending axis" {
  let source = ir_fixture([
    { x: 100.0, y: Some(0.25), },
    { x: 80.0, y: Some(0.5), },
    { x: 30.0, y: None, },
  ])
  let text = write_ir_424(source)
  assert_true(text.contains("##XYPOINTS="))
  assert_true(validate_ir_424(text).valid)
  assert_eq(read_spectra(text)[0].points, source.points)
}

///|
test "strict exporter refuses first missing and preserves provenance across cycles" {
  let source = ir_fixture([{ x: 1.0, y: Some(2.0), }, { x: 2.0, y: None, }])
  let mut text = write_ir_424(source)
  for _ in 0..<5 {
    text = write_ir_424(read_spectra(text)[0])
    assert_eq(read_spectra(text)[0].points, source.points)
    assert_eq(
      record_value(read_spectra(text)[0].records, "OWNER"),
      Some("Synthetic data, MIT"),
    )
  }
  let invalid = { ..source, points: [{ x: 1.0, y: None, }], }
  assert_true(
    !validate_ir_424(
      write_spectrum(invalid, options={
        ..WriteOptions::default(),
        version: "4.24",
      }).replace_all(old="\n", new="\r\n"),
    ).valid,
  )
}

///|
test "nominal DELTAX does not replace endpoint-derived abscissa interval" {
  let source = ir_fixture([{ x: 1.0, y: Some(2.0), }, { x: 2.0, y: Some(3.0), }])
  let text = write_ir_424(source).replace_all(
    old="##DELTAX=1",
    new="##DELTAX=0.999",
  )
  assert_true(validate_ir_424(text).valid)
  assert_eq(read_spectra(text)[0].points, source.points)
}

///|
test "strict gate rejects invalid units and CORE record reordering" {
  let text = write_ir_424(ir_fixture([{ x: 1.0, y: Some(2.0), }]))
  let reordered = text
    .replace_all(old="##JCAMP-DX=4.24\r\n", new="")
    .replace_all(old="##XUNITS=", new="##JCAMP-DX=4.24\r\n##XUNITS=")
  assert_eq(validate_ir_424(reordered).diagnostics[0].code, "IR_VERSION_ORDER")
  assert_eq(
    validate_ir_424(text.replace_all(old="##XUNITS=1/CM", new="##XUNITS=NM")).diagnostics[0].code,
    "IR_XUNITS",
  )
  assert_eq(
    validate_ir_424(
      text.replace_all(old="##YUNITS=ABSORBANCE", new="##YUNITS=COUNTS"),
    ).diagnostics[0].code,
    "IR_YUNITS",
  )
}

///|
test "strict gate rejects wrong first ordinate and corrupt terminal checkpoint" {
  let source = ir_fixture([{ x: 1.0, y: Some(2.0), }, { x: 2.0, y: Some(3.0), }])
  let text = write_ir_424(source, options={
    ..WriteOptions::default(),
    encoding: Difference,
  })
  assert_true(
    !validate_ir_424(text.replace_all(old="##FIRSTY=2", new="##FIRSTY=9")).valid,
  )
  assert_eq(
    validate_ir_424(text.replace_all(old="2 C\r\n", new="2 D\r\n")).diagnostics[0].code,
    "Y_CHECKPOINT",
  )
}

///|
test "strict 424 reads unsigned E as SQZ rather than a vendor exponent" {
  let source = ir_fixture([
    { x: 0.0, y: Some(1.0), },
    { x: 1.0, y: Some(52.0), },
  ])
  let text = write_ir_424(source).replace_all(old="0 1 52\r\n", new="0 1E2\r\n")
  assert_true(validate_ir_424(text).valid)
  assert_eq(
    checked_ir_424(text, ParseOptions::default(), false).points,
    source.points,
  )
}
