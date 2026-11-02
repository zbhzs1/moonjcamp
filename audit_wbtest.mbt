///|
test "metadata audit checks extrema independently of structural validity" {
  let source = synthetic([{ x: 1.0, y: Some(2.0), }, { x: 2.0, y: Some(3.0), }])
  let text = write_spectrum(source).replace_all(
    old="##MAXY=3",
    new="##MAXY=300",
  )
  assert_true(inspect(text).valid)
  let report = audit(text)
  assert_true(!report.valid)
  assert_true(
    report.diagnostics.iter().any(d => d.code == "AUDIT_DERIVED_VALUE"),
  )
  let policy = { ..AuditPolicy::default(), check_extrema: false, }
  assert_true(audit(text, policy~).valid)
}

///|
test "audit provenance policy and diagnostic caps are explicit" {
  let source = synthetic([{ x: 1.0, y: None, }])
  let policy = {
    ..AuditPolicy::default(),
    require_origin: true,
    require_owner: true,
    max_diagnostics: 1,
  }
  let report = audit(write_spectrum(source), policy~)
  assert_eq(report.errors, 2)
  assert_eq(report.diagnostics.length(), 1)
  assert_true(report.truncated)
}

///|
test "metadata edits cannot change structural scales or forge operation history" {
  let source = synthetic([{ x: 1.0, y: Some(2.0), }])
  let edited = edit_metadata(source, [
    Set("TITLE", "Reviewed sample"),
    Set("ORIGIN", "Laboratory A"),
    Remove("$SOURCE"),
  ])
  assert_eq(edited.title, "Reviewed sample")
  assert_eq(record_value(edited.records, "ORIGIN"), Some("Laboratory A"))
  assert_eq(record_value(edited.records, "$SOURCE"), None)
  assert_eq(source.title, "Synthetic")
  assert_true(record_value(edited.records, "$MOONJCAMP.HISTORY") is Some(_))
  for label in ["XFACTOR", "XUNITS", "DATA TYPE", "$MOONJCAMP.HISTORY"] {
    let failed = try {
      ignore(edit_metadata(source, [Set(label, "spoof")]))
      false
    } catch {
      Invalid(d) => d.code == "METADATA_PROTECTED"
    }
    assert_true(failed)
  }
}

///|
test "metadata edits validate every change before returning any new spectrum" {
  let source = synthetic([{ x: 1.0, y: Some(2.0), }])
  for
    edits in [
      [Set("OWNER", "A"), Set("owner", "B")],
      [Set("ORIGIN", "A\n##END=")],
      [Remove("TITLE")],
    ] {
    let failed = try {
      ignore(edit_metadata(source, edits))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(failed)
    assert_eq(source.records.length(), 1)
  }
}
