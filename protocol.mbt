///|
fn run_request(request : Json) -> Json raise JcampError {
  guard request is Object(fields) else { reject("REQUEST_OBJECT", "request must be an object") }
  let operation = json_string(fields, "operation")
  let read = parse_read_options(fields.get("read_options").unwrap_or({}))
  let write = parse_write_options(fields.get("write_options").unwrap_or({}))
  match operation {
    "read" => {
      ignore(json_object(request, ["operation", "text", "read_options"], "read request"))
      export_json(read_spectra(json_string(fields, "text"), options=read))
    }
    "inspect" => {
      ignore(json_object(request, ["operation", "text", "read_options"], "inspect request"))
      Json(inspect(json_string(fields, "text"), options=read))
    }
    "write" => {
      ignore(json_object(request, ["operation", "spectrum", "write_options"], "write request"))
      { "text": write_spectrum(spectrum_from_json(json_field(fields, "spectrum")), options=write) }
    }
    "from-json" => {
      ignore(json_object(request, ["operation", "text", "write_options"], "from-json request"))
      let spectra = parse_interchange(json_string(fields, "text"))
      { "text": if spectra.length() == 1 { write_spectrum(spectra[0], options=write) } else { write_collection(spectra, options=write) } }
    }
    "rewrite" => {
      ignore(json_object(request, ["operation", "text", "read_options", "write_options"], "rewrite request"))
      { "text": rewrite_document(parse_document(json_string(fields, "text"), options=read), options=write) }
    }
    "split" => {
      ignore(json_object(request, ["operation", "text", "read_options"], "split request"))
      let document = parse_document(json_string(fields, "text"), options=read)
      let files : Array[Json] = []
      for i, part in split_document(document) {
        files.push({ "name": "spectrum-" + (i + 1).to_string() + ".jdx", "text": render_document(part) })
      }
      { "files": Json(files) }
    }
    "combine" => {
      ignore(json_object(request, ["operation", "texts", "title"], "combine request"))
      guard json_field(fields, "texts") is Array(texts) && !texts.is_empty() && texts.length() < Limits::default().max_blocks else { reject("REQUEST_FILES", "texts must be a bounded nonempty list") }
      let documents : Array[Document] = []
      let mut chars = 0
      for text in texts {
        guard text is String(text) else { reject("JSON_TYPE", "each source must be text") }
        guard text.length() <= Limits::default().max_chars - chars else { reject("LIMIT_TEXT", "combined input exceeds text budget") }
        chars += text.length()
        documents.push(parse_document(text))
      }
      let title = match fields.get("title") { Some(String(title)) => title; None => "Combined documents"; _ => reject("JSON_TYPE", "title must be a string") }
      { "text": render_document(combine_documents(documents, title~)) }
    }
    _ => reject("REQUEST_OPERATION", "unknown operation: " + operation)
  }
}

///|
pub fn handle_request(request : Json) -> Json {
  try {
    { "ok": true, "value": run_request(request) }
  } catch {
    Invalid(diagnostic) => { "ok": false, "error": Json(diagnostic) }
  }
}

///|
pub fn protocol(text : String) -> String {
  let result : Json = try {
    guard text.length() <= 2 * Limits::default().max_chars else { reject("LIMIT_TEXT", "protocol input exceeds budget") }
    let request = try { @json.parse(text[:], reject_duplicate_keys=true) }
      catch { _ => reject("JSON_SYNTAX", "invalid request JSON or duplicate object key") }
    handle_request(request)
  } catch {
    Invalid(diagnostic) => { "ok": false, "error": Json(diagnostic) }
  }
  result.stringify()
}
