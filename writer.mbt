///|
pub(all) enum TableStyle {
  Automatic
  Incremental
  Pairs
} derive(Eq, @debug.Debug, ToJson)

///|
pub(all) struct WriteOptions {
  encoding : Encoding
  table_style : TableStyle
  points_per_line : Int
  x_factor : Double
  y_factor : Double
} derive(@debug.Debug, ToJson)

///|
pub fn WriteOptions::default() -> WriteOptions {
  { encoding: Plain, table_style: Automatic, points_per_line: 8, x_factor: 1.0, y_factor: 1.0 }
}

///|
pub extend TableStyle with Eq::{equal, not_equal}
///|
pub extend TableStyle with @debug.Debug::{to_repr}
///|
pub extend TableStyle with ToJson::{to_json}
///|
pub extend WriteOptions with @debug.Debug::{to_repr}
///|
pub extend WriteOptions with ToJson::{to_json}

///|
fn decimal(value : Double) -> String raise JcampError {
  guard finite(value) else { reject("WRITE_NUMBER", "cannot write non-finite values") }
  let raw = value.to_string()
  let upper = raw[:].to_upper().to_owned()
  guard upper.find("E") is Some(at) else { return raw }
  let exponent = number(upper[at + 1:].to_owned()).to_int()
  let negative = upper.has_prefix("-")
  let mantissa = upper[if negative { 1 } else { 0 }:at].to_owned()
  let before = mantissa.find(".").unwrap_or(mantissa.length())
  let digits = mantissa.replace_all(old=".", new="")
  let position = before + exponent
  let out = StringBuilder()
  if negative { out.write_string("-") }
  if position <= 0 {
    out.write_string("0.")
    for _i = 0; _i < -position; _i = _i + 1 { out.write_string("0") }
    out.write_string(digits)
  } else if position >= digits.length() {
    out.write_string(digits)
    for _i = digits.length(); _i < position; _i = _i + 1 { out.write_string("0") }
  } else {
    out.write_string(digits[:position].to_owned())
    out.write_string(".")
    out.write_string(digits[position:].to_owned())
  }
  out.to_string()
}

///|
fn writable_record(record : Record) -> Unit raise JcampError {
  let label = trim(record.label)
  guard label != "" && !label.contains("=") && !label.contains("#") && !label.contains("$$") &&
    label.iter().all(c => c >= ' ' && c != '\u007f') else { reject("WRITE_LABEL", "record label contains a delimiter or control character", line=record.line) }
  guard !record.value.contains("\r") && !record.value.contains("\u0000") && !record.value.contains("$$") else { reject("WRITE_VALUE", "record value contains a control or comment delimiter", line=record.line) }
  for line in record.value.split("\n") {
    guard !trim(line.to_owned()).has_prefix("##") else { reject("WRITE_INJECTION", "continuation value would inject a label", line=record.line) }
  }
}

///|
fn append_record(out : StringBuilder, record : Record) -> Unit raise JcampError {
  writable_record(record)
  out.write_string("##" + trim(record.label) + "=" + record.value + "\n")
}

///|
fn checked_spectrum(spectrum : Spectrum) -> Unit raise JcampError {
  guard trim(spectrum.title) != "" && trim(spectrum.x_units) != "" && trim(spectrum.y_units) != "" else { reject("SPECTRUM_METADATA", "title and axis units must be nonempty") }
  guard !spectrum.points.is_empty() && spectrum.points.length() <= Limits::default().max_points else { reject("POINT_COUNT", "spectrum point count is outside supported budget") }
  for p in spectrum.points {
    guard finite(p.x) else { reject("X_RANGE", "X must be finite") }
    if p.y is Some(y) { guard finite(y) else { reject("Y_RANGE", "Y must be finite or missing") } }
  }
}

///|
fn uniform_step(points : Array[Point]) -> Double? {
  if points.is_empty() { return None }
  if points.length() == 1 { return Some(0.0) }
  let first = points[0].x
  let step = (points[points.length() - 1].x - first) / (points.length() - 1).to_double()
  if !finite(step) || step == 0.0 { return None }
  let precise = { ..ParseOptions::default(), relative_tolerance: 0.000000000001, absolute_tolerance: 0.000000000001 }
  for i, point in points {
    let expected = first + i.to_double() * step
    if !finite(expected) || !close(point.x, expected, precise) { return None }
  }
  Some(step)
}

