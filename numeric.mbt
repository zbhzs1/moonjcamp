///|
priv enum TokenKind {
  Absolute(Double)
  Delta(Double)
  Repeat(Int32)
  Missing
}

///|
priv struct NumericToken {
  kind : TokenKind
  column : Int32
}

///|
priv struct DecodedLine {
  values : Array[Double?]
  uses_difference : Bool
  ends_difference : Bool
  first_ordinate_absolute : Bool
}

///|
fn separator(c : UInt16) -> Bool {
  whitespace(c) || c == ',' || c == ';'
}

///|
fn absolute_prefix(c : UInt16) -> Int32? {
  if c == '@' {
    Some(0)
  } else if c >= 'A' && c <= 'I' {
    Some(c.to_int() - 64)
  } else if c >= 'a' && c <= 'i' {
    Some(96 - c.to_int())
  } else {
    None
  }
}

///|
fn delta_prefix(c : UInt16) -> Int32? {
  if c == '%' {
    Some(0)
  } else if c >= 'J' && c <= 'R' {
    Some(c.to_int() - 73)
  } else if c >= 'j' && c <= 'r' {
    Some(105 - c.to_int())
  } else {
    None
  }
}

///|
fn repeat_prefix(c : UInt16) -> Int32? {
  if c >= 'S' && c <= 'Z' {
    Some(c.to_int() - 82)
  } else if c == 's' {
    Some(9)
  } else {
    None
  }
}

///|
fn coded_integer(
  text : String,
  start : Int32,
  leading : Int32,
  line : Int32,
) -> (Double, Int32) raise JcampError {
  let mut value = leading.abs().to_double()
  let mut i = start + 1
  while i < text.length() && digit(text[i]) {
    value = value * 10.0 + (text[i].to_int() - 48).to_double()
    guard value <= 9007199254740991.0 else {
      reject(
        "ASDF_PRECISION",
        "coded integer exceeds exact binary64 integer range",
        line~,
        column=start + 1,
      )
    }
    i += 1
  }
  (if leading < 0 { -value } else { value }, i)
}

///|
fn numeric_tokens(
  text : String,
  mode : NumericMode,
  options : ParseOptions,
  line : Int32,
) -> Array[NumericToken] raise JcampError {
  let tokens : Array[NumericToken] = []
  let mut i = 0
  while i < text.length() {
    let c = text[i]
    if separator(c) {
      i += 1
      continue
    }
    guard tokens.length() < options.limits.max_tokens_per_line else {
      reject(
        "LIMIT_TOKENS",
        "numeric token budget exceeded",
        line~,
        column=i + 1,
      )
    }
    let start = i
    if c == '?' {
      tokens.push({ kind: Missing, column: i + 1, })
      i += 1
      continue
    }
    if mode == Asdf {
      if absolute_prefix(c) is Some(prefix) {
        let (value, next) = coded_integer(text, i, prefix, line)
        tokens.push({ kind: Absolute(value), column: i + 1, })
        i = next
        continue
      }
      if delta_prefix(c) is Some(prefix) {
        let (value, next) = coded_integer(text, i, prefix, line)
        tokens.push({ kind: Delta(value), column: i + 1, })
        i = next
        continue
      }
      if repeat_prefix(c) is Some(prefix) {
        let (value, next) = coded_integer(text, i, prefix, line)
        guard value <= options.limits.max_points.to_double() else {
          reject(
            "LIMIT_DUP",
            "DUP count exceeds point budget",
            line~,
            column=i + 1,
          )
        }
        tokens.push({ kind: Repeat(value.to_int()), column: i + 1, })
        i = next
        continue
      }
    }
    if c == '+' || c == '-' {
      i += 1
    }
    let mut digits = 0
    while i < text.length() && digit(text[i]) {
      i += 1
      digits += 1
    }
    if i < text.length() && text[i] == '.' {
      i += 1
      while i < text.length() && digit(text[i]) {
        i += 1
        digits += 1
      }
    }
    guard digits > 0 else {
      reject(
        "NUMERIC_TOKEN",
        "unrecognized numeric token",
        line~,
        column=start + 1,
      )
    }
    if i < text.length() &&
      (text[i] == 'E' || text[i] == 'e') &&
      (
        mode != Asdf ||
        (i + 1 < text.length() && (text[i + 1] == '+' || text[i + 1] == '-'))
      ) {
      i += 1
      if i < text.length() && (text[i] == '+' || text[i] == '-') {
        i += 1
      }
      let exponent = i
      while i < text.length() && digit(text[i]) {
        i += 1
      }
      guard i > exponent else {
        reject(
          "NUMBER_EXPONENT",
          "exponent has no digits",
          line~,
          column=start + 1,
        )
      }
    }
    let value = number(text[start:i].to_owned(), line~, column=start + 1)
    tokens.push({ kind: Absolute(value), column: start + 1, })
  }
  tokens
}

