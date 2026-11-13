///|
fn complex_ntuple_fixture() -> String {
  "##TITLE=Synthetic complex FID\n" +
  "##JCAMP-DX=5.01\n" +
  "##DATA TYPE=NMR FID\n" +
  "##DATA CLASS=NTUPLES\n" +
  "##ORIGIN=MoonJCAMP test\n" +
  "##NTUPLES=NMR FID\n" +
  "##VAR_NAME=TIME,FID/REAL,FID/IMAG,PAGE NUMBER\n" +
  "##SYMBOL=X,R,I,N\n" +
  "##VAR_TYPE=INDEPENDENT,DEPENDENT,DEPENDENT,PAGE\n" +
  "##VAR_FORM=AFFN,ASDF,ASDF,AFFN\n" +
  "##VAR_DIM=4,4,4,2\n" +
  "##UNITS=SECONDS,ARBITRARY UNITS,ARBITRARY UNITS, \n" +
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
}

///|
test "5.01 FID NTUPLES retains typed real and imaginary PAGE arrays" {
  let dataset = read_ntuples(complex_ntuple_fixture())
  assert_eq(dataset.version, "5.01")
  assert_eq(dataset.data_type, "NMR FID")
  assert_eq(dataset.variables.length(), 4)
  assert_eq(dataset.pages.map(page => page.number), [1, 2])
  assert_eq(dataset.pages.map(page => page.variable_symbol), ["R", "I"])
  assert_eq(dataset.pages[0].points.map(point => point.y), [
    Some(1.0),
    Some(2.0),
    Some(3.0),
    Some(4.0),
  ])
  assert_eq(dataset.pages[1].points.map(point => point.y), [
    Some(10.0),
    Some(20.0),
    Some(30.0),
    Some(40.0),
  ])
}

///|
test "NTUPLES page writer preserves all arrays and validates re-read" {
  let dataset = read_ntuples(complex_ntuple_fixture())
  let output = write_ntuples(dataset)
  assert_true(output.contains("##DATA TABLE=(X++(R..R)), XYDATA\n"))
  assert_true(output.contains("##DATA TABLE=(X++(I..I)), XYDATA\n"))
  assert_eq(read_ntuples(output).pages, dataset.pages)
  assert_eq(
    read_ntuples(rewrite_ntuples(complex_ntuple_fixture())).pages,
    dataset.pages,
  )
}

///|
test "NTUPLES writer supports each declared encoding and canonicalizes 5.0" {
  let source = complex_ntuple_fixture().replace_all(old="5.01", new="5.0")
  let dataset = read_ntuples(source)
  assert_eq(dataset.version, "5.00")
  for encoding in [Plain, Packed, Squeezed, Difference] {
    let output = write_ntuples(dataset, options={
      encoding,
      points_per_line: 3,
    })
    assert_true(output.contains("##JCAMP-DX=5.00\n"))
    let decoded = read_ntuples(output)
    assert_eq(decoded.pages, dataset.pages)
    let dependent_form = if encoding == Plain { "AFFN" } else { "ASDF" }
    assert_eq(decoded.variables[1].form, dependent_form)
    assert_eq(decoded.variables[2].form, dependent_form)
  }
}