///|
fn remove_records(records : Array[Record], labels : Array[String]) -> Array[Record] {
  records.filter(r => !labels.contains(canonical_label(r.label)))
}

///|
fn write_records(spectrum : Spectrum, options : WriteOptions, incremental : Bool) -> Array[Record] raise JcampError {
  let mut records = remove_records(spectrum.records, ["TITLE", "JCAMPDX", "DATATYPE", "DATACLASS", "END", "BLOCKS", "XYDATA", "XYPOINTS", "XYPAIRS", "PEAKTABLE", "DATATABLE", "NPOINTS", "FIRSTX", "LASTX", "FIRSTY", "MINX", "MAXX", "MINY", "MAXY", "DELTAX", "XFACTOR", "YFACTOR", "XUNITS", "YUNITS"])
  let mut x_min = spectrum.points[0].x
  let mut x_max = x_min
  let mut y_min : Double? = None
  let mut y_max : Double? = None
  for p in spectrum.points {
    if p.x < x_min { x_min = p.x }
    if p.x > x_max { x_max = p.x }
    if p.y is Some(y) {
      y_min = match y_min { Some(v) => Some(if y < v { y } else { v }); None => Some(y) }
      y_max = match y_max { Some(v) => Some(if y > v { y } else { v }); None => Some(y) }
    }
  }
  let first = spectrum.points[0]
  let last = spectrum.points[spectrum.points.length() - 1]
  let prefix : Array[Record] = [
    { label: "TITLE", value: spectrum.title, line: 0 },
    { label: "JCAMP-DX", value: "5.01", line: 0 },
    { label: "DATA TYPE", value: spectrum.data_type, line: 0 },
    { label: "DATA CLASS", value: if incremental { "XYDATA" } else { "XYPOINTS" }, line: 0 },
  ]
  records = prefix + records
  records = set_record(records, "XUNITS", spectrum.x_units)
  records = set_record(records, "YUNITS", spectrum.y_units)
  records = set_record(records, "XFACTOR", decimal(options.x_factor))
  records = set_record(records, "YFACTOR", decimal(options.y_factor))
  records = set_record(records, "FIRSTX", decimal(first.x))
  records = set_record(records, "LASTX", decimal(last.x))
  records = set_record(records, "NPOINTS", spectrum.points.length().to_string())
  records = set_record(records, "MINX", decimal(x_min))
  records = set_record(records, "MAXX", decimal(x_max))
  if first.y is Some(y) { records = set_record(records, "FIRSTY", decimal(y)) }
  if y_min is Some(y) { records = set_record(records, "MINY", decimal(y)) }
  if y_max is Some(y) { records = set_record(records, "MAXY", decimal(y)) }
  if incremental && uniform_step(spectrum.points) is Some(step) { records = set_record(records, "DELTAX", decimal(step)) }
  records
}

///|
fn asdf_integer(value : Double, factor : Double) -> Double raise JcampError {
  let raw = value / factor
  guard finite(raw) && raw.abs() <= 9007199254740991.0 else { reject("WRITE_ASDF_RANGE", "ASDF ordinate exceeds exact integer range") }
  let integer = raw.round()
  let reconstructed = integer * factor
  let precise = { ..ParseOptions::default(), relative_tolerance: 0.000000000001, absolute_tolerance: 0.000000000001 }
  guard close(value, reconstructed, precise) else { reject("WRITE_ASDF_SCALE", "selected YFACTOR does not represent ordinate as an integer without material rounding") }
  integer
}

///|
fn coded(value : Double, difference : Bool) -> String raise JcampError {
  guard finite(value) && value.floor() == value && value.abs() <= 9007199254740991.0 else { reject("WRITE_ASDF_RANGE", "coded value must be an exactly representable integer") }
  let digits = value.abs().to_int64().to_string()
  let leading = digits[0].to_int() - 48
  let alphabet = if difference {
    if value < 0.0 { "%jklmnopqr" } else { "%JKLMNOPQR" }
  } else {
    if value < 0.0 { "@abcdefghi" } else { "@ABCDEFGHI" }
  }
  alphabet[leading:leading + 1].to_owned() + digits[1:].to_owned()
}

