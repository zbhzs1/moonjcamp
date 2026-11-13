///|
fn check_headers(block : Block) -> Unit raise JcampError {
  let unique : Map[String, Bool] = Map([])
  for record in block.records {
    let key = canonical_label(record.label)
    if [
        "TITLE", "JCAMPDX", "DATATYPE", "DATACLASS", "NPOINTS", "FIRSTX", "LASTX",
        "FIRSTY", "DELTAX", "XFACTOR", "YFACTOR", "XUNITS", "YUNITS", "BLOCKS",
      ].contains(key) {
      guard !unique.contains(key) else {
        reject(
          "HEADER_DUPLICATE",
          "duplicate semantic label: " + key,
          line=record.line,
        )
      }
      unique[key] = true
    }
    if key == "NTUPLES" ||
      key == "PAGE" ||
      key == "ENDNTUPLES" ||
      key == "PEAKASSIGNMENTS" {
      reject(
        "UNSUPPORTED_TABLE",
        "this release does not interpret " + key,
        line=record.line,
      )
    }
  }
  guard block_title(block) != "" else {
    reject("TITLE_EMPTY", "TITLE must be nonempty", line=block.start_line)
  }
  let version = required_number(block.records, "JCAMP-DX", block.start_line)
  guard version == 4.24 || version == 5.0 || version == 5.01 else {
    reject(
      "UNSUPPORTED_VERSION",
      "supported declarations are 4.24, 5.00 and 5.01",
      line=block.start_line,
    )
  }
  guard block_kind(block) != "" else {
    reject("HEADER_MISSING", "missing DATA TYPE", line=block.start_line)
  }
}

///|
fn scaling(block : Block) -> (Double, Double) raise JcampError {
  let x = optional_number(block.records, "XFACTOR", 1.0, block.start_line)
  let y = optional_number(block.records, "YFACTOR", 1.0, block.start_line)
  guard x != 0.0 && y != 0.0 else {
    reject(
      "SCALE_ZERO",
      "XFACTOR and YFACTOR must be nonzero",
      line=block.start_line,
    )
  }
  (x, y)
}

///|
fn scaled(
  value : Double,
  factor : Double,
  line : Int32,
) -> Double raise JcampError {
  let result = value * factor
  guard finite(result) else {
    reject("SCALE_RANGE", "scaled value is not finite", line~)
  }
  result
}

///|
fn scaled_y(
  value : Double?,
  factor : Double,
  line : Int32,
) -> Double? raise JcampError {
  match value {
    Some(y) => Some(scaled(y, factor, line))
    None => None
  }
}

///|
fn matching_y(a : Double?, b : Double?, options : ParseOptions) -> Bool {
  match (a, b) {
    (Some(a), Some(b)) => close(a, b, options)
    (None, None) => true
    _ => false
  }
}

///|
fn table_options(table : DataTable, options : ParseOptions) -> ParseOptions {
  if options.numeric_mode != Auto {
    return options
  }
  for row in table.rows {
    let affn = try {
      ignore(numeric_tokens(strip_comment(row.text), Affn, options, row.line))
      true
    } catch {
      Invalid(_) => false
    }
    if !affn {
      return { ..options, numeric_mode: Asdf, }
    }
  }
  { ..options, numeric_mode: Affn, }
}

