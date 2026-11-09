///|
fn checked_ir_424(
  text : String,
  options : ParseOptions,
  pure_compound : Bool,
) -> Spectrum raise JcampError {
  check_options(options)
  // In 4.24, an exponent has an explicit sign; unsigned E/e is a SQZ digit.
  let options = if options.numeric_mode == Auto {
    { ..options, numeric_mode: Asdf, }
  } else {
    options
  }
  let lines = physical_lines(text, options)
  let unpaired = text.replace_all(old="\r\n", new="")
  guard !unpaired.contains("\r") && !unpaired.contains("\n") else {
    reject(
      "IR_LINE_ENDINGS", "4.24 exchange requires CRLF physical line endings",
    )
  }
  for row in lines {
    guard row.text.length() <= 80 else {
      reject(
        "IR_LINE_WIDTH",
        "4.24 physical lines may not exceed 80 characters",
        line=row.line,
      )
    }
    guard row.text.iter().all(c => c >= ' ' && c <= '~') else {
      reject(
        "IR_ASCII",
        "4.24 exchange requires printable ASCII",
        line=row.line,
      )
    }
  }
  let document = parse_document(text, options~)
  guard document.blocks.length() == 1 && document.blocks[0].children.is_empty() else {
    reject(
      "IR_SINGLE", "the 4.24 IR exchange target requires one simple spectrum",
    )
  }
  let block = document.blocks[0]
  guard block.records.length() >= 2 &&
    canonical_label(block.records[1].label) == "JCAMPDX" else {
    reject(
      "IR_VERSION_ORDER",
      "JCAMP-DX must immediately follow TITLE",
      line=block.start_line,
    )
  }
  guard record_value(block.records, "JCAMP-DX").map(trim) == Some("4.24") else {
    reject(
      "IR_VERSION",
      "this conformance target requires JCAMP-DX=4.24",
      line=block.start_line,
    )
  }
  guard canonical_label(block_kind(block)) == "INFRAREDSPECTRUM" else {
    reject(
      "IR_DATA_TYPE",
      "this target requires DATA TYPE=INFRARED SPECTRUM",
      line=block.start_line,
    )
  }
  let seen : Map[String, Bool] = Map([])
  for record in block.records {
    let key = canonical_label(record.label)
    if key != "" {
      guard !seen.contains(key) else {
        reject(
          "IR_DUPLICATE",
          "4.24 permits each named LDR only once per block",
          line=record.line,
        )
      }
      seen[key] = true
    }
  }
  for
    key in [
      "ORIGIN", "OWNER", "XUNITS", "YUNITS", "XFACTOR", "YFACTOR", "FIRSTX", "LASTX",
      "FIRSTY", "NPOINTS",
    ] {
    guard record_value(block.records, key).map(trim).unwrap_or("") != "" else {
      reject(
        "IR_CORE_MISSING",
        "missing nonempty CORE field: " + key,
        line=block.start_line,
      )
    }
  }
  guard record_value(block.records, "BLOCKS") is None else {
    reject(
      "IR_BLOCKS",
      "BLOCKS is not permitted in a simple data block",
      line=block.start_line,
    )
  }
  if pure_compound {
    guard record_value(block.records, "CLASS").map(trim).unwrap_or("") != "" else {
      reject(
        "IR_CLASS",
        "CLASS must be supplied for a pure compound",
        line=block.start_line,
      )
    }
  }
  let x = canonical_label(record_value(block.records, "XUNITS").unwrap())
  let y = canonical_label(record_value(block.records, "YUNITS").unwrap())
  guard ["1CM", "MICROMETERS", "NANOMETERS", "SECONDS"].contains(x) else {
    reject(
      "IR_XUNITS",
      "XUNITS is not a standard 4.24 infrared unit",
      line=block.start_line,
    )
  }
  guard [
    "TRANSMITTANCE", "REFLECTANCE", "ABSORBANCE", "KUBELKAMUNK", "ARBITRARYUNITS",
  ].contains(y) else {
    reject(
      "IR_YUNITS",
      "YUNITS is not a standard 4.24 infrared unit",
      line=block.start_line,
    )
  }
  let spectrum = spectrum_from_block(block, options~)
  let table = block.tables[0]
  let key = canonical_label(table.label)
  guard key == "XYDATA" || key == "XYPOINTS" else {
    reject(
      "IR_TABLE",
      "the IR spectrum target uses XYDATA or XYPOINTS",
      line=table.line,
    )
  }
  for record in block.records {
    guard record.line < table.line else {
      reject(
        "IR_RECORD_ORDER",
        "metadata must precede the spectral table",
        line=record.line,
      )
    }
  }
  guard spectrum.points[0].y is Some(_) else {
    reject(
      "IR_FIRST_MISSING",
      "the first spectral ordinate must be valid",
      line=table.line,
    )
  }
  if key == "XYDATA" {
    let numeric = table_options(table, options)
    for row in table.rows {
      let value = trim(strip_comment(row.text))
      guard value != "" &&
        (
          digit(value[0]) ||
          value[0] == '+' ||
          value[0] == '-' ||
          value[0] == '.'
        ) else {
        reject("IR_X_FORM", "XYDATA row abscissae must use AFFN", line=row.line)
      }
    }
    let last = table.rows[table.rows.length() - 1]
    guard !decode_line(last.text, numeric, last.line).ends_difference else {
      reject(
        "IR_FINAL_CHECKPOINT",
        "DIF output requires a final absolute X/Y checkpoint line",
        line=last.line,
      )
    }
  } else {
    // XYPOINTS is AFFN in 4.24, unlike the ASDF XYDATA stream.
    ignore(paired_points(block, table, { ..options, numeric_mode: Affn, }))
  }
  let audited = audit_document(
    document,
    policy={
      ..AuditPolicy::default(),
      require_origin: true,
      require_owner: true,
    },
    options~,
  )
  guard audited.valid else {
    let diagnostic = audited.diagnostics.filter(d => d.severity == Error)[0]
    raise Invalid(diagnostic)
  }
  spectrum
}

///|
pub fn validate_ir_424(
  text : String,
  options~ : ParseOptions = ParseOptions::default(),
  pure_compound~ : Bool = false,
) -> Report {
  try {
    let spectrum = checked_ir_424(text, options, pure_compound)
    {
      valid: true,
      spectra: 1,
      points: spectrum.points.length(),
      missing: spectrum.points.filter(p => p.y is None).length(),
      diagnostics: [],
    }
  } catch {
    Invalid(diagnostic) =>
      {
        valid: false,
        spectra: 0,
        points: 0,
        missing: 0,
        diagnostics: [diagnostic],
      }
  }
}

///|
pub fn write_ir_424(
  spectrum : Spectrum,
  options~ : WriteOptions = WriteOptions::default(),
  pure_compound~ : Bool = false,
) -> String raise JcampError {
  let mut width = options.points_per_line
  while true {
    let text = write_spectrum(spectrum, options={
      ..options,
      version: "4.24",
      points_per_line: width,
    }).replace_all(old="\n", new="\r\n")
    let report = validate_ir_424(text, pure_compound~)
    if report.valid {
      return text
    }
    let diagnostic = report.diagnostics[0]
    if diagnostic.code == "IR_LINE_WIDTH" && width > 1 {
      width = width / 2
      continue
    }
    raise Invalid(diagnostic)
  }
  reject("IR_WRITE", "unreachable IR export state")
}
