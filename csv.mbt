///|
pub(all) struct CsvBundle {
  csv : String
  metadata : Json
} derive(@debug.Debug, ToJson)

///|
fn csv_quote(value : String) -> String {
  if value.contains(",") ||
    value.contains("\"") ||
    value.contains("\n") ||
    value.contains("\r") {
    "\"" + value.replace_all(old="\"", new="\"\"") + "\""
  } else {
    value
  }
}

///|
pub fn export_csv(spectrum : Spectrum) -> CsvBundle raise JcampError {
  checked_spectrum(spectrum)
  let out = StringBuilder()
  out.write_string("x,y\r\n")
  for point in spectrum.points {
    out.write_string(csv_quote(decimal(point.x)) + ",")
    if point.y is Some(y) {
      out.write_string(csv_quote(decimal(y)))
    }
    out.write_string("\r\n")
  }
  {
    csv: out.to_string(),
    metadata: {
      "schema": "moonjcamp/csv/1",
      "title": spectrum.title,
      "data_type": spectrum.data_type,
      "x_units": spectrum.x_units,
      "y_units": spectrum.y_units,
      "records": Json(spectrum.records),
    },
  }
}

///|
pub fn parse_csv(text : String) -> Array[Array[String]] raise JcampError {
  guard text.length() <= Limits::default().max_chars && !text.contains("\u0000") else {
    reject("CSV_LIMIT", "CSV exceeds budget or contains NUL")
  }
  let text = if text.has_prefix("\uFEFF") { text[1:].to_owned() } else { text }
  let rows : Array[Array[String]] = []
  let mut row : Array[String] = []
  let mut field = StringBuilder()
  let mut quoted = false
  let mut closed = false
  let mut started = false
  let mut i = 0
  let mut line = 1
  fn append_field() -> Unit raise JcampError {
    guard row.length() < 16 else {
      reject("CSV_COLUMNS", "CSV column budget exceeded", line~)
    }
    row.push(field.to_string())
    field = StringBuilder()
    closed = false
    started = false
  }
  fn append_row() -> Unit raise JcampError {
    append_field()
    guard rows.length() <= Limits::default().max_points else {
      reject("CSV_ROWS", "CSV row budget exceeded", line~)
    }
    rows.push(row)
    row = []
  }
  while i < text.length() {
    let c = text[i]
    if quoted {
      if c == '"' {
        if i + 1 < text.length() && text[i + 1] == '"' {
          field.write_string("\"")
          i += 2
          continue
        }
        quoted = false
        closed = true
      } else {
        field.write_string(text[i:i + 1].to_owned())
        if c == '\n' {
          line += 1
        }
      }
    } else if c == ',' {
      append_field()
    } else if c == '\r' || c == '\n' {
      append_row()
      if c == '\r' && i + 1 < text.length() && text[i + 1] == '\n' {
        i += 1
      }
      line += 1
    } else if c == '"' {
      guard !started && !closed else {
        reject("CSV_QUOTE", "quote inside an unquoted field", line~)
      }
      quoted = true
      started = true
    } else {
      guard !closed else {
        reject("CSV_QUOTE", "characters after closing quote", line~)
      }
      field.write_string(text[i:i + 1].to_owned())
      started = true
    }
    i += 1
  }
  guard !quoted else { reject("CSV_QUOTE", "unterminated quoted field", line~) }
  if started || closed || !row.is_empty() {
    append_row()
  }
  rows
}

///|
pub fn import_csv(text : String, metadata : Json) -> Spectrum raise JcampError {
  let fields = json_object(
    metadata,
    ["schema", "title", "data_type", "x_units", "y_units", "records"],
    "CSV metadata",
  )
  guard json_string(fields, "schema") == "moonjcamp/csv/1" else {
    reject("CSV_SCHEMA", "unsupported CSV sidecar schema")
  }
  let rows = parse_csv(text)
  guard rows.length() >= 2 && rows[0] == ["x", "y"] else {
    reject(
      "CSV_HEADER", "CSV requires exact x,y header and at least one data row",
    )
  }
  let points : Array[Json] = []
  for i = 1; i < rows.length(); i = i + 1 {
    let row = rows[i]
    guard row.length() == 2 else {
      reject(
        "CSV_ARITY",
        "each row must contain exactly two fields",
        line=i + 1,
      )
    }
    let y : Json = if trim(row[1]) == "" {
      Json::null()
    } else {
      Json(number(row[1], line=i + 1, column=2))
    }
    points.push({ "x": number(row[0], line=i + 1), "y": y })
  }
  spectrum_from_json({
    "title": json_string(fields, "title"),
    "data_type": json_string(fields, "data_type"),
    "x_units": json_string(fields, "x_units"),
    "y_units": json_string(fields, "y_units"),
    "records": fields.get("records").unwrap_or([]),
    "points": Json(points),
  })
}
