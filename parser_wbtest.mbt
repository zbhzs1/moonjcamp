///|
test "records continuations source positions and table rows are separate" {
  let doc = parse_document("$$ comment\n##TITLE=Example\n##JCAMP-DX=5.01\n##DATA TYPE=INFRARED SPECTRUM\n##$VENDOR=first\nsecond\n##XYPOINTS=(XY..XY)\n1,2 $$ note\n##END=\n")
  let b = doc.blocks[0]
  assert_eq(block_title(b), "Example")
  assert_eq(record_value(b.records, "$VENDOR"), Some("first\nsecond"))
  assert_eq(b.tables[0].rows[0].text, "1,2")
  assert_eq(b.tables[0].rows[0].line, 8)
  assert_eq(b.start_line, 2)
  assert_eq(b.end_line, 9)
}

///|
test "LINK children have independent records and matching END scopes" {
  let doc = parse_document("##TITLE=Set\n##DATA TYPE=LINK\n##BLOCKS=2\n##TITLE=A\n##END=\n##TITLE=B\n##END=\n##END=\n")
  assert_eq(document_block_count(doc), 3)
  assert_eq(doc.blocks[0].children.map(block_title), ["A", "B"])
  assert_eq(doc.blocks[0].end_line, 8)
}

///|
test "concatenated root blocks are explicit rather than silently discarded" {
  let doc = parse_document("##TITLE=A\n##END=\n##TITLE=B\n##END=")
  assert_eq(doc.blocks.length(), 2)
}

///|
test "parser rejects unfinished blocks malformed labels and illegal nesting" {
  for input in ["", "garbage", "##TITLE=A", "##TITLE=A\n##BAD\n##END=", "##TITLE=A\n##TITLE=B\n##END=\n##END=", "##TITLE=A\n##END=bad"] {
    let failed = try { ignore(parse_document(input)); false } catch { Invalid(_) => true }
    assert_true(failed)
  }
}

///|
test "structural budgets reject before unbounded nesting or records" {
  let options = { ..ParseOptions::default(), limits: { ..Limits::default(), max_depth: 1 } }
  let failed = try { ignore(parse_document("##TITLE=P\n##DATA TYPE=LINK\n##TITLE=C\n##END=\n##END=", options~)); false } catch { Invalid(d) => d.code == "LIMIT_DEPTH" }
  assert_true(failed)
  let options = { ..ParseOptions::default(), limits: { ..Limits::default(), max_records: 1 } }
  let failed = try { ignore(parse_document("##TITLE=A\n##END=", options~)); false } catch { Invalid(d) => d.code == "LIMIT_RECORDS" }
  assert_true(failed)
}
