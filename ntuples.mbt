///|
fn ntuple_one_record(block : Block, label : String) -> Record raise JcampError {
  let key = canonical_label(label)
  let matches = block.records.filter(record => {
    canonical_label(record.label) == key
  })
  guard matches.length() == 1 else {
    reject(
      "NTUPLE_HEADER",
      "expected exactly one " + label + " record",
      line=block.start_line,
    )
  }
  matches[0]
}

///|
fn ntuple_fields(
  block : Block,
  label : String,
) -> Array[String] raise JcampError {
  let record = ntuple_one_record(block, label)
  let rows = parse_csv(record.value)
  guard rows.length() == 1 else {
    reject(
      "NTUPLE_CSV",
      label + " must be a single comma-separated record",
      line=record.line,
    )
  }
  rows[0].map(trim)
}

///|
fn ntuple_integer(
  text : String,
  line : Int32,
  label : String,
) -> Int32 raise JcampError {
  let value = number(text, line~)
  guard value >= 0.0 && value.floor() == value && value <= 2147483647.0 else {
    reject("NTUPLE_INTEGER", label + " must be a nonnegative integer", line~)
  }
  value.to_int()
}

///|
fn ntuple_variables(
  block : Block,
  options : ParseOptions,
) -> Array[NtupleVariable] raise JcampError {
  let names = ntuple_fields(block, "VAR_NAME")
  let symbols = ntuple_fields(block, "SYMBOL")
  let roles = ntuple_fields(block, "VAR_TYPE")
  let forms = ntuple_fields(block, "VAR_FORM")
  let dimensions = ntuple_fields(block, "VAR_DIM")
  let units = ntuple_fields(block, "UNITS")
  let first = ntuple_fields(block, "FIRST")
  let last = ntuple_fields(block, "LAST")
  let minimum = ntuple_fields(block, "MIN")
  let maximum = ntuple_fields(block, "MAX")
  let factors = ntuple_fields(block, "FACTOR")
  let count = names.length()
  guard count >= 2 && count <= 16 else {
    reject(
      "NTUPLE_VARIABLES",
      "NTUPLES must define a bounded variable list",
      line=block.start_line,
    )
  }
  for
    fields in [
      symbols, roles, forms, dimensions, units, first, last, minimum, maximum, factors,
    ] {
    guard fields.length() == count else {
      reject(
        "NTUPLE_ARITY",
        "NTUPLES variable records have different column counts",
        line=block.start_line,
      )
    }
  }
  let variables : Array[NtupleVariable] = []
  for i = 0; i < count; i = i + 1 {
    let dimension = ntuple_integer(dimensions[i], block.start_line, "VAR_DIM")
    guard dimension > 0 && dimension <= options.limits.max_points else {
      reject(
        "NTUPLE_DIMENSION",
        "VAR_DIM is outside the configured point budget",
        line=block.start_line,
      )
    }
    let factor = number(factors[i], line=block.start_line)
    guard factor != 0.0 else {
      reject("NTUPLE_FACTOR", "FACTOR must be nonzero", line=block.start_line)
    }
    variables.push({
      name: names[i],
      symbol: symbols[i],
      role: canonical_label(roles[i]),
      form: canonical_label(forms[i]),
      dimension,
      units: units[i],
      first: number(first[i], line=block.start_line),
      last: number(last[i], line=block.start_line),
      minimum: number(minimum[i], line=block.start_line),
      maximum: number(maximum[i], line=block.start_line),
      factor,
    })
  }
  variables
}

///|
fn ntuple_page_number(record : Record) -> Int32 raise JcampError {
  let value = trim(record.value)
  guard value.has_prefix("N=") else {
    reject(
      "NTUPLE_PAGE",
      "PAGE must use the N=<page-number> form",
      line=record.line,
    )
  }
  ntuple_integer(trim(value[2:].to_owned()), record.line, "PAGE")
}

