///|
test "labels normalize standard spacing without destroying private prefixes" {
  assert_eq(canonical_label("Jcamp-Dx"), "JCAMPDX")
  assert_eq(canonical_label("data type"), "DATATYPE")
  assert_eq(canonical_label(".OBSERVE FREQUENCY"), ".OBSERVEFREQUENCY")
  assert_eq(canonical_label("$vendor_key"), "$VENDORKEY")
}

///|
test "metadata replacement is immutable and removes duplicate values" {
  let records : Array[Record] = [
    { label: "X-FACTOR", value: "2", line: 3, },
    { label: "XFACTOR", value: "3", line: 4, },
  ]
  let result = set_record(records, "XFACTOR", "4")
  assert_eq(result.length(), 1)
  assert_eq(record_value(result, "x factor"), Some("4"))
  assert_eq(records.length(), 2)
}

///|
test "decimal grammar handles packed scientific spelling and finite limits" {
  assert_eq(number("-1.25E+2"), -125.0)
  assert_eq(number("+.5"), 0.5)
  assert_eq(number("3."), 3.0)
  for value in ["NaN", "inf", "0x20", "+", ".", "1E", "1_000", "1e9999"] {
    let failed = try {
      ignore(number(value))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(failed)
  }
}

///|
test "text input normalizes BOM and all line endings" {
  let rows = physical_lines("\uFEFFa\r\nb\rc\n", ParseOptions::default())
  assert_eq(rows.map(r => r.text), ["a", "b", "c", ""])
  assert_eq(rows[2].line, 3)
}