///|
fn duplication(count : Int) -> String {
  let digits = count.to_string()
  let first = digits[0].to_int() - 49
  "STUVWXYZs"[first:first + 1].to_owned() + digits[1:].to_owned()
}

///|
fn ordinate(value : Double?, options : WriteOptions, force_absolute : Bool, previous : Double?) -> (String, Bool) raise JcampError {
  guard value is Some(y) else { return ("?", false) }
  match options.encoding {
    Plain => (decimal(y / options.y_factor), false)
    Packed => {
      let raw = y / options.y_factor
      let text = decimal(raw)
      (if raw >= 0.0 { "+" + text } else { text }, false)
    }
    Squeezed => (coded(asdf_integer(y, options.y_factor), false), false)
    Difference => {
      let raw = asdf_integer(y, options.y_factor)
      if !force_absolute && previous is Some(previous) {
        let delta = raw - asdf_integer(previous, options.y_factor)
        (coded(delta, true), true)
      } else { (coded(raw, false), false) }
    }
  }
}

///|
fn append_encoded(out : StringBuilder, tokens : Array[(String, Bool)], encoding : Encoding) -> Unit {
  let mut i = 0
  while i < tokens.length() {
    let (token, delta) = tokens[i]
    if encoding == Plain && i > 0 { out.write_string(" ") }
    out.write_string(token)
    let mut run = 1
    if encoding == Difference && delta {
      while i + run < tokens.length() && tokens[i + run] == (token, true) { run += 1 }
      if run > 1 { out.write_string(duplication(run)) }
    }
    i += run
  }
}

///|
pub fn write_spectrum(spectrum : Spectrum, options~ : WriteOptions = WriteOptions::default()) -> String raise JcampError {
  checked_spectrum(spectrum)
  guard options.points_per_line >= 1 && options.points_per_line <= 1024 else { reject("WRITE_WIDTH", "points_per_line must be between 1 and 1024") }
  guard finite(options.x_factor) && finite(options.y_factor) && options.x_factor != 0.0 && options.y_factor != 0.0 else { reject("WRITE_SCALE", "scale factors must be finite and nonzero") }
  let regular = uniform_step(spectrum.points) is Some(_)
  let incremental = match options.table_style {
    Automatic => regular
    Incremental => {
      guard regular else { reject("WRITE_AXIS", "irregular axis requires explicit pair table") }
      true
    }
    Pairs => false
  }
  guard incremental || options.encoding != Difference else { reject("WRITE_ENCODING", "DIF output requires incremental XYDATA") }
  let out = StringBuilder()
  for record in write_records(spectrum, options, incremental) { append_record(out, record) }
  if incremental {
    out.write_string("##XYDATA=(X++(Y..Y))\n")
    let mut next = 0
    let mut previous_difference = false
    while next < spectrum.points.length() {
      let begin = if previous_difference && next > 0 { next - 1 } else { next }
      let end = if next + options.points_per_line < spectrum.points.length() { next + options.points_per_line } else { spectrum.points.length() }
      out.write_string(decimal(spectrum.points[begin].x / options.x_factor) + " ")
      let tokens : Array[(String, Bool)] = []
      let mut previous : Double? = None
      let mut differential = false
      for i = begin; i < end; i = i + 1 {
        let token = ordinate(spectrum.points[i].y, options, i == begin, previous)
        tokens.push(token)
        differential = differential || token.1
        previous = spectrum.points[i].y
      }
      append_encoded(out, tokens, options.encoding)
      out.write_string("\n")
      previous_difference = differential
      next = end
    }
  } else {
    out.write_string("##XYPOINTS=(XY..XY)\n")
    for i, point in spectrum.points {
      if i > 0 && i % options.points_per_line != 0 { out.write_string("; ") }
      out.write_string(decimal(point.x / options.x_factor) + ",")
      let (value, _) = ordinate(point.y, options, true, None)
      out.write_string(value)
      if (i + 1) % options.points_per_line == 0 || i + 1 == spectrum.points.length() { out.write_string("\n") }
    }
  }
  out.write_string("##END=\n")
  let result = out.to_string()
  // Enforce the same profile on constructed public objects as on input files.
  ignore(read_spectra(result))
  result
}