///|
fn ntuple_stats(
  points : Array[Point],
  x_axis : Bool,
) -> (Double, Double, Double, Double) raise JcampError {
  guard !points.is_empty() else {
    reject("NTUPLE_RANGE", "cannot derive ranges from empty data")
  }
  let mut first = 0.0
  let mut last = 0.0
  let mut minimum = 0.0
  let mut maximum = 0.0
  let mut initialized = false
  for point in points {
    let value = if x_axis {
      point.x
    } else {
      match point.y {
        Some(y) => y
        None => continue
      }
    }
    let raw = value
    guard finite(raw) else {
      reject("NTUPLE_RANGE", "scaled NTUPLES value is not finite")
    }
    if !initialized {
      first = raw
    }
    if !initialized {
      minimum = raw
      maximum = raw
      initialized = true
    } else {
      if raw < minimum {
        minimum = raw
      }
      if raw > maximum {
        maximum = raw
      }
    }
    last = raw
  }
  guard initialized else {
    reject("NTUPLE_RANGE", "dependent NTUPLES variable contains no values")
  }
  (first, last, minimum, maximum)
}

///|
fn ntuple_validate(
  dataset : NtupleDataset,
  options : ParseOptions,
  check_ranges : Bool,
) -> Unit raise JcampError {
  guard ["5.00", "5.0", "5.01"].contains(dataset.version) else {
    reject(
      "NTUPLE_VERSION",
      "NTUPLES NMR support requires JCAMP-DX 5.00 or 5.01",
      line=dataset.source_line,
    )
  }
  let data_type = canonical_label(dataset.data_type)
  guard data_type == "NMRFID" || data_type == "NMRSPECTRUM" else {
    reject(
      "NTUPLE_TYPE",
      "this NTUPLES profile supports NMR FID and NMR SPECTRUM",
      line=dataset.source_line,
    )
  }
  guard canonical_label(dataset.ntuples_type) == data_type else {
    reject(
      "NTUPLE_TYPE",
      "NTUPLES declaration differs from DATA TYPE",
      line=dataset.source_line,
    )
  }
  guard trim(dataset.title) != "" && dataset.variables.length() == 4 else {
    reject(
      "NTUPLE_VARIABLES",
      "the supported complex NMR profile requires four variables",
      line=dataset.source_line,
    )
  }
  guard dataset.records.length() <= options.limits.max_records else {
    reject("LIMIT_RECORDS", "NTUPLES metadata exceeds the configured budget")
  }
  for variable in dataset.variables {
    guard finite(variable.first) &&
      finite(variable.last) &&
      finite(variable.minimum) &&
      finite(variable.maximum) &&
      finite(variable.factor) else {
      reject(
        "NTUPLE_METADATA",
        "variable ranges and factors must be finite",
        line=dataset.source_line,
      )
    }
    guard variable.factor != 0.0 &&
      variable.dimension > 0 &&
      variable.dimension <= options.limits.max_points else {
      reject(
        "NTUPLE_METADATA",
        "variable factors and dimensions are outside the supported range",
        line=dataset.source_line,
      )
    }
  }
  let x = dataset.variables[0]
  let real = dataset.variables[1]
  let imaginary = dataset.variables[2]
  let page = dataset.variables[3]
  guard x.role == "INDEPENDENT" &&
    real.role == "DEPENDENT" &&
    imaginary.role == "DEPENDENT" &&
    page.role == "PAGE" else {
    reject(
      "NTUPLE_ROLES",
      "variables must be independent, two dependent variables, then PAGE",
      line=dataset.source_line,
    )
  }
  guard x.symbol == "X" &&
    real.symbol == "R" &&
    imaginary.symbol == "I" &&
    page.symbol == "N" else {
    reject(
      "NTUPLE_SYMBOLS",
      "this profile requires X, R, I and N variable symbols",
      line=dataset.source_line,
    )
  }
  guard x.form == "AFFN" &&
    ["AFFN", "ASDF"].contains(real.form) &&
    ["AFFN", "ASDF"].contains(imaginary.form) &&
    page.form == "AFFN" else {
    reject(
      "NTUPLE_FORMS",
      "this profile requires AFFN X/PAGE and AFFN or ASDF dependent variables",
      line=dataset.source_line,
    )
  }
  guard trim(x.name) != "" &&
    trim(real.name) != "" &&
    trim(imaginary.name) != "" &&
    x.units != "" &&
    real.units != "" &&
    imaginary.units != "" else {
    reject(
      "NTUPLE_METADATA",
      "NMR variables require names and units",
      line=dataset.source_line,
    )
  }
  guard dataset.pages.length() == 2 &&
    page.dimension == 2 &&
    page.first == 1.0 &&
    page.last == 2.0 &&
    page.minimum == 1.0 &&
    page.maximum == 2.0 &&
    page.factor == 1.0 else {
    reject(
      "NTUPLE_PAGE",
      "the complex NMR profile requires exactly two indexed pages",
      line=dataset.source_line,
    )
  }
  guard x.dimension == real.dimension && x.dimension == imaginary.dimension else {
    reject(
      "NTUPLE_DIMENSION",
      "X, real and imaginary variable dimensions must agree",
      line=dataset.source_line,
    )
  }
  let expected_pages = [real.symbol, imaginary.symbol]
  let reference_axis : Array[Double] = []
  let mut total_points = 0
  for i = 0; i < dataset.pages.length(); i = i + 1 {
    let item = dataset.pages[i]
    guard item.points.length() <= options.limits.max_points - total_points else {
      reject(
        "LIMIT_POINTS",
        "NTUPLES aggregate point count exceeds the configured budget",
        line=dataset.source_line,
      )
    }
    total_points += item.points.length()
    guard item.number == i + 1 && item.variable_symbol == expected_pages[i] else {
      reject(
        "NTUPLE_PAGE",
        "page order or dependent-variable mapping is invalid",
        line=dataset.source_line,
      )
    }
    guard item.points.length() == x.dimension &&
      item.points.length() <= options.limits.max_points else {
      reject(
        "NTUPLE_DIMENSION",
        "page point count differs from VAR_DIM",
        line=dataset.source_line,
      )
    }
    for j, point in item.points {
      guard finite(point.x) else {
        reject(
          "NTUPLE_AXIS",
          "independent coordinate must be finite",
          line=dataset.source_line,
        )
      }
      if i == 0 {
        reference_axis.push(point.x)
      } else {
        guard close(point.x, reference_axis[j], options) else {
          reject(
            "NTUPLE_AXIS",
            "all pages must share the same independent axis",
            line=dataset.source_line,
          )
        }
      }
      if point.y is Some(y) && !finite(y) {
        reject(
          "NTUPLE_VALUE",
          "dependent values must be finite or missing",
          line=dataset.source_line,
        )
      }
      guard point.y is Some(_) else {
        reject(
          "NTUPLE_MISSING",
          "this dense complex NMR profile does not accept missing ordinates",
          line=dataset.source_line,
        )
      }
    }
    guard uniform_step(item.points) is Some(_) else {
      reject(
        "NTUPLE_AXIS",
        "this NTUPLES profile requires a uniform independent axis",
        line=dataset.source_line,
      )
    }
  }
  if check_ranges {
    let axis = dataset.pages[0].points
    let ranges = [x, real, imaginary]
    for i = 0; i < ranges.length(); i = i + 1 {
      let variable = ranges[i]
      let points = if i == 0 { axis } else { dataset.pages[i - 1].points }
      let (first, last, minimum, maximum) = ntuple_stats(points, i == 0)
      // Historic NTUPLES headers describe physical values before ASDF quantization.
      let range_options = if i == 0 {
        options
      } else {
        {
          ..options,
          absolute_tolerance: options.absolute_tolerance +
          variable.factor.abs() / 2.0,
        }
      }
      guard close(first, variable.first, range_options) &&
        close(last, variable.last, range_options) &&
        close(minimum, variable.minimum, range_options) &&
        close(maximum, variable.maximum, range_options) else {
        reject(
          "NTUPLE_RANGE",
          "FIRST/LAST/MIN/MAX disagree with decoded variable data",
          line=dataset.source_line,
        )
      }
    }
  }
}

