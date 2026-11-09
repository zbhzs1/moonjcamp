///|
fn run_request(request : Json) -> Json raise JcampError {
  guard request is Object(fields) else {
    reject("REQUEST_OBJECT", "request must be an object")
  }
  let operation = json_string(fields, "operation")
  let read = parse_read_options(fields.get("read_options").unwrap_or({}))
  let write = parse_write_options(fields.get("write_options").unwrap_or({}))
  match operation {
    "export-ir" => {
      ignore(
        json_object(
          request,
          ["operation", "text", "read_options", "write_options"],
          "IR normalization request",
        ),
      )
      let spectra = read_spectra(json_string(fields, "text"), options=read)
      guard spectra.length() == 1 else {
        reject("IR_SINGLE", "split compound spectra before strict IR export")
      }
      { "text": write_ir_424(spectra[0], options=write) }
    }
    "validate-ir" => {
      ignore(
        json_object(
          request,
          ["operation", "text", "read_options", "pure_compound"],
          "IR validation request",
        ),
      )
      let pure_compound = match fields.get("pure_compound") {
        None => false
        Some(True) => true
        Some(False) => false
        _ => reject("JSON_TYPE", "pure_compound must be a boolean")
      }
      Json(
        validate_ir_424(
          json_string(fields, "text"),
          options=read,
          pure_compound~,
        ),
      )
    }
    "write-ir" => {
      ignore(
        json_object(
          request,
          ["operation", "spectrum", "write_options", "pure_compound"],
          "IR export request",
        ),
      )
      let pure_compound = match fields.get("pure_compound") {
        None => false
        Some(True) => true
        Some(False) => false
        _ => reject("JSON_TYPE", "pure_compound must be a boolean")
      }
      {
        "text": write_ir_424(
          spectrum_from_json(json_field(fields, "spectrum")),
          options=write,
          pure_compound~,
        ),
      }
    }
    "read" => {
      ignore(
        json_object(
          request,
          ["operation", "text", "read_options"],
          "read request",
        ),
      )
      export_json(read_spectra(json_string(fields, "text"), options=read))
    }
    "audit" => {
      ignore(
        json_object(
          request,
          ["operation", "text", "read_options"],
          "audit request",
        ),
      )
      Json(audit(json_string(fields, "text"), options=read))
    }
    "inspect" => {
      ignore(
        json_object(
          request,
          ["operation", "text", "read_options"],
          "inspect request",
        ),
      )
      Json(inspect(json_string(fields, "text"), options=read))
    }
    "summary" => {
      ignore(
        json_object(
          request,
          ["operation", "text", "read_options", "policy"],
          "summary request",
        ),
      )
      let policy = parse_quality_policy(fields.get("policy").unwrap_or({}))
      let summaries : Array[Summary] = []
      for spectrum in read_spectra(json_string(fields, "text"), options=read) {
        summaries.push(summarize(spectrum, policy~))
      }
      {
        "spectra": Json(summaries),
        "accepted": summaries.iter().all(s => s.accepted),
      }
    }
    "batch" => {
      ignore(
        json_object(
          request,
          ["operation", "inputs", "read_options", "policy"],
          "batch request",
        ),
      )
      guard json_field(fields, "inputs") is Array(values) &&
        values.length() <= read.limits.max_blocks else {
        reject("BATCH_SIZE", "inputs must be a bounded array")
      }
      let inputs : Array[BatchInput] = []
      for value in values {
        let input = json_object(value, ["name", "text"], "batch input")
        inputs.push({
          name: json_string(input, "name"),
          text: json_string(input, "text"),
        })
      }
      Json(
        inspect_batch(
          inputs,
          policy=parse_quality_policy(fields.get("policy").unwrap_or({})),
          options=read,
        ),
      )
    }
    "to-csv" => {
      ignore(
        json_object(
          request,
          ["operation", "text", "read_options"],
          "CSV export request",
        ),
      )
      let spectra = read_spectra(json_string(fields, "text"), options=read)
      guard spectra.length() == 1 else {
        reject("CSV_SINGLE", "split a compound document before CSV export")
      }
      Json(export_csv(spectra[0]))
    }
    "from-csv" => {
      ignore(
        json_object(
          request,
          ["operation", "text", "metadata", "metadata_text", "write_options"],
          "CSV import request",
        ),
      )
      {
        "text": write_spectrum(
          import_csv(
            json_string(fields, "text"),
            nested_json(fields, "metadata"),
          ),
          options=write,
        ),
      }
    }
    "transform" => {
      ignore(
        json_object(
          request,
          [
            "operation", "text", "actions", "actions_text", "read_options", "write_options",
          ],
          "transform request",
        ),
      )
      guard nested_json(fields, "actions") is Array(actions) &&
        !actions.is_empty() &&
        actions.length() <= 100 else {
        reject(
          "TRANSFORM_ACTIONS", "actions must contain between 1 and 100 operations",
        )
      }
      let spectra = read_spectra(json_string(fields, "text"), options=read)
      let result : Array[Spectrum] = []
      let mut total = 0
      for spectrum in spectra {
        let mut value = spectrum
        for action in actions {
          value = apply_action(value, action)
        }
        guard value.points.length() <= read.limits.max_points - total else {
          reject("LIMIT_POINTS", "transformed collection exceeds point budget")
        }
        total += value.points.length()
        result.push(value)
      }
      {
        "text": if result.length() == 1 {
          write_spectrum(result[0], options=write)
        } else {
          write_collection(result, options=write)
        },
      }
    }
    "write" => {
      ignore(
        json_object(
          request,
          ["operation", "spectrum", "write_options"],
          "write request",
        ),
      )
      {
        "text": write_spectrum(
          spectrum_from_json(json_field(fields, "spectrum")),
          options=write,
        ),
      }
    }
    "verify" => {
      ignore(
        json_object(
          request,
          ["operation", "texts", "read_options"],
          "verify request",
        ),
      )
      guard json_field(fields, "texts") is [String(left), String(right)] else {
        reject("COMPARE_FILES", "verify requires exactly two text inputs")
      }
      Json(compare_documents(left, right, options=read))
    }
    "from-json" => {
      ignore(
        json_object(
          request,
          ["operation", "text", "write_options"],
          "from-json request",
        ),
      )
      let spectra = parse_interchange(json_string(fields, "text"))
      {
        "text": if spectra.length() == 1 {
          write_spectrum(spectra[0], options=write)
        } else {
          write_collection(spectra, options=write)
        },
      }
    }
    "rewrite" => {
      ignore(
        json_object(
          request,
          ["operation", "text", "read_options", "write_options"],
          "rewrite request",
        ),
      )
      {
        "text": rewrite_document(
          parse_document(json_string(fields, "text"), options=read),
          options=write,
          read_options=read,
        ),
      }
    }
    "split" => {
      ignore(
        json_object(
          request,
          ["operation", "text", "read_options"],
          "split request",
        ),
      )
      let document = parse_document(json_string(fields, "text"), options=read)
      let files : Array[Json] = []
      for i, part in split_document(document, read_options=read) {
        files.push({
          "name": "spectrum-" + (i + 1).to_string() + ".jdx",
          "text": render_document(part, read_options=read),
        })
      }
      { "files": Json(files) }
    }
    "combine" => {
      ignore(
        json_object(request, ["operation", "texts", "title"], "combine request"),
      )
      guard json_field(fields, "texts") is Array(texts) &&
        !texts.is_empty() &&
        texts.length() < Limits::default().max_blocks else {
        reject("REQUEST_FILES", "texts must be a bounded nonempty list")
      }
      let documents : Array[Document] = []
      let mut chars = 0
      for text in texts {
        guard text is String(text) else {
          reject("JSON_TYPE", "each source must be text")
        }
        guard text.length() <= Limits::default().max_chars - chars else {
          reject("LIMIT_TEXT", "combined input exceeds text budget")
        }
        chars += text.length()
        documents.push(parse_document(text))
      }
      let title = match fields.get("title") {
        Some(String(title)) => title
        None => "Combined documents"
        _ => reject("JSON_TYPE", "title must be a string")
      }
      { "text": render_document(combine_documents(documents, title~)) }
    }
    _ => reject("REQUEST_OPERATION", "unknown operation: " + operation)
  }
}

