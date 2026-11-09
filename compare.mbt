///|
#derive(@debug.Debug, ToJson)
pub(all) struct ComparisonIssue {
  code : String
  message : String
  spectrum : Int32
  point : Int32
}

///|
#derive(@debug.Debug, ToJson)
pub(all) struct Comparison {
  equivalent : Bool
  compared_points : Int32
  issue_count : Int32
  truncated : Bool
  issues : Array[ComparisonIssue]
}

///|
pub extend ComparisonIssue with @debug.Debug::{to_repr}

///|
pub extend ComparisonIssue with ToJson::{to_json}

///|
pub extend Comparison with @debug.Debug::{to_repr}

///|
pub extend Comparison with ToJson::{to_json}

///|
pub fn compare_spectra(
  left : Array[Spectrum],
  right : Array[Spectrum],
  options~ : ParseOptions = ParseOptions::default(),
  compare_records~ : Bool = false,
  max_issues~ : Int32 = 100,
) -> Comparison raise JcampError {
  check_options(options)
  guard max_issues >= 1 && max_issues <= 10000 else {
    reject("COMPARE_LIMIT", "max_issues must be between 1 and 10000")
  }
  // Validate aggregate budgets before walking two externally constructed lists.
  ignore(export_json(left))
  ignore(export_json(right))
  let issues : Array[ComparisonIssue] = []
  let mut issue_count = 0
  let mut compared_points = 0
  fn issue(
    code : String,
    message : String,
    spectrum : Int32,
    point : Int32,
  ) -> Unit {
    issue_count += 1
    if issues.length() < max_issues {
      issues.push({ code, message, spectrum, point, })
    }
  }
  if left.length() != right.length() {
    issue("COMPARE_SPECTRA", "spectrum counts differ", -1, -1)
  }
  let count = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for i = 0; i < count; i = i + 1 {
    let a = left[i]
    let b = right[i]
    if a.title != b.title {
      issue("COMPARE_TITLE", "spectrum titles differ", i, -1)
    }
    if canonical_label(a.data_type) != canonical_label(b.data_type) {
      issue("COMPARE_TYPE", "spectrum types differ", i, -1)
    }
    if canonical_label(a.x_units) != canonical_label(b.x_units) ||
      canonical_label(a.y_units) != canonical_label(b.y_units) {
      issue(
        "COMPARE_UNITS", "axis units differ; conversion must be explicit", i, -1,
      )
    }
    if a.points.length() != b.points.length() {
      issue("COMPARE_POINTS", "point counts differ", i, -1)
    }
    if compare_records {
      let derived = [
        "TITLE", "JCAMPDX", "DATATYPE", "DATACLASS", "NPOINTS", "FIRSTX", "LASTX",
        "FIRSTY", "LASTY", "MINX", "MAXX", "MINY", "MAXY", "DELTAX", "XFACTOR", "YFACTOR",
        "XUNITS", "YUNITS",
      ]
      fn descriptors(records : Array[Record]) -> Array[(String, String)] {
        records
        .filter(r => !derived.contains(canonical_label(r.label)))
        .map(r => (canonical_label(r.label), trim(r.value)))
      }
      if descriptors(a.records) != descriptors(b.records) {
        issue("COMPARE_RECORDS", "ordered descriptive records differ", i, -1)
      }
    }
    let points = if a.points.length() < b.points.length() {
      a.points.length()
    } else {
      b.points.length()
    }
    for j = 0; j < points; j = j + 1 {
      compared_points += 1
      if !close(a.points[j].x, b.points[j].x, options) {
        issue("COMPARE_X", "X coordinates differ", i, j)
      }
      if !matching_y(a.points[j].y, b.points[j].y, options) {
        issue("COMPARE_Y", "ordinates or missing-value positions differ", i, j)
      }
    }
  }
  {
    equivalent: issue_count == 0,
    compared_points,
    issue_count,
    truncated: issue_count > issues.length(),
    issues,
  }
}

///|
pub fn compare_documents(
  left : String,
  right : String,
  options~ : ParseOptions = ParseOptions::default(),
  compare_records~ : Bool = false,
  max_issues~ : Int32 = 100,
) -> Comparison raise JcampError {
  compare_spectra(
    read_spectra(left, options~),
    read_spectra(right, options~),
    options~,
    compare_records~,
    max_issues~,
  )
}
