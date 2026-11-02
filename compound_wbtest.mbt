///|
test "raw rendering retains factors coded rows and private metadata" {
  let input = header() +
    "##$NOTE=original metadata\n##XYDATA=(X++(Y..Y))\n100 A0JT\n102 A2JT\n##END=\n"
  let output = render_document(parse_document(input))
  assert_eq(read_spectra(output)[0].points, read_spectra(input)[0].points)
  assert_true(output.contains("100 A0JT"))
  assert_true(output.contains("##$NOTE=original metadata"))
}

///|
test "nested collections split without discarding ancestor labels" {
  let a = synthetic([{ x: 1.0, y: Some(2.0), }])
  let leaf = parse_document(write_spectrum(a))
  let inner = combine_documents([leaf], title="inner")
  let outer = combine_documents([inner, leaf], title="outer")
  let split = split_document(outer)
  assert_eq(split.length(), 2)
  let ancestors = record_value(
    split[0].blocks[0].records,
    "$MOONJCAMP.CONTAINERS",
  ).unwrap()
  assert_true(ancestors.contains("outer") && ancestors.contains("inner"))
  for document in split {
    assert_eq(read_spectra(render_document(document))[0].points, a.points)
  }
}

///|
test "collection rewriting preserves the compound tree" {
  let source = synthetic(
    Array::makei(6, i => { x: i.to_double(), y: Some(i.to_double()), }),
  )
  let input = write_collection([source, source], title="pair")
  let doc = parse_document(input)
  let rewritten = rewrite_document(doc, options={
    ..WriteOptions::default(),
    encoding: Difference,
    points_per_line: 2,
  })
  assert_eq(document_block_count(parse_document(rewritten)), 3)
  assert_eq(read_spectra(rewritten).length(), 2)
  assert_eq(read_spectra(rewritten)[1].points, source.points)
}

///|
test "LINK cardinality and reserved provenance collision are rejected" {
  let source = synthetic([{ x: 1.0, y: Some(1.0), }])
  let input = write_collection([source])
  assert_true(!inspect(input.replace_all(old="BLOCKS=1", new="BLOCKS=2")).valid)
  let source = {
    ..source,
    records: [
      { label: "$MOONJCAMP.CONTAINERS", value: "source value", line: 0, },
    ],
  }
  let input = parse_document(write_collection([source]))
  let failed = try {
    ignore(split_document(input))
    false
  } catch {
    Invalid(d) => d.code == "PROVENANCE_COLLISION"
  }
  assert_true(failed)
}
