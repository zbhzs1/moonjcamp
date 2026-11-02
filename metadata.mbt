///|
pub(all) enum MetadataEdit {
  Set(String, String)
  Remove(String)
} derive(@debug.Debug)

///|
pub extend MetadataEdit with @debug.Debug::{to_repr}

///|
fn protected_label(key : String) -> Bool {
  [
    "JCAMPDX", "DATATYPE", "DATACLASS", "END", "BLOCKS", "XYDATA", "XYPOINTS", "XYPAIRS",
    "PEAKTABLE", "DATATABLE", "NTUPLES", "NPOINTS", "FIRSTX", "LASTX", "FIRSTY",
    "LASTY", "MINX", "MAXX", "MINY", "MAXY", "DELTAX", "XFACTOR", "YFACTOR", "XUNITS",
    "YUNITS",
  ].contains(key) ||
  key.has_prefix("$MOONJCAMP.")
}

///|
pub fn edit_metadata(
  spectrum : Spectrum,
  edits : Array[MetadataEdit],
) -> Spectrum raise JcampError {
  checked_spectrum(spectrum)
  guard !edits.is_empty() && edits.length() <= 100 else {
    reject("METADATA_EDITS", "metadata editing requires 1..100 changes")
  }
  let keys : Map[String, Bool] = Map([])
  let mut records = spectrum.records.copy()
  let mut title = spectrum.title
  let changes : Array[Json] = []
  for edit in edits {
    let label = match edit {
      Set(label, _) | Remove(label) => label
    }
    let key = canonical_label(label)
    writable_record({ label, value: "", line: 0, })
    guard key != "" && !keys.contains(key) else {
      reject(
        "METADATA_DUPLICATE", "metadata edit keys must be nonempty and unique",
      )
    }
    guard !protected_label(key) else {
      reject(
        "METADATA_PROTECTED",
        "derived, structural, unit and provenance labels require a dedicated operation: " +
        label,
      )
    }
    keys[key] = true
    match edit {
      Set(label, value) => {
        writable_record({ label, value, line: 0, })
        if key == "TITLE" {
          guard trim(value) != "" && !value.contains("\n") else {
            reject("METADATA_TITLE", "title must be nonempty and single-line")
          }
          title = value
        }
        records = set_record(records, label, value)
        changes.push({ "action": "set", "label": label, "value": value })
      }
      Remove(_) => {
        guard key != "TITLE" else {
          reject("METADATA_TITLE", "TITLE cannot be removed")
        }
        records = remove_records(records, [key])
        changes.push({ "action": "remove", "label": label })
      }
    }
    guard records.length() <= Limits::default().max_records else {
      reject("LIMIT_RECORDS", "metadata record budget exceeded")
    }
  }
  let updated = transformed(
    { ..spectrum, title, records, },
    spectrum.points.copy(),
    { "operation": "edit-metadata", "changes": Json(changes) },
  )
  // Use the same normalization and profile checks as a file written to disk.
  { ..read_spectra(write_spectrum(updated))[0], source_line: 0, }
}

///|
fn parse_metadata_edits(value : Json) -> Array[MetadataEdit] raise JcampError {
  guard value is Array(items) && items.length() <= 100 else {
    reject("METADATA_EDITS", "edits must be a bounded array")
  }
  let edits : Array[MetadataEdit] = []
  for item in items {
    let fields = json_object(
      item,
      ["action", "label", "value"],
      "metadata edit",
    )
    let label = json_string(fields, "label")
    match json_string(fields, "action") {
      "set" => edits.push(Set(label, json_string(fields, "value")))
      "remove" => {
        guard fields.get("value") is None else {
          reject("JSON_FIELD", "remove edit must not include a value")
        }
        edits.push(Remove(label))
      }
      _ => reject("METADATA_ACTION", "metadata action must be set or remove")
    }
  }
  edits
}
