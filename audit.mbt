///|
#derive(@debug.Debug, ToJson)
pub(all) struct AuditPolicy {
  require_origin : Bool
  require_owner : Bool
  check_extrema : Bool
  check_nmr_metadata : Bool
  max_diagnostics : Int32
}

///|
pub fn AuditPolicy::default() -> AuditPolicy {
  {
    require_origin: false,
    require_owner: false,
    check_extrema: true,
    check_nmr_metadata: true,
    max_diagnostics: 100,
  }
}

///|
#derive(@debug.Debug, ToJson)
pub(all) struct AuditReport {
  valid : Bool
  spectra : Int32
  errors : Int32
  warnings : Int32
  truncated : Bool
  diagnostics : Array[Diagnostic]
}

///|
pub extend AuditPolicy with @debug.Debug::{to_repr}

///|
pub extend AuditPolicy with ToJson::{to_json}

///|
pub extend AuditReport with @debug.Debug::{to_repr}

///|
pub extend AuditReport with ToJson::{to_json}

///|
priv struct Auditor {
  policy : AuditPolicy
  options : ParseOptions
  diagnostics : Array[Diagnostic]
  mut errors : Int32
  mut warnings : Int32
}

///|
fn Auditor::add(
  self : Auditor,
  severity : Severity,
  code : String,
  message : String,
  line : Int32,
) -> Unit {
  if severity == Error {
    self.errors += 1
  } else {
    self.warnings += 1
  }
  if self.diagnostics.length() < self.policy.max_diagnostics {
    self.diagnostics.push({ severity, code, message, line, column: 1, })
  }
}

///|
fn Auditor::declared(
  self : Auditor,
  spectrum : Spectrum,
  key : String,
  expected : Double?,
) -> Unit {
  for record in spectrum.records {
    if canonical_label(record.label) != key {
      continue
    }
    try {
      let value = number(record.value, line=record.line)
      match expected {
        None =>
          self.add(
            Error,
            "AUDIT_EMPTY_ORDINATES",
            key + " is declared but all corresponding values are missing",
            record.line,
          )
        Some(expected) =>
          if !close(value, expected, self.options) {
            self.add(
              Error,
              "AUDIT_DERIVED_VALUE",
              key + " differs from decoded data in " + spectrum.title,
              record.line,
            )
          }
      }
    } catch {
      Invalid(d) => self.add(d.severity, d.code, d.message, d.line)
    }
  }
}

///|
fn Auditor::spectrum(self : Auditor, spectrum : Spectrum) -> Unit {
  let seen : Map[String, Bool] = Map([])
  for record in spectrum.records {
    let key = canonical_label(record.label)
    if seen.contains(key) {
      self.add(
        Warning,
        "AUDIT_DUPLICATE_LABEL",
        "repeated descriptive label: " + record.label,
        record.line,
      )
    }
    seen[key] = true
    if trim(record.value) == "" {
      self.add(
        Warning,
        "AUDIT_EMPTY_LABEL",
        "empty descriptive value: " + record.label,
        record.line,
      )
    }
  }
  for
    (key, required) in [
      ("ORIGIN", self.policy.require_origin),
      ("OWNER", self.policy.require_owner),
    ] {
    if record_value(spectrum.records, key).map(trim).unwrap_or("") == "" {
      self.add(
        if required {
          Error
        } else {
          Warning
        },
        "AUDIT_PROVENANCE",
        "missing " + key + " in " + spectrum.title,
        spectrum.source_line,
      )
    }
  }
  if self.policy.check_extrema {
    let mut xmin = spectrum.points[0].x
    let mut xmax = xmin
    let mut ymin : Double? = None
    let mut ymax : Double? = None
    for p in spectrum.points {
      if p.x < xmin {
        xmin = p.x
      }
      if p.x > xmax {
        xmax = p.x
      }
      if p.y is Some(y) {
        ymin = match ymin {
          None => Some(y)
          Some(a) => Some(if y < a { y } else { a })
        }
        ymax = match ymax {
          None => Some(y)
          Some(a) => Some(if y > a { y } else { a })
        }
      }
    }
    self.declared(spectrum, "MINX", Some(xmin))
    self.declared(spectrum, "MAXX", Some(xmax))
    self.declared(spectrum, "MINY", ymin)
    self.declared(spectrum, "MAXY", ymax)
    self.declared(
      spectrum,
      "LASTY",
      spectrum.points[spectrum.points.length() - 1].y,
    )
  }
  if self.policy.check_nmr_metadata &&
    canonical_label(spectrum.data_type) == "NMRSPECTRUM" {
    match record_value(spectrum.records, ".OBSERVE FREQUENCY") {
      None =>
        self.add(
          Warning,
          "AUDIT_NMR_FREQUENCY",
          "NMR spectrum has no observe frequency; PPM/HZ calibration cannot be inferred",
          spectrum.source_line,
        )
      Some(raw) =>
        try {
          if number(raw) <= 0.0 {
            self.add(
              Error,
              "AUDIT_NMR_FREQUENCY",
              "observe frequency must be positive",
              spectrum.source_line,
            )
          }
        } catch {
          Invalid(d) =>
            self.add(
              Error,
              "AUDIT_NMR_FREQUENCY",
              d.message,
              spectrum.source_line,
            )
        }
    }
    if record_value(spectrum.records, ".OBSERVE NUCLEUS")
      .map(trim)
      .unwrap_or("") ==
      "" {
      self.add(
        Warning,
        "AUDIT_NMR_NUCLEUS",
        "NMR spectrum has no observe nucleus",
        spectrum.source_line,
      )
    }
  }
  for key in ["DATE", "TIME", "LONGDATE"] {
    if record_value(spectrum.records, key) is Some(value) {
      if trim(value) == "" || value.contains("\n") {
        self.add(
          Warning,
          "AUDIT_DATE",
          key + " is empty or multiline; timestamp not interpreted",
          spectrum.source_line,
        )
      }
    }
  }
}

///|
pub fn audit_document(
  document : Document,
  policy~ : AuditPolicy = AuditPolicy::default(),
  options~ : ParseOptions = ParseOptions::default(),
) -> AuditReport raise JcampError {
  guard policy.max_diagnostics >= 1 && policy.max_diagnostics <= 10000 else {
    reject("AUDIT_LIMIT", "max_diagnostics must be between 1 and 10000")
  }
  let spectra = spectra_from_document(document, options~)
  let auditor : Auditor = {
    policy,
    options,
    diagnostics: [],
    errors: 0,
    warnings: 0,
  }
  let titles : Map[String, Bool] = Map([])
  for spectrum in spectra {
    if titles.contains(spectrum.title) {
      auditor.add(
        Warning,
        "AUDIT_DUPLICATE_TITLE",
        "duplicate title; use document paths instead of title as identifier",
        spectrum.source_line,
      )
    }
    titles[spectrum.title] = true
    auditor.spectrum(spectrum)
  }
  {
    valid: auditor.errors == 0,
    spectra: spectra.length(),
    errors: auditor.errors,
    warnings: auditor.warnings,
    truncated: auditor.errors + auditor.warnings > auditor.diagnostics.length(),
    diagnostics: auditor.diagnostics,
  }
}

///|
pub fn audit(
  text : String,
  policy~ : AuditPolicy = AuditPolicy::default(),
  options~ : ParseOptions = ParseOptions::default(),
) -> AuditReport {
  audit_document(parse_document(text, options~), policy~, options~) catch {
    Invalid(d) =>
      {
        valid: false,
        spectra: 0,
        errors: 1,
        warnings: 0,
        truncated: false,
        diagnostics: [d],
      }
  }
}
