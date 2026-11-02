///|
fn json_object(
  value : Json,
  allowed : Array[String],
  context : String,
) -> Map[String, Json] raise JcampError {
  guard value is Object(fields) else {
    reject("JSON_OBJECT", context + " must be an object")
  }
  for key in fields.keys() {
    guard allowed.contains(key) else {
      reject("JSON_FIELD", context + " has unknown field: " + key)
    }
  }
  fields
}

///|
fn json_field(
  fields : Map[String, Json],
  key : String,
) -> Json raise JcampError {
  match fields.get(key) {
    Some(value) => value
    None => reject("JSON_REQUIRED", "missing JSON field: " + key)
  }
}

///|
fn json_string(
  fields : Map[String, Json],
  key : String,
) -> String raise JcampError {
  match json_field(fields, key) {
    String(text) => text
    _ => reject("JSON_TYPE", key + " must be a string")
  }
}

///|
fn json_double(
  fields : Map[String, Json],
  key : String,
  default : Double,
) -> Double raise JcampError {
  match fields.get(key) {
    Some(Number(n, ..)) => {
      guard finite(n) else { reject("JSON_NUMBER", key + " must be finite") }
      n
    }
    Some(_) => reject("JSON_TYPE", key + " must be a number")
    None => default
  }
}

///|
fn json_int(
  fields : Map[String, Json],
  key : String,
  default : Int32,
) -> Int32 raise JcampError {
  let n = json_double(fields, key, default.to_double())
  guard n.floor() == n && n >= -2147483648.0 && n <= 2147483647.0 else {
    reject("JSON_INTEGER", key + " must be a 32-bit integer")
  }
  n.to_int()
}

///|
pub fn spectrum_from_json(value : Json) -> Spectrum raise JcampError {
  let fields = json_object(
    value,
    [
      "title", "data_type", "x_units", "y_units", "points", "records", "source_line",
    ],
    "spectrum",
  )
  guard json_field(fields, "points") is Array(input) else {
    reject("JSON_TYPE", "points must be an array")
  }
  guard input.length() <= Limits::default().max_points else {
    reject("LIMIT_POINTS", "JSON point count exceeds budget")
  }
  let points : Array[Point] = []
  for item in input {
    let p = json_object(item, ["x", "y"], "point")
    guard json_field(p, "x") is Number(x, ..) && finite(x) else {
      reject("JSON_NUMBER", "point x must be finite")
    }
    let y : Double? = match json_field(p, "y") {
      Null => None
      Number(value, ..) => {
        guard finite(value) else {
          reject("JSON_NUMBER", "point y must be finite or null")
        }
        Some(value)
      }
      _ => reject("JSON_TYPE", "point y must be a number or null")
    }
    points.push({ x, y, })
  }
  let records : Array[Record] = []
  match fields.get("records") {
    Some(Array(items)) => {
      guard items.length() <= Limits::default().max_records else {
        reject("LIMIT_RECORDS", "JSON record count exceeds budget")
      }
      for item in items {
        let r = json_object(item, ["label", "value", "line"], "record")
        let record : Record = {
          label: json_string(r, "label"),
          value: json_string(r, "value"),
          line: json_int(r, "line", 0),
        }
        writable_record(record)
        records.push(record)
      }
    }
    Some(_) => reject("JSON_TYPE", "records must be an array")
    None => ()
  }
  let result : Spectrum = {
    title: json_string(fields, "title"),
    data_type: json_string(fields, "data_type"),
    x_units: json_string(fields, "x_units"),
    y_units: json_string(fields, "y_units"),
    points,
    records,
    source_line: json_int(fields, "source_line", 0),
  }
  checked_spectrum(result)
  result
}

///|
pub fn export_json(spectra : Array[Spectrum]) -> Json raise JcampError {
  guard !spectra.is_empty() && spectra.length() < Limits::default().max_blocks else {
    reject(
      "COLLECTION_SIZE", "JSON export requires a bounded nonempty collection",
    )
  }
  let mut count = 0
  for spectrum in spectra {
    checked_spectrum(spectrum)
    guard spectrum.points.length() <= Limits::default().max_points - count else {
      reject("LIMIT_POINTS", "JSON export exceeds point budget")
    }
    count += spectrum.points.length()
  }
  { "schema": "moonjcamp/spectra/1", "spectra": Json(spectra) }
}

///|
pub fn import_json(value : Json) -> Array[Spectrum] raise JcampError {
  let fields = json_object(value, ["schema", "spectra"], "interchange document")
  guard json_string(fields, "schema") == "moonjcamp/spectra/1" else {
    reject("JSON_SCHEMA", "unsupported interchange schema")
  }
  guard json_field(fields, "spectra") is Array(values) &&
    !values.is_empty() &&
    values.length() < Limits::default().max_blocks else {
    reject("COLLECTION_SIZE", "spectra must be a bounded nonempty array")
  }
  let result : Array[Spectrum] = []
  let mut count = 0
  for value in values {
    let spectrum = spectrum_from_json(value)
    guard spectrum.points.length() <= Limits::default().max_points - count else {
      reject("LIMIT_POINTS", "JSON input exceeds total point budget")
    }
    count += spectrum.points.length()
    result.push(spectrum)
  }
  result
}

///|
pub fn parse_interchange(text : String) -> Array[Spectrum] raise JcampError {
  guard text.length() <= Limits::default().max_chars else {
    reject("LIMIT_TEXT", "JSON input exceeds text budget")
  }
  let value = @json.parse(text[:], reject_duplicate_keys=true) catch {
    _ => reject("JSON_SYNTAX", "invalid JSON or duplicate object key")
  }
  import_json(value)
}

///|
fn parse_write_options(value : Json) -> WriteOptions raise JcampError {
  let fields = json_object(
    value,
    ["encoding", "table", "points_per_line", "x_factor", "y_factor"],
    "write options",
  )
  let encoding = match fields.get("encoding") {
    None | Some(String("affn")) => Plain
    Some(String("pac")) => Packed
    Some(String("sqz")) => Squeezed
    Some(String("difdup")) => Difference
    _ => reject("WRITE_ENCODING", "encoding must be affn, pac, sqz or difdup")
  }
  let table_style = match fields.get("table") {
    None | Some(String("auto")) => Automatic
    Some(String("incremental")) => Incremental
    Some(String("pairs")) => Pairs
    _ => reject("WRITE_TABLE", "table must be auto, incremental or pairs")
  }
  {
    encoding,
    table_style,
    points_per_line: json_int(fields, "points_per_line", 8),
    x_factor: json_double(fields, "x_factor", 1.0),
    y_factor: json_double(fields, "y_factor", 1.0),
  }
}

///|
fn parse_read_options(value : Json) -> ParseOptions raise JcampError {
  let fields = json_object(
    value,
    ["numeric_mode", "max_points", "relative_tolerance", "absolute_tolerance"],
    "read options",
  )
  let numeric_mode = match fields.get("numeric_mode") {
    None | Some(String("auto")) => Auto
    Some(String("affn")) => Affn
    Some(String("asdf")) => Asdf
    _ => reject("NUMERIC_MODE", "numeric_mode must be auto, affn or asdf")
  }
  let options = {
    numeric_mode,
    limits: {
      ..Limits::default(),
      max_points: json_int(fields, "max_points", Limits::default().max_points),
    },
    relative_tolerance: json_double(
      fields,
      "relative_tolerance",
      ParseOptions::default().relative_tolerance,
    ),
    absolute_tolerance: json_double(
      fields,
      "absolute_tolerance",
      ParseOptions::default().absolute_tolerance,
    ),
  }
  check_options(options)
  options
}