///|
test "NTUPLES validates table order, core label uniqueness and total point budget" {
  let valid = complex_ntuple_fixture()
  let table_before_page = valid
    .replace_all(old="##PAGE=N=1\n", new="")
    .replace_all(
      old="0 1 2 3 4\n##PAGE=N=2",
      new="0 1 2 3 4\n##PAGE=N=1\n##PAGE=N=2",
    )
  let end_before_table = valid
    .replace_all(old="##END NTUPLES=NMR FID\n", new="")
    .replace_all(old="##PAGE=N=2\n", new="##END NTUPLES=NMR FID\n##PAGE=N=2\n")
  let duplicate_type = valid.replace_all(
    old="##DATA TYPE=NMR FID\n",
    new="##DATA TYPE=NMR FID\n##DATA TYPE=NMR FID\n",
  )
  for text in [table_before_page, end_before_table, duplicate_type] {
    let rejected = try {
      ignore(read_ntuples(text))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
  let limited = try {
    ignore(
      read_ntuples(valid, options={
        ..ParseOptions::default(),
        limits: { ..Limits::default(), max_points: 7, },
      }),
    )
    false
  } catch {
    Invalid(_) => true
  }
  assert_true(limited)
}

///|
test "NTUPLES writer rejects missing complex samples and updates TITLE" {
  let dataset = read_ntuples(complex_ntuple_fixture())
  let points = dataset.pages[0].points.copy()
  points[0] = { ..points[0], y: None, }
  let incomplete = {
    ..dataset,
    pages: [{ ..dataset.pages[0], points, }, dataset.pages[1]],
  }
  let rejected = try {
    ignore(write_ntuples(incomplete))
    false
  } catch {
    Invalid(_) => true
  }
  assert_true(rejected)
  let renamed = write_ntuples({ ..dataset, title: "Renamed complex FID", })
  assert_true(renamed.has_prefix("##TITLE=Renamed complex FID\n"))
}

///|
test "NTUPLES rejects malformed dimensions page order and variable shape" {
  let valid = complex_ntuple_fixture()
  let cases = [
    valid.replace_all(old="##VAR_DIM=4,4,4,2", new="##VAR_DIM=4,3,4,2"),
    valid.replace_all(old="##PAGE=N=2", new="##PAGE=N=3"),
    valid.replace_all(
      old="##DATA TABLE=(X++(I..I))",
      new="##DATA TABLE=(X++(R..R))",
    ),
    valid.replace_all(
      old="##VAR_TYPE=INDEPENDENT,DEPENDENT,DEPENDENT,PAGE",
      new="##VAR_TYPE=INDEPENDENT,DEPENDENT,PAGE,DEPENDENT",
    ),
  ]
  for text in cases {
    let rejected = try {
      ignore(read_ntuples(text))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
}

///|
test "ordinary spectrum reader does not silently flatten NTUPLES" {
  let result = inspect(complex_ntuple_fixture())
  assert_true(!result.valid)
  assert_eq(result.diagnostics[0].code, "UNSUPPORTED_TABLE")
}

///|
test "NTUPLES roundtrips fractional scales descending axis and quoted variable names" {
  let dataset = read_ntuples(complex_ntuple_fixture())
  let variables = dataset.variables.copy()
  variables[0] = { ..variables[0], factor: 0.5, }
  variables[1] = { ..variables[1], factor: 0.25, name: "FID, REAL", }
  variables[2] = { ..variables[2], factor: 0.5, }
  let real = dataset.pages[0].points.mapi((i, _) => {
    x: 3.0 - i.to_double() * 0.5,
    y: Some((i + 1).to_double() * 0.25),
  })
  let imaginary = dataset.pages[1].points.mapi((i, _) => {
    x: 3.0 - i.to_double() * 0.5,
    y: Some((i + 1).to_double() * 0.5),
  })
  let input = {
    ..dataset,
    variables,
    pages: [
      { ..dataset.pages[0], points: real, },
      { ..dataset.pages[1], points: imaginary, },
    ],
  }
  for encoding in [Plain, Packed, Squeezed, Difference] {
    for width in [1, 2, 8] {
      let output = write_ntuples(input, options={
        encoding,
        points_per_line: width,
      })
      let decoded = read_ntuples(output)
      assert_eq(decoded.pages, input.pages)
      assert_eq(decoded.variables[1].name, "FID, REAL")
      assert_eq(decoded.variables[0].first, 3.0)
      assert_eq(decoded.variables[0].last, 1.5)
    }
  }
}

///|
test "NTUPLES rejects unsafe constructed writes and invalid options" {
  let dataset = read_ntuples(complex_ntuple_fixture())
  for title in ["", "Injected\n##END="] {
    let rejected = try {
      ignore(write_ntuples({ ..dataset, title, }))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
  for width in [0, 1025] {
    let rejected = try {
      ignore(
        write_ntuples(dataset, options={
          ..NtupleWriteOptions::default(),
          points_per_line: width,
        }),
      )
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
  let rejected = try {
    ignore(
      read_ntuples(complex_ntuple_fixture(), options={
        ..ParseOptions::default(),
        limits: { ..Limits::default(), max_points: -1, },
      }),
    )
    false
  } catch {
    Invalid(_) => true
  }
  assert_true(rejected)
}

///|
test "ordinary spectrum API rejects orphan PAGE records" {
  let file = "##TITLE=Orphan page\n##JCAMP-DX=5.01\n" +
    "##DATA TYPE=NMR SPECTRUM\n##PAGE=N=1\n" +
    "##XUNITS=HZ\n##YUNITS=ARBITRARY UNITS\n" +
    "##NPOINTS=2\n##XYPOINTS=(XY..XY)\n0 1 1 2\n##END=\n"
  assert_true(!inspect(file).valid)
}
