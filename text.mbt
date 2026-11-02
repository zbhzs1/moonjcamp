///|
fn whitespace(c : UInt16) -> Bool {
  c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

///|
fn digit(c : UInt16) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn trim(text : String) -> String {
  let mut first = 0
  let mut last = text.length()
  while first < last && whitespace(text[first]) { first += 1 }
  while last > first && whitespace(text[last - 1]) { last -= 1 }
  text[first:last].to_owned()
}

///|
pub fn canonical_label(label : String) -> String {
  let out = StringBuilder()
  for c in label.iter() {
    if c != ' ' && c != '\t' && c != '-' && c != '_' {
      out.write_char(c)
    }
  }
  out.to_string()[:].to_upper().to_owned()
}

///|
pub fn record_value(records : Array[Record], label : String) -> String? {
  let key = canonical_label(label)
  for record in records {
    if canonical_label(record.label) == key { return Some(record.value) }
  }
  None
}

///|
pub fn set_record(records : Array[Record], label : String, value : String) -> Array[Record] {
  let key = canonical_label(label)
  let result : Array[Record] = []
  let mut replaced = false
  for record in records {
    if canonical_label(record.label) == key {
      if !replaced { result.push({ label: record.label, value, line: record.line }); replaced = true }
    } else { result.push(record) }
  }
  if !replaced { result.push({ label, value, line: 0 }) }
  result
}

///|
fn strip_comment(text : String) -> String {
  match text.find("$$") {
    Some(index) => text[:index].to_owned()
    None => text
  }
}

///|
fn physical_lines(text : String, options : ParseOptions) -> Array[DataLine] raise JcampError {
  check_options(options)
  guard text.length() <= options.limits.max_chars else {
    reject("LIMIT_TEXT", "input exceeds text budget")
  }
  guard !text.contains("\u0000") else { reject("TEXT_NUL", "NUL is not permitted in JCAMP text") }
  let text = if text.has_prefix("\uFEFF") { text[1:].to_owned() } else { text }
  let text = text.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n")
  let result : Array[DataLine] = []
  for value in text.split("\n") {
    let line = result.length() + 1
    guard line <= options.limits.max_lines else { reject("LIMIT_LINES", "too many physical lines", line~) }
    guard value.length() <= options.limits.max_line_chars else { reject("LIMIT_LINE", "physical line exceeds budget", line~) }
    result.push({ text: value.to_owned(), line })
  }
  result
}

///|
fn number(text : String, line~ : Int = 0, column~ : Int = 1) -> Double raise JcampError {
  let text = trim(text)
  guard text != "" else { reject("NUMBER_EMPTY", "expected a number", line~, column~) }
  let mut i = 0
  if text[i] == '+' || text[i] == '-' { i += 1 }
  let mut digits = 0
  while i < text.length() && digit(text[i]) { digits += 1; i += 1 }
  if i < text.length() && text[i] == '.' {
    i += 1
    while i < text.length() && digit(text[i]) { digits += 1; i += 1 }
  }
  guard digits > 0 else { reject("NUMBER_SYNTAX", "number has no digits", line~, column~) }
  if i < text.length() && (text[i] == 'E' || text[i] == 'e') {
    i += 1
    if i < text.length() && (text[i] == '+' || text[i] == '-') { i += 1 }
    let start = i
    while i < text.length() && digit(text[i]) { i += 1 }
    guard i > start else { reject("NUMBER_EXPONENT", "exponent has no digits", line~, column~) }
  }
  guard i == text.length() else { reject("NUMBER_SYNTAX", "invalid numeric characters", line~, column~) }
  let value = try { @string.parse_double(text[:]) } catch { _ => reject("NUMBER_RANGE", "numeric conversion failed", line~, column~) }
  guard finite(value) else { reject("NUMBER_RANGE", "non-finite numeric value", line~, column~) }
  value
}

///|
fn required_number(records : Array[Record], key : String, line : Int) -> Double raise JcampError {
  match record_value(records, key) {
    Some(value) => number(value, line~)
    None => reject("HEADER_MISSING", "missing " + key, line~)
  }
}

///|
fn optional_number(records : Array[Record], key : String, default : Double, line : Int) -> Double raise JcampError {
  match record_value(records, key) {
    Some(value) => number(value, line~)
    None => default
  }
}

///|
fn point_count(records : Array[Record], options : ParseOptions, line : Int) -> Int raise JcampError {
  let count = required_number(records, "NPOINTS", line)
  guard count >= 1.0 && count.floor() == count && count <= options.limits.max_points.to_double() else {
    reject("POINT_COUNT", "NPOINTS must be a positive integer within the point budget", line~)
  }
  count.to_int()
}