///|
fn decode_line(
  text : String,
  options : ParseOptions,
  line : Int32,
) -> DecodedLine raise JcampError {
  let text = strip_comment(text)
  let tokens = if options.numeric_mode == Auto {
    numeric_tokens(text, Affn, options, line) catch {
      Invalid(_) => numeric_tokens(text, Asdf, options, line)
    }
  } else {
    numeric_tokens(text, options.numeric_mode, options, line)
  }
  let values : Array[Double?] = []
  let mut previous : Double? = None
  let mut previous_token : TokenKind? = None
  let mut uses_difference = false
  let first_ordinate_absolute = if tokens.length() >= 2 {
    match tokens[1].kind {
      Absolute(_) | Missing => true
      _ => false
    }
  } else {
    false
  }
  for token in tokens {
    match token.kind {
      Absolute(value) => {
        guard values.length() < options.limits.max_points else {
          reject(
            "LIMIT_POINTS",
            "expanded numeric row exceeds point budget",
            line~,
            column=token.column,
          )
        }
        values.push(Some(value))
        previous = Some(value)
        previous_token = Some(token.kind)
      }
      Missing => {
        guard values.length() < options.limits.max_points else {
          reject(
            "LIMIT_POINTS",
            "expanded numeric row exceeds point budget",
            line~,
            column=token.column,
          )
        }
        values.push(None)
        previous = None
        previous_token = None
      }
      Delta(delta) => {
        guard previous is Some(value) else {
          reject(
            "DIF_ANCHOR",
            "DIF requires a preceding finite absolute value",
            line~,
            column=token.column,
          )
        }
        let next = value + delta
        guard finite(next) && next.abs() <= 9007199254740991.0 else {
          reject(
            "ASDF_PRECISION",
            "difference reconstruction exceeds exact integer range",
            line~,
            column=token.column,
          )
        }
        guard values.length() < options.limits.max_points else {
          reject(
            "LIMIT_POINTS",
            "expanded numeric row exceeds point budget",
            line~,
            column=token.column,
          )
        }
        values.push(Some(next))
        previous = Some(next)
        previous_token = Some(token.kind)
        uses_difference = true
      }
      Repeat(count) => {
        guard previous_token is Some(operation) else {
          reject(
            "DUP_ANCHOR",
            "DUP requires a preceding absolute or difference token",
            line~,
            column=token.column,
          )
        }
        guard count >= 1 &&
          count - 1 <= options.limits.max_points - values.length() else {
          reject(
            "LIMIT_DUP",
            "DUP expansion exceeds remaining point budget",
            line~,
            column=token.column,
          )
        }
        let mut repeat = 1
        while repeat < count {
          let value = match operation {
            Absolute(value) => value
            Delta(delta) => {
              guard previous is Some(value) else {
                reject(
                  "DIF_ANCHOR",
                  "missing difference anchor",
                  line~,
                  column=token.column,
                )
              }
              let result = value + delta
              guard finite(result) && result.abs() <= 9007199254740991.0 else {
                reject(
                  "ASDF_PRECISION",
                  "DUP reconstruction exceeds exact integer range",
                  line~,
                  column=token.column,
                )
              }
              result
            }
            _ =>
              reject(
                "DUP_ANCHOR",
                "unsupported repeated token",
                line~,
                column=token.column,
              )
          }
          values.push(Some(value))
          previous = Some(value)
          repeat += 1
        }
      }
    }
  }
  let ends_difference = previous_token is Some(Delta(_))
  { values, uses_difference, ends_difference, first_ordinate_absolute, }
}

///|
pub fn decode_numbers(
  text : String,
  mode~ : NumericMode = Auto,
  max_values~ : Int32 = 100000,
) -> Array[Double?] raise JcampError {
  let options = {
    ..ParseOptions::default(),
    numeric_mode: mode,
    limits: { ..Limits::default(), max_points: max_values, },
  }
  check_options(options)
  guard text.length() <= options.limits.max_line_chars else {
    reject("LIMIT_LINE", "numeric row exceeds line budget")
  }
  decode_line(text, options, 1).values
}