///|
fn ntuple_from_block(
  block : Block,
  options : ParseOptions,
) -> NtupleDataset raise JcampError {
  guard block.children.is_empty() &&
    canonical_label(record_value(block.records, "DATA CLASS").unwrap_or("")) ==
    "NTUPLES" else {
    reject(
      "NTUPLE_EXPECTED",
      "block is not a standalone NTUPLES dataset",
      line=block.start_line,
    )
  }
  let version_record = ntuple_one_record(block, "JCAMP-DX")
  let version = if trim(version_record.value) == "5.0" {
    "5.00"
  } else {
    trim(version_record.value)
  }
  let data_type = ntuple_one_record(block, "DATA TYPE").value
  let class_record = ntuple_one_record(block, "DATA CLASS")
  guard canonical_label(class_record.value) == "NTUPLES" else {
    reject(
      "NTUPLE_EXPECTED",
      "DATA CLASS must be NTUPLES",
      line=class_record.line,
    )
  }
  let ntuples_type = ntuple_one_record(block, "NTUPLES").value
  let end_record = ntuple_one_record(block, "END NTUPLES")
  guard canonical_label(end_record.value) == canonical_label(ntuples_type) else {
    reject(
      "NTUPLE_END",
      "END NTUPLES must match the declared tuple type",
      line=end_record.line,
    )
  }
  let variables = ntuple_variables(block, options)
  guard variables.length() == 4 else {
    reject(
      "NTUPLE_VARIABLES",
      "this complex NMR profile requires four variables",
      line=block.start_line,
    )
  }
  guard variables[0].dimension <=
    options.limits.max_points - variables[0].dimension else {
    reject(
      "LIMIT_POINTS",
      "two NTUPLES pages exceed the aggregate point budget",
      line=block.start_line,
    )
  }
  let page_records = block.records.filter(record => {
    canonical_label(record.label) == "PAGE"
  })
  guard page_records.length() == block.tables.length() &&
    block.tables.length() == 2 else {
    reject(
      "NTUPLE_PAGE",
      "each supported PAGE requires one DATA TABLE",
      line=block.start_line,
    )
  }
  for record in block.records {
    let key = canonical_label(record.label)
    if key != "PAGE" && key != "ENDNTUPLES" {
      guard record.line < page_records[0].line else {
        reject(
          "NTUPLE_ORDER",
          "NTUPLES metadata must precede the first PAGE",
          line=record.line,
        )
      }
    }
  }
  guard end_record.line > block.tables[1].line &&
    end_record.line < block.end_line else {
    reject(
      "NTUPLE_ORDER",
      "END NTUPLES must follow all PAGE data tables and precede END",
      line=end_record.line,
    )
  }
  let pages : Array[NtuplePage] = []
  for i = 0; i < block.tables.length(); i = i + 1 {
    let number = ntuple_page_number(page_records[i])
    let table = block.tables[i]
    guard page_records[i].line < table.line &&
      (i == block.tables.length() - 1 || table.line < page_records[i + 1].line) else {
      reject(
        "NTUPLE_ORDER",
        "each PAGE must precede its table and tables must follow PAGE order",
        line=table.line,
      )
    }
    guard canonical_label(table.label) == "DATATABLE" else {
      reject(
        "NTUPLE_TABLE",
        "NTUPLES payload must use DATA TABLE",
        line=table.line,
      )
    }
    let fields = parse_csv(table.descriptor)
    guard fields.length() == 1 &&
      fields[0].length() == 2 &&
      canonical_label(fields[0][1]) == "XYDATA" else {
      reject(
        "NTUPLE_TABLE",
        "only XYDATA DATA TABLE pages are supported",
        line=table.line,
      )
    }
    let dependent = variables[i + 1]
    let table_options = if options.numeric_mode == Auto {
      {
        ..options,
        numeric_mode: if dependent.form == "AFFN" {
          Affn
        } else {
          Asdf
        },
      }
    } else {
      options
    }
    let expected_descriptor = "(" +
      variables[0].symbol +
      "++(" +
      dependent.symbol +
      ".." +
      dependent.symbol +
      "))"
    guard canonical_label(fields[0][0]) == canonical_label(expected_descriptor) else {
      reject(
        "NTUPLE_TABLE",
        "DATA TABLE descriptor does not match its variable symbols",
        line=table.line,
      )
    }
    let records = [
      {
        label: "NPOINTS",
        value: variables[0].dimension.to_string(),
        line: table.line,
      },
      { label: "FIRSTX", value: decimal(variables[0].first), line: table.line, },
      { label: "LASTX", value: decimal(variables[0].last), line: table.line, },
      {
        label: "XFACTOR",
        value: decimal(variables[0].factor),
        line: table.line,
      },
      { label: "YFACTOR", value: decimal(dependent.factor), line: table.line, },
    ]
    let synthetic = {
      records,
      tables: [],
      children: [],
      start_line: block.start_line,
      end_line: block.end_line,
    }
    let points = incremental_points(
      synthetic,
      {
        label: "XYDATA",
        descriptor: "(X++(Y..Y))",
        rows: table.rows,
        line: table.line,
      },
      table_options,
    )
    pages.push({ number, variable_symbol: dependent.symbol, points, })
  }
  let result : NtupleDataset = {
    title: block_title(block),
    version,
    data_type,
    ntuples_type,
    records: block.records.copy(),
    variables,
    pages,
    source_line: block.start_line,
  }
  ntuple_validate(result, options, true)
  result
}

