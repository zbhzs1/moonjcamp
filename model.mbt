///|
#derive(Eq, @debug.Debug, ToJson)
pub(all) enum Severity {
  Error
  Warning
}

///|
#derive(Eq, @debug.Debug, ToJson)
pub(all) struct Diagnostic {
  severity : Severity
  code : String
  message : String
  line : Int32
  column : Int32
}

///|
#derive(@debug.Debug)
pub(all) suberror JcampError {
  Invalid(Diagnostic)
}

///|
#derive(Eq, @debug.Debug, ToJson)
pub(all) enum NumericMode {
  Auto
  Affn
  Asdf
}

///|
#derive(Eq, @debug.Debug, ToJson)
pub(all) enum Encoding {
  Plain
  Packed
  Squeezed
  Difference
}

///|
#derive(Eq, @debug.Debug, ToJson)
pub(all) struct Limits {
  max_chars : Int32
  max_lines : Int32
  max_line_chars : Int32
  max_records : Int32
  max_blocks : Int32
  max_depth : Int32
  max_points : Int32
  max_tokens_per_line : Int32
}

///|
pub fn Limits::default() -> Limits {
  {
    max_chars: 16000000,
    max_lines: 250000,
    max_line_chars: 16384,
    max_records: 50000,
    max_blocks: 1000,
    max_depth: 16,
    max_points: 1000000,
    max_tokens_per_line: 100000,
  }
}

///|
#derive(@debug.Debug, ToJson)
pub(all) struct ParseOptions {
  limits : Limits
  numeric_mode : NumericMode
  relative_tolerance : Double
  absolute_tolerance : Double
}

///|
pub fn ParseOptions::default() -> ParseOptions {
  {
    limits: Limits::default(),
    numeric_mode: Auto,
    relative_tolerance: 0.000001,
    absolute_tolerance: 0.00000001,
  }
}

///|
#derive(Eq, @debug.Debug, ToJson, @json.FromJson)
pub(all) struct Record {
  label : String
  value : String
  line : Int32
}

///|
#derive(Eq, @debug.Debug, ToJson)
pub(all) struct DataLine {
  text : String
  line : Int32
}

///|
#derive(Eq, @debug.Debug, ToJson)
pub(all) struct DataTable {
  label : String
  descriptor : String
  rows : Array[DataLine]
  line : Int32
}

///|
#derive(@debug.Debug, ToJson)
pub(all) struct Block {
  records : Array[Record]
  tables : Array[DataTable]
  children : Array[Block]
  start_line : Int32
  end_line : Int32
}

///|
#derive(@debug.Debug, ToJson)
pub(all) struct Document {
  blocks : Array[Block]
}

///|
#derive(Eq, @debug.Debug, @json.FromJson)
pub(all) struct Point {
  x : Double
  y : Double?
}

///|
pub impl ToJson for Point with fn to_json(self) {
  let y : Json = match self.y {
    Some(y) => Json(y)
    None => Json::null()
  }
  { "x": Json(self.x), "y": y }
}

///|
#derive(@debug.Debug, ToJson, @json.FromJson)
pub(all) struct Spectrum {
  title : String
  data_type : String
  x_units : String
  y_units : String
  points : Array[Point]
  records : Array[Record]
  source_line : Int32
}

///|
#derive(@debug.Debug, ToJson)
pub(all) struct Report {
  valid : Bool
  spectra : Int32
  points : Int32
  missing : Int32
  diagnostics : Array[Diagnostic]
}

///|
fn[T] reject(
  code : String,
  message : String,
  line~ : Int32 = 0,
  column~ : Int32 = 1,
) -> T raise JcampError {
  raise Invalid({ severity: Error, code, message, line, column, })
}

///|
fn finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn close(a : Double, b : Double, options : ParseOptions) -> Bool {
  let scale = if a.abs() > b.abs() { a.abs() } else { b.abs() }
  (a - b).abs() <=
  options.absolute_tolerance + options.relative_tolerance * scale
}

///|
fn check_options(options : ParseOptions) -> Unit raise JcampError {
  let l = options.limits
  for
    limit in [
      l.max_chars,
      l.max_lines,
      l.max_line_chars,
      l.max_records,
      l.max_blocks,
      l.max_depth,
      l.max_points,
      l.max_tokens_per_line,
    ] {
    guard limit > 0 else {
      reject("OPTION_LIMIT", "resource budgets must be positive")
    }
  }
  guard l.max_depth <= 128 else {
    reject("OPTION_DEPTH", "maximum nesting may not exceed 128")
  }
  guard finite(options.relative_tolerance) &&
    finite(options.absolute_tolerance) &&
    options.relative_tolerance >= 0.0 &&
    options.absolute_tolerance >= 0.0 else {
    reject("OPTION_TOLERANCE", "tolerances must be finite and nonnegative")
  }
}