///|
fn incremental_points(
  block : Block,
  table : DataTable,
  options : ParseOptions,
) -> Array[Point] raise JcampError {
  let options = table_options(table, options)
  guard canonical_label(table.descriptor) == "(X++(Y..Y))" else {
    reject(
      "UNSUPPORTED_DESCRIPTOR",
      "XYDATA requires (X++(Y..Y))",
      line=table.line,
    )
  }
  let count = point_count(block.records, options, block.start_line)
  let first = required_number(block.records, "FIRSTX", block.start_line)
  let last = required_number(block.records, "LASTX", block.start_line)
  let step = if count == 1 {
    0.0
  } else {
    (last - first) / (count - 1).to_double()
  }
  guard finite(step) && (count == 1 || step != 0.0) else {
    reject(
      "AXIS_STEP",
      "incremental axis requires a finite nonzero step",
      line=table.line,
    )
  }
  if count == 1 && !close(first, last, options) {
    reject(
      "AXIS_ENDPOINT",
      "single-point FIRSTX and LASTX must agree",
      line=table.line,
    )
  }
  // Section 6.3.2 defines DELTAX as nominal, not the reconstruction interval.
  let (xfactor, yfactor) = scaling(block)
  guard options.limits.max_points < 2147483647 else {
    reject("OPTION_LIMIT", "point budget is too large")
  }
  let row_options = {
    ..options,
    limits: { ..options.limits, max_points: options.limits.max_points + 1, },
  }
  let points : Array[Point] = []
  let mut previous_difference = false
  for row in table.rows {
    let decoded = decode_line(row.text, row_options, row.line)
    guard decoded.values.length() >= 2 && decoded.first_ordinate_absolute else {
      reject(
        "ROW_ANCHOR",
        "each data row requires absolute X and Y anchors",
        line=row.line,
      )
    }
    guard decoded.values[0] is Some(raw_x) else {
      reject("X_MISSING", "X anchor cannot be missing", line=row.line)
    }
    let overlap = previous_difference && !points.is_empty()
    let index = if overlap { points.length() - 1 } else { points.length() }
    let expected = first + step * index.to_double()
    let actual = scaled(raw_x, xfactor, row.line)
    guard finite(expected) && close(actual, expected, options) else {
      reject(
        "X_CHECKPOINT",
        "row X anchor disagrees with reconstructed axis",
        line=row.line,
      )
    }
    if overlap {
      let checkpoint = scaled_y(decoded.values[1], yfactor, row.line)
      guard matching_y(checkpoint, points[points.length() - 1].y, options) else {
        reject(
          "Y_CHECKPOINT",
          "DIF checkpoint differs from the preceding terminal ordinate",
          line=row.line,
        )
      }
    }
    let mut i = if overlap { 2 } else { 1 }
    while i < decoded.values.length() {
      guard points.length() < count else {
        reject(
          "POINT_COUNT",
          "data table contains more values than NPOINTS",
          line=row.line,
        )
      }
      let x = first + step * points.length().to_double()
      guard finite(x) else {
        reject("AXIS_RANGE", "reconstructed axis overflow", line=row.line)
      }
      points.push({ x, y: scaled_y(decoded.values[i], yfactor, row.line), })
      i += 1
    }
    previous_difference = decoded.ends_difference
  }
  guard points.length() == count else {
    reject(
      "POINT_COUNT",
      "decoded point count differs from NPOINTS",
      line=table.line,
    )
  }
  points
}

///|
fn paired_points(
  block : Block,
  table : DataTable,
  options : ParseOptions,
) -> Array[Point] raise JcampError {
  let options = table_options(table, options)
  guard canonical_label(table.descriptor) == "(XY..XY)" else {
    reject(
      "UNSUPPORTED_DESCRIPTOR",
      "explicit point tables require (XY..XY)",
      line=table.line,
    )
  }
  let count = point_count(block.records, options, block.start_line)
  let (xfactor, yfactor) = scaling(block)
  let points : Array[Point] = []
  guard options.limits.max_points <= 1073741823 else {
    reject("OPTION_LIMIT", "point budget is too large")
  }
  let row_options = {
    ..options,
    limits: { ..options.limits, max_points: options.limits.max_points * 2, },
  }
  for row in table.rows {
    let decoded = decode_line(row.text, row_options, row.line)
    guard !decoded.uses_difference && decoded.values.length() % 2 == 0 else {
      reject(
        "PAIR_ARITY",
        "explicit pair rows require complete absolute X,Y pairs",
        line=row.line,
      )
    }
    let mut i = 0
    while i < decoded.values.length() {
      guard decoded.values[i] is Some(raw_x) else {
        reject("X_MISSING", "explicit X cannot be missing", line=row.line)
      }
      guard points.length() < count else {
        reject("POINT_COUNT", "more explicit pairs than NPOINTS", line=row.line)
      }
      points.push({
        x: scaled(raw_x, xfactor, row.line),
        y: scaled_y(decoded.values[i + 1], yfactor, row.line),
      })
      i += 2
    }
  }
  guard points.length() == count else {
    reject(
      "POINT_COUNT",
      "explicit pair count differs from NPOINTS",
      line=table.line,
    )
  }
  points
}

///|
fn check_endpoints(
  block : Block,
  points : Array[Point],
  options : ParseOptions,
) -> Unit raise JcampError {
  if record_value(block.records, "FIRSTX") is Some(value) {
    guard close(number(value, line=block.start_line), points[0].x, options) else {
      reject(
        "AXIS_ENDPOINT",
        "FIRSTX disagrees with first data point",
        line=block.start_line,
      )
    }
  }
  if record_value(block.records, "LASTX") is Some(value) {
    guard close(
      number(value, line=block.start_line),
      points[points.length() - 1].x,
      options,
    ) else {
      reject(
        "AXIS_ENDPOINT",
        "LASTX disagrees with last data point",
        line=block.start_line,
      )
    }
  }
  if record_value(block.records, "FIRSTY") is Some(value) {
    guard points[0].y is Some(y) &&
      close(number(value, line=block.start_line), y, options) else {
      reject(
        "Y_ENDPOINT",
        "FIRSTY disagrees with first data point",
        line=block.start_line,
      )
    }
  }
}