///|
pub fn read_ntuples(
  text : String,
  options~ : ParseOptions = ParseOptions::default(),
) -> NtupleDataset raise JcampError {
  let document = parse_document(text, options~)
  guard document.blocks.length() == 1 else {
    reject(
      "NTUPLE_BLOCKS", "read_ntuples expects exactly one top-level NTUPLES block",
    )
  }
  ntuple_from_block(document.blocks[0], options)
}

///|
fn ntuple_csv(values : Array[String]) -> String {
  let out = StringBuilder()
  for i, value in values {
    if i > 0 {
      out.write_string(",")
    }
    out.write_string(csv_quote(value))
  }
  out.to_string()
}

///|
fn ntuple_record_fields(
  dataset : NtupleDataset,
  variables : Array[NtupleVariable],
) -> Array[Record] raise JcampError {
  let names = variables.map(v => v.name)
  let symbols = variables.map(v => v.symbol)
  let roles = variables.map(v => v.role)
  let forms = variables.map(v => v.form)
  let dimensions = variables.map(v => v.dimension.to_string())
  let units = variables.map(v => v.units)
  let first = variables.map(v => decimal(v.first))
  let last = variables.map(v => decimal(v.last))
  let minimum = variables.map(v => decimal(v.minimum))
  let maximum = variables.map(v => decimal(v.maximum))
  let factors = variables.map(v => decimal(v.factor))
  let version = if dataset.version == "5.0" { "5.00" } else { dataset.version }
  let records = set_record(dataset.records, "TITLE", dataset.title)
  let records = set_record(records, "JCAMP-DX", version)
  let records = set_record(records, "DATA TYPE", dataset.data_type)
  let records = set_record(records, "DATA CLASS", "NTUPLES")
  let records = set_record(records, "NTUPLES", dataset.ntuples_type)
  let records = set_record(records, "VAR_NAME", ntuple_csv(names))
  let records = set_record(records, "SYMBOL", ntuple_csv(symbols))
  let records = set_record(records, "VAR_TYPE", ntuple_csv(roles))
  let records = set_record(records, "VAR_FORM", ntuple_csv(forms))
  let records = set_record(records, "VAR_DIM", ntuple_csv(dimensions))
  let records = set_record(records, "UNITS", ntuple_csv(units))
  let records = set_record(records, "FIRST", ntuple_csv(first))
  let records = set_record(records, "LAST", ntuple_csv(last))
  let records = set_record(records, "MIN", ntuple_csv(minimum))
  let records = set_record(records, "MAX", ntuple_csv(maximum))
  set_record(records, "FACTOR", ntuple_csv(factors))
}

