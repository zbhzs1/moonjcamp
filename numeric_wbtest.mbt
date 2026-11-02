///|
test "AFFN scientific notation packed signs separators and missing values" {
  assert_eq(decode_numbers("1.5 -2E-2,+3.0;?"), [Some(1.5), Some(-0.02), Some(3.0), None])
  assert_eq(decode_numbers("1+2-3.5", mode=Affn), [Some(1.0), Some(2.0), Some(-3.5)])
}

///|
test "SQZ positive negative zero and multi-digit tokens" {
  assert_eq(decode_numbers("0 @A2b3I9", mode=Asdf), [Some(0.0), Some(0.0), Some(12.0), Some(-23.0), Some(99.0)])
  assert_eq(decode_numbers("0 E12e12", mode=Asdf), [Some(0.0), Some(512.0), Some(-512.0)])
}

///|
test "DIF deltas and DUP counts include the preceding token" {
  assert_eq(decode_numbers("0 A0JT", mode=Asdf), [Some(0.0), Some(10.0), Some(11.0), Some(12.0)])
  assert_eq(decode_numbers("0 A0J2U", mode=Asdf), [Some(0.0), Some(10.0), Some(22.0), Some(34.0), Some(46.0)])
  assert_eq(decode_numbers("0 B5j%", mode=Asdf), [Some(0.0), Some(25.0), Some(24.0), Some(24.0)])
}

///|
test "DUP absolute token repetition and decimal repeat counts" {
  assert_eq(decode_numbers("A0U", mode=Asdf), [Some(10.0), Some(10.0), Some(10.0)])
  assert_eq(decode_numbers("@S0", mode=Asdf).length(), 10)
}

///|
test "automatic mode prefers AFFN exponents with explicit ASDF override" {
  assert_eq(decode_numbers("0 1E2"), [Some(0.0), Some(100.0)])
  assert_eq(decode_numbers("0 1E2", mode=Asdf), [Some(0.0), Some(1.0), Some(52.0)])
  assert_eq(decode_numbers("0 A0JT"), [Some(0.0), Some(10.0), Some(11.0), Some(12.0)])
}

///|
test "malformed or unbounded streams fail without allocating expanded data" {
  for value in ["J", "S", "?J", "?T", "A99999999999999999999", "1~", "1E+", "A0s9999999"] {
    let failed = try { ignore(decode_numbers(value)); false } catch { Invalid(_) => true }
    assert_true(failed)
  }
  let limited = try { ignore(decode_numbers("A0Z", max_values=4)); false } catch { Invalid(d) => d.code == "LIMIT_DUP" }
  assert_true(limited)
}

///|
test "numeric rows preserve line-relative columns in errors" {
  let result = try { ignore(decode_numbers("0 1 ~", mode=Affn)); None } catch { Invalid(d) => Some(d) }
  guard result is Some(diagnostic) else { fail("expected a diagnostic") }
  assert_eq(diagnostic.line, 1)
  assert_eq(diagnostic.column, 5)
}