///|
fn nested_json(
  fields : Map[String, Json],
  key : String,
) -> Json raise JcampError {
  match (fields.get(key), fields.get(key + "_text")) {
    (Some(value), None) => value
    (None, Some(String(text))) => {
      guard text.length() <= Limits::default().max_chars else {
        reject("LIMIT_TEXT", "nested JSON exceeds text budget")
      }
      @json.parse(text[:], reject_duplicate_keys=true) catch {
        _ =>
          reject("JSON_SYNTAX", "invalid nested JSON or duplicate object key")
      }
    }
    _ =>
      reject(
        "JSON_FIELD",
        "provide exactly one of " + key + " or " + key + "_text",
      )
  }
}

///|
fn apply_action(
  spectrum : Spectrum,
  action : Json,
) -> Spectrum raise JcampError {
  guard action is Object(fields) else {
    reject("JSON_OBJECT", "transform action must be an object")
  }
  let operation = json_string(fields, "operation")
  fn required_double(key : String) -> Double raise JcampError {
    ignore(json_field(fields, key))
    json_double(fields, key, 0.0)
  }
  match operation {
    "edit-metadata" => {
      ignore(json_object(action, ["operation", "edits"], "metadata action"))
      edit_metadata(spectrum, parse_metadata_edits(json_field(fields, "edits")))
    }
    "crop" => {
      ignore(
        json_object(action, ["operation", "minimum", "maximum"], "crop action"),
      )
      crop(spectrum, required_double("minimum"), required_double("maximum"))
    }
    "resample" => {
      ignore(
        json_object(
          action,
          ["operation", "start", "end", "count"],
          "resample action",
        ),
      )
      ignore(json_field(fields, "count"))
      resample(
        spectrum,
        required_double("start"),
        required_double("end"),
        json_int(fields, "count", 0),
      )
    }
    "convert-x" => {
      ignore(
        json_object(action, ["operation", "target"], "X conversion action"),
      )
      convert_x(spectrum, json_string(fields, "target"))
    }
    "convert-y" => {
      ignore(
        json_object(action, ["operation", "target"], "Y conversion action"),
      )
      convert_y(spectrum, json_string(fields, "target"))
    }
    _ => reject("TRANSFORM_OPERATION", "unknown transform: " + operation)
  }
}

///|
pub fn handle_request(request : Json) -> Json {
  { "ok": true, "value": run_request(request) } catch {
    Invalid(diagnostic) => { "ok": false, "error": Json(diagnostic) }
  }
}

///|
pub fn protocol(text : String) -> String {
  let result : Json = try {
    guard text.length() <= 2 * Limits::default().max_chars else {
      reject("LIMIT_TEXT", "protocol input exceeds budget")
    }
    let request = @json.parse(text[:], reject_duplicate_keys=true) catch {
      _ => reject("JSON_SYNTAX", "invalid request JSON or duplicate object key")
    }
    handle_request(request)
  } catch {
    Invalid(diagnostic) => { "ok": false, "error": Json(diagnostic) }
  }
  result.stringify()
}