///|
fn ntuple_written_variables(
  dataset : NtupleDataset,
  encoding : Encoding,
) -> Array[NtupleVariable] raise JcampError {
  let updated = dataset.variables.copy()
  let x = updated[0]
  let (first, last, minimum, maximum) = ntuple_stats(
    dataset.pages[0].points,
    true,
  )
  updated[0] = {
    ..x,
    dimension: dataset.pages[0].points.length(),
    first,
    last,
    minimum,
    maximum,
  }
  for i = 0; i < dataset.pages.length(); i = i + 1 {
    let old = updated[i + 1]
    let points = dataset.pages[i].points
    let (first, last, minimum, maximum) = ntuple_stats(points, false)
    let form = if encoding == Plain { "AFFN" } else { "ASDF" }
    updated[i + 1] = {
      ..old,
      dimension: points.length(),
      form,
      first,
      last,
      minimum,
      maximum,
    }
  }
  let page = updated[3]
  updated[3] = {
    ..page,
    dimension: dataset.pages.length(),
    first: 1.0,
    last: dataset.pages.length().to_double(),
    minimum: 1.0,
    maximum: dataset.pages.length().to_double(),
    factor: 1.0,
  }
  updated
}

///|
pub fn write_ntuples(
  dataset : NtupleDataset,
  options~ : NtupleWriteOptions = NtupleWriteOptions::default(),
) -> String raise JcampError {
  guard options.points_per_line >= 1 && options.points_per_line <= 1024 else {
    reject("WRITE_WIDTH", "points_per_line must be between 1 and 1024")
  }
  let parse_options = ParseOptions::default()
  ntuple_validate(dataset, parse_options, false)
  let variables = ntuple_written_variables(dataset, options.encoding)
  let records = ntuple_record_fields(dataset, variables)
  let out = StringBuilder()
  let title_record = { label: "TITLE", value: dataset.title, line: 0, }
  let records = [title_record] +
    records.filter(record => canonical_label(record.label) != "TITLE")
  for record in records {
    let key = canonical_label(record.label)
    if key != "PAGE" && key != "ENDNTUPLES" {
      append_record(out, record)
    }
  }
  for i = 0; i < dataset.pages.length(); i = i + 1 {
    let page = dataset.pages[i]
    let dependent = variables[i + 1]
    let version = if dataset.version == "5.0" {
      "5.00"
    } else {
      dataset.version
    }
    let spectrum = {
      title: dataset.title,
      data_type: "NMR SPECTRUM",
      x_units: variables[0].units,
      y_units: dependent.units,
      points: page.points,
      records: [],
      source_line: dataset.source_line,
    }
    let table_text = write_spectrum(spectrum, options={
      encoding: options.encoding,
      table_style: Incremental,
      points_per_line: options.points_per_line,
      x_factor: variables[0].factor,
      y_factor: dependent.factor,
      version,
    })
    let generated = parse_document(table_text)
    guard generated.blocks.length() == 1 &&
      generated.blocks[0].tables.length() == 1 else {
      reject("NTUPLE_WRITE", "internal one-dimensional table generation failed")
    }
    let table = generated.blocks[0].tables[0]
    out.write_string("##PAGE=N=" + page.number.to_string() + "\n")
    out.write_string(
      "##DATA TABLE=(" +
      variables[0].symbol +
      "++(" +
      dependent.symbol +
      ".." +
      dependent.symbol +
      ")), XYDATA\n",
    )
    for row in table.rows {
      out.write_string(row.text + "\n")
    }
  }
  out.write_string("##END NTUPLES=" + dataset.ntuples_type + "\n##END=\n")
  let result = out.to_string()
  let checked = read_ntuples(result)
  for i = 0; i < dataset.pages.length(); i = i + 1 {
    guard checked.pages[i].points == dataset.pages[i].points else {
      reject("NTUPLE_WRITE", "written NTUPLES pages do not roundtrip exactly")
    }
  }
  result
}

///|
pub fn rewrite_ntuples(
  text : String,
  read_options~ : ParseOptions = ParseOptions::default(),
  write_options~ : NtupleWriteOptions = NtupleWriteOptions::default(),
) -> String raise JcampError {
  write_ntuples(read_ntuples(text, options=read_options), options=write_options)
}
