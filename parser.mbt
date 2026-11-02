///|
priv struct ParseState {
  rows : Array[DataLine]
  options : ParseOptions
  mut cursor : Int32
  mut blocks : Int32
  mut records : Int32
}

///|
fn label_record(row : DataLine) -> Record raise JcampError {
  let text = trim(strip_comment(row.text))
  guard text.has_prefix("##") else {
    reject("LABEL_PREFIX", "expected ## label", line=row.line)
  }
  guard text.find("=") is Some(index) && index >= 3 else {
    reject(
      "LABEL_EQUALS",
      "label requires a nonempty name and =",
      line=row.line,
    )
  }
  let label = trim(text[2:index].to_owned())
  guard canonical_label(label) != "" &&
    label.iter().all(c => c >= ' ' && c != '\u007f' && c != '#') else {
    reject("LABEL_NAME", "invalid label name", line=row.line)
  }
  { label, value: trim(text[index + 1:].to_owned()), line: row.line, }
}

///|
fn table_label(key : String) -> Bool {
  key == "XYDATA" ||
  key == "XYPOINTS" ||
  key == "XYPAIRS" ||
  key == "PEAKTABLE" ||
  key == "DATATABLE"
}

///|
fn read_block(state : ParseState, depth : Int32) -> Block raise JcampError {
  let first = label_record(state.rows[state.cursor])
  guard canonical_label(first.label) == "TITLE" else {
    reject("BLOCK_TITLE", "every block must begin with TITLE", line=first.line)
  }
  guard depth <= state.options.limits.max_depth else {
    reject("LIMIT_DEPTH", "compound nesting budget exceeded", line=first.line)
  }
  state.blocks += 1
  guard state.blocks <= state.options.limits.max_blocks else {
    reject("LIMIT_BLOCKS", "block budget exceeded", line=first.line)
  }
  state.records += 1
  let records = [first]
  let tables : Array[DataTable] = []
  let children : Array[Block] = []
  let mut active_table : DataTable? = None
  state.cursor += 1
  while state.cursor < state.rows.length() {
    let row = state.rows[state.cursor]
    let text = trim(strip_comment(row.text))
    if text == "" {
      state.cursor += 1
      continue
    }
    if text.has_prefix("##") {
      let record = label_record(row)
      let key = canonical_label(record.label)
      if key == "TITLE" {
        guard record_value(records, "DATA TYPE") is Some(kind) &&
          canonical_label(kind) == "LINK" else {
          reject(
            "NESTED_BLOCK",
            "nested TITLE is only permitted inside a LINK block",
            line=row.line,
          )
        }
        guard tables.is_empty() else {
          reject(
            "LINK_TABLE",
            "LINK blocks cannot contain a numeric table",
            line=row.line,
          )
        }
        children.push(read_block(state, depth + 1))
        active_table = None
        continue
      }
      state.records += 1
      guard state.records <= state.options.limits.max_records else {
        reject("LIMIT_RECORDS", "record budget exceeded", line=row.line)
      }
      if key == "END" {
        guard record.value == "" else {
          reject("END_VALUE", "END must not have a value", line=row.line)
        }
        state.cursor += 1
        return {
          records,
          tables,
          children,
          start_line: first.line,
          end_line: row.line,
        }
      }
      if table_label(key) {
        let table : DataTable = {
          label: record.label,
          descriptor: record.value,
          rows: [],
          line: row.line,
        }
        tables.push(table)
        active_table = Some(table)
      } else {
        records.push(record)
        active_table = None
      }
      state.cursor += 1
      continue
    }
    match active_table {
      Some(table) => table.rows.push({ text, line: row.line, })
      None => {
        guard !records.is_empty() && children.is_empty() else {
          reject(
            "ORPHAN_TEXT",
            "text is not attached to a label or data table",
            line=row.line,
          )
        }
        let index = records.length() - 1
        let previous = records[index]
        records[index] = { ..previous, value: previous.value + "\n" + text, }
      }
    }
    state.cursor += 1
  }
  reject("END_MISSING", "block has no closing END", line=first.line)
}

///|
pub fn parse_document(
  text : String,
  options~ : ParseOptions = ParseOptions::default(),
) -> Document raise JcampError {
  let rows = physical_lines(text, options)
  let state : ParseState = { rows, options, cursor: 0, blocks: 0, records: 0, }
  let blocks : Array[Block] = []
  while state.cursor < rows.length() {
    let row = rows[state.cursor]
    if trim(strip_comment(row.text)) == "" {
      state.cursor += 1
      continue
    }
    blocks.push(read_block(state, 1))
  }
  guard !blocks.is_empty() else {
    reject("DOCUMENT_EMPTY", "document contains no JCAMP blocks")
  }
  { blocks, }
}

///|
pub fn block_title(block : Block) -> String {
  record_value(block.records, "TITLE").unwrap_or("")
}

///|
pub fn block_kind(block : Block) -> String {
  record_value(block.records, "DATA TYPE").unwrap_or("")
}

///|
pub fn document_block_count(
  document : Document,
  max_depth~ : Int32 = 16,
) -> Int32 raise JcampError {
  guard max_depth > 0 && max_depth <= 128 else {
    reject("OPTION_DEPTH", "invalid maximum depth")
  }
  fn count(blocks : Array[Block], depth : Int32) -> Int32 raise JcampError {
    guard depth <= max_depth else {
      reject("LIMIT_DEPTH", "document nesting budget exceeded")
    }
    let mut total = blocks.length()
    for block in blocks {
      if !block.children.is_empty() {
        let nested = count(block.children, depth + 1)
        guard nested <= 1000000 - total else {
          reject("LIMIT_BLOCKS", "document block count exceeds safety budget")
        }
        total += nested
      }
    }
    total
  }
  count(document.blocks, 1)
}
