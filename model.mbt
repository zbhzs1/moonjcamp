///|
pub(all) enum Severity {
  Error
  Warning
} derive(Eq, @debug.Debug, ToJson)

///|
pub(all) struct Diagnostic {
  severity : Severity
  code : String
  message : String
  line : Int
  column : Int
} derive(Eq, @debug.Debug, ToJson)

///|
pub(all) suberror JcampError {
  Invalid(Diagnostic)
} derive(@debug.Debug)

///|
pub(all) enum NumericMode {
  Auto
  Affn
  Asdf
} derive(Eq, @debug.Debug, ToJson)

///|
pub(all) enum Encoding {
  Plain
  Packed
  Squeezed
  Difference
} derive(Eq, @debug.Debug, ToJson)

///|
pub(all) struct Limits {
  max_chars : Int
  max_lines : Int
  max_line_chars : Int
  max_records : Int
  max_blocks : Int
  max_depth : Int
  max_points : Int
  max_tokens_per_line : Int
} derive(Eq, @debug.Debug, ToJson)

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
pub(all) struct ParseOptions {
  limits : Limits
  numeric_mode : NumericMode
  relative_tolerance : Double
  absolute_tolerance : Double
} derive(@debug.Debug, ToJson)

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
pub(all) struct Record {
  label : String
  value : String
  line : Int
} derive(Eq, @debug.Debug, ToJson, @json.FromJson)

///|
pub(all) struct DataLine {
  text : String
  line : Int
} derive(Eq, @debug.Debug, ToJson)

///|
pub(all) struct DataTable {
  label : String
  descriptor : String
  rows : Array[DataLine]
  line : Int
} derive(Eq, @debug.Debug, ToJson)

///|
pub(all) struct Block {
  records : Array[Record]
  tables : Array[DataTable]
  children : Array[Block]
  start_line : Int
  end_line : Int
} derive(@debug.Debug, ToJson)

///|
pub(all) struct Document {
  blocks : Array[Block]
} derive(@debug.Debug, ToJson)

///|
pub(all) struct Point {
  x : Double
  y : Double?
} derive(Eq, @debug.Debug, ToJson, @json.FromJson)

///|
pub(all) struct Spectrum {
  title : String
  data_type : String
  x_units : String
  y_units : String
  points : Array[Point]
  records : Array[Record]
  source_line : Int
} derive(@debug.Debug, ToJson, @json.FromJson)

///|
pub(all) struct Report {
  valid : Bool
  spectra : Int
  points : Int
  missing : Int
  diagnostics : Array[Diagnostic]
} derive(@debug.Debug, ToJson)

///|
fn[T] reject(code : String, message : String, line~ : Int = 0, column~ : Int = 1) -> T raise JcampError {
  raise Invalid({ severity: Error, code, message, line, column })
}

///|
fn finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn close(a : Double, b : Double, options : ParseOptions) -> Bool {
  let scale = if a.abs() > b.abs() { a.abs() } else { b.abs() }
  (a - b).abs() <= options.absolute_tolerance + options.relative_tolerance * scale
}

///|
fn check_options(options : ParseOptions) -> Unit raise JcampError {
  let l = options.limits
  for limit in [l.max_chars, l.max_lines, l.max_line_chars, l.max_records, l.max_blocks, l.max_depth, l.max_points, l.max_tokens_per_line] {
    guard limit > 0 else { reject("OPTION_LIMIT", "resource budgets must be positive") }
  }
  guard l.max_depth <= 128 else { reject("OPTION_DEPTH", "maximum nesting may not exceed 128") }
  guard finite(options.relative_tolerance) && finite(options.absolute_tolerance) &&
    options.relative_tolerance >= 0.0 && options.absolute_tolerance >= 0.0 else {
    reject("OPTION_TOLERANCE", "tolerances must be finite and nonnegative")
  }
}
