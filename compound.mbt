///|
fn render_block(out : StringBuilder, block : Block, depth : Int) -> Unit raise JcampError {
  guard depth <= Limits::default().max_depth else { reject("LIMIT_DEPTH", "rendering depth budget exceeded") }
  for record in block.records { append_record(out, record) }
  for table in block.tables {
    append_record(out, { label: table.label, value: table.descriptor, line: table.line })
    for row in table.rows {
      guard !trim(row.text).has_prefix("##") && !row.text.contains("\n") && !row.text.contains("\r") else { reject("WRITE_INJECTION", "data row would inject a label or extra line", line=row.line) }
      out.write_string(row.text + "\n")
    }
  }
  for child in block.children { render_block(out, child, depth + 1) }
  out.write_string("##END=\n")
}

///|
pub fn render_document(document : Document) -> String raise JcampError {
  ignore(spectra_from_document(document))
  let out = StringBuilder()
  for block in document.blocks { render_block(out, block, 1) }
  let text = out.to_string()
  ignore(read_spectra(text))
  text
}

///|
pub fn write_collection(spectra : Array[Spectrum], title~ : String = "Spectral collection", options~ : WriteOptions = WriteOptions::default()) -> String raise JcampError {
  guard !spectra.is_empty() && spectra.length() < Limits::default().max_blocks else { reject("COLLECTION_SIZE", "collection requires a bounded nonempty list of spectra") }
  let out = StringBuilder()
  for record in [
    { label: "TITLE", value: title, line: 0 },
    { label: "JCAMP-DX", value: "5.01", line: 0 },
    { label: "DATA TYPE", value: "LINK", line: 0 },
    { label: "BLOCKS", value: spectra.length().to_string(), line: 0 },
  ] { append_record(out, record) }
  let mut total = 0
  for spectrum in spectra {
    guard spectrum.points.length() <= Limits::default().max_points - total else { reject("LIMIT_POINTS", "collection point budget exceeded") }
    total += spectrum.points.length()
    out.write_string(write_spectrum(spectrum, options~))
  }
  out.write_string("##END=\n")
  out.to_string()
}

///|
pub fn combine_documents(documents : Array[Document], title~ : String = "Combined documents") -> Document raise JcampError {
  guard !documents.is_empty() else { reject("COLLECTION_EMPTY", "no documents to combine") }
  let children : Array[Block] = []
  for document in documents {
    ignore(spectra_from_document(document))
    for block in document.blocks {
      guard children.length() + 1 < Limits::default().max_blocks else { reject("LIMIT_BLOCKS", "combined root block budget exceeded") }
      children.push(block)
    }
  }
  let root : Block = {
    records: [
      { label: "TITLE", value: title, line: 0 },
      { label: "JCAMP-DX", value: "5.01", line: 0 },
      { label: "DATA TYPE", value: "LINK", line: 0 },
      { label: "BLOCKS", value: children.length().to_string(), line: 0 },
    ], tables: [], children, start_line: 0, end_line: 0,
  }
  let result : Document = { blocks: [root] }
  ignore(spectra_from_document(result))
  result
}

///|
pub fn split_document(document : Document) -> Array[Document] raise JcampError {
  ignore(spectra_from_document(document))
  let result : Array[Document] = []
  fn visit(block : Block, ancestors : Array[Array[Record]], depth : Int) -> Unit raise JcampError {
    guard depth <= Limits::default().max_depth else { reject("LIMIT_DEPTH", "splitting depth budget exceeded") }
    if canonical_label(block_kind(block)) == "LINK" {
      let chain = ancestors + [block.records]
      for child in block.children { visit(child, chain, depth + 1) }
    } else {
      let records = if ancestors.is_empty() { block.records.copy() } else {
        guard record_value(block.records, "$MOONJCAMP.CONTAINERS") is None else { reject("PROVENANCE_COLLISION", "source already contains reserved container provenance", line=block.start_line) }
        set_record(block.records, "$MOONJCAMP.CONTAINERS", Json(ancestors).stringify())
      }
      result.push({ blocks: [{ ..block, records }] })
    }
  }
  for block in document.blocks { visit(block, [], 1) }
  result
}

///|
pub fn rewrite_document(document : Document, options~ : WriteOptions = WriteOptions::default()) -> String raise JcampError {
  ignore(spectra_from_document(document))
  let out = StringBuilder()
  fn visit(block : Block, depth : Int) -> Unit raise JcampError {
    guard depth <= Limits::default().max_depth else { reject("LIMIT_DEPTH", "rewriting depth budget exceeded") }
    if canonical_label(block_kind(block)) == "LINK" {
      for record in block.records { append_record(out, record) }
      for child in block.children { visit(child, depth + 1) }
      out.write_string("##END=\n")
    } else { out.write_string(write_spectrum(spectrum_from_block(block), options~)) }
  }
  for block in document.blocks { visit(block, 1) }
  out.to_string()
}