///|
pub fn spectrum_from_block(
  block : Block,
  options~ : ParseOptions = ParseOptions::default(),
) -> Spectrum raise JcampError {
  check_options(options)
  check_headers(block)
  guard block.children.is_empty() &&
    canonical_label(block_kind(block)) != "LINK" else {
    reject(
      "SPECTRUM_EXPECTED",
      "a compound block is not a single spectrum",
      line=block.start_line,
    )
  }
  guard block.tables.length() == 1 else {
    reject(
      "TABLE_COUNT",
      "a spectrum requires exactly one supported data table",
      line=block.start_line,
    )
  }
  guard canonical_label(block_kind(block)).has_suffix("SPECTRUM") ||
    canonical_label(block_kind(block)).contains("PEAK") else {
    reject(
      "UNSUPPORTED_DATA_TYPE",
      "only one-dimensional real spectra and peak tables are interpreted",
      line=block.start_line,
    )
  }
  let table = block.tables[0]
  let key = canonical_label(table.label)
  if record_value(block.records, "DATA CLASS") is Some(data_class) {
    guard canonical_label(data_class) == key else {
      reject(
        "DATA_CLASS",
        "DATA CLASS differs from table label",
        line=table.line,
      )
    }
  }
  let x_units = record_value(block.records, "XUNITS").unwrap_or("")
  let y_units = record_value(block.records, "YUNITS").unwrap_or("")
  guard trim(x_units) != "" && trim(y_units) != "" else {
    reject(
      "HEADER_UNITS",
      "nonempty XUNITS and YUNITS are required",
      line=block.start_line,
    )
  }
  let points = match key {
    "XYDATA" => incremental_points(block, table, options)
    "XYPOINTS" | "XYPAIRS" | "PEAKTABLE" => paired_points(block, table, options)
    _ =>
      reject(
        "UNSUPPORTED_TABLE",
        "unsupported data table: " + table.label,
        line=table.line,
      )
  }
  check_endpoints(block, points, options)
  {
    title: block_title(block),
    data_type: block_kind(block),
    x_units,
    y_units,
    points,
    records: block.records.copy(),
    source_line: block.start_line,
  }
}

///|
pub fn spectra_from_document(
  document : Document,
  options~ : ParseOptions = ParseOptions::default(),
) -> Array[Spectrum] raise JcampError {
  check_options(options)
  let result : Array[Spectrum] = []
  let mut total_points = 0
  let mut total_blocks = 0
  fn visit(block : Block, depth : Int32) -> Unit raise JcampError {
    guard depth <= options.limits.max_depth else {
      reject(
        "LIMIT_DEPTH",
        "compound nesting exceeds budget",
        line=block.start_line,
      )
    }
    total_blocks += 1
    guard total_blocks <= options.limits.max_blocks else {
      reject(
        "LIMIT_BLOCKS",
        "document block budget exceeded",
        line=block.start_line,
      )
    }
    if canonical_label(block_kind(block)) == "LINK" {
      check_headers(block)
      guard block.tables.is_empty() && !block.children.is_empty() else {
        reject(
          "LINK_CONTENT",
          "LINK requires child blocks and no numeric table",
          line=block.start_line,
        )
      }
      let declared = required_number(block.records, "BLOCKS", block.start_line)
      guard declared == block.children.length().to_double() else {
        reject(
          "LINK_COUNT",
          "BLOCKS differs from direct child count",
          line=block.start_line,
        )
      }
      for child in block.children {
        visit(child, depth + 1)
      }
    } else {
      let spectrum = spectrum_from_block(block, options~)
      guard spectrum.points.length() <= options.limits.max_points - total_points else {
        reject(
          "LIMIT_POINTS",
          "total document points exceed budget",
          line=block.start_line,
        )
      }
      total_points += spectrum.points.length()
      result.push(spectrum)
    }
  }
  for block in document.blocks {
    visit(block, 1)
  }
  guard !result.is_empty() else {
    reject("SPECTRUM_EMPTY", "document contains no interpreted spectra")
  }
  result
}

///|
pub fn read_spectra(
  text : String,
  options~ : ParseOptions = ParseOptions::default(),
) -> Array[Spectrum] raise JcampError {
  spectra_from_document(parse_document(text, options~), options~)
}

///|
pub fn inspect(
  text : String,
  options~ : ParseOptions = ParseOptions::default(),
) -> Report {
  try {
    let spectra = read_spectra(text, options~)
    let mut points = 0
    let mut missing = 0
    for spectrum in spectra {
      points += spectrum.points.length()
      missing += spectrum.points.filter(p => p.y is None).length()
    }
    {
      valid: true,
      spectra: spectra.length(),
      points,
      missing,
      diagnostics: [],
    }
  } catch {
    Invalid(diagnostic) =>
      {
        valid: false,
        spectra: 0,
        points: 0,
        missing: 0,
        diagnostics: [diagnostic],
      }
  }
}
