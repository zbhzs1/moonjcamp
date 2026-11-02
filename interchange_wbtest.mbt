///|
test "versioned JSON interchange preserves missing values and private labels" {
  let spectrum = synthetic([{ x: 1.0, y: Some(2.0), }, { x: 2.0, y: None, }])
  assert_true(export_json([spectrum]).stringify().contains("\"y\":null"))
  let result = import_json(export_json([spectrum]))[0]
  assert_eq(result.points, spectrum.points)
  assert_eq(result.records, spectrum.records)
}

///|
test "JSON interchange rejects unknown fields duplicate keys and empty collections" {
  for
    text in [
      "{}", "{\"schema\":\"wrong\",\"spectra\":[]}", "{\"schema\":\"moonjcamp/spectra/1\",\"spectra\":[]}",
      "{\"schema\":\"a\",\"schema\":\"b\",\"spectra\":[]}",
    ] {
    let failed = try {
      ignore(parse_interchange(text))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(failed)
  }
  let result = handle_request({
    "operation": "inspect",
    "text": "",
    "invented": true,
  })
  guard result is { "ok": false, "error": { "code": String(code), .. }, .. } else {
    fail("expected schema rejection")
  }
  assert_eq(code, "JSON_FIELD")
}

///|
test "protocol read write and malformed request envelopes" {
  let source = synthetic([{ x: 1.0, y: Some(2.0), }])
  let response = handle_request({
    "operation": "write",
    "spectrum": Json(source),
  })
  guard response is { "ok": true, "value": { "text": String(text), .. }, .. } else {
    fail("write failed")
  }
  let read = handle_request({ "operation": "read", "text": text })
  guard read is { "ok": true, "value": { "schema": String(schema), .. }, .. } else {
    fail("read failed")
  }
  assert_eq(schema, "moonjcamp/spectra/1")
  assert_true(protocol("not json").contains("JSON_SYNTAX"))
  assert_true(
    protocol("{\"operation\":\"unknown\"}").contains("REQUEST_OPERATION"),
  )
}
