///|
pub(all) struct QualityPolicy {
  max_missing_fraction : Double
  require_monotone : Bool
  require_uniform : Bool
  min_points : Int32
} derive(@debug.Debug, ToJson)

///|
pub fn QualityPolicy::default() -> QualityPolicy {
  {
    max_missing_fraction: 0.1,
    require_monotone: true,
    require_uniform: false,
    min_points: 2,
  }
}

///|
pub(all) struct Summary {
  title : String
  points : Int32
  missing : Int32
  x_min : Double
  x_max : Double
  y_min : Double?
  y_max : Double?
  y_mean : Double?
  direction : Int32
  uniform : Bool
  longest_missing_run : Int32
  diagnostics : Array[Diagnostic]
  accepted : Bool
} derive(@debug.Debug, ToJson)

///|
pub(all) struct BatchInput {
  name : String
  text : String
} derive(@debug.Debug, ToJson)

///|
pub(all) struct BatchItem {
  name : String
  accepted : Bool
  spectra : Array[Summary]
  diagnostics : Array[Diagnostic]
} derive(@debug.Debug, ToJson)

///|
pub(all) struct BatchReport {
  accepted : Int32
  rejected : Int32
  items : Array[BatchItem]
} derive(@debug.Debug, ToJson)

///|
fn check_policy(policy : QualityPolicy) -> Unit raise JcampError {
  guard finite(policy.max_missing_fraction) &&
    policy.max_missing_fraction >= 0.0 &&
    policy.max_missing_fraction <= 1.0 else {
    reject("QUALITY_POLICY", "missing fraction must be between zero and one")
  }
  guard policy.min_points >= 1 &&
    policy.min_points <= Limits::default().max_points else {
    reject("QUALITY_POLICY", "min_points must be inside the point budget")
  }
}

///|
fn quality_diagnostic(
  code : String,
  message : String,
  line : Int32,
) -> Diagnostic {
  { severity: Warning, code, message, line, column: 1, }
}

///|
pub fn summarize(
  spectrum : Spectrum,
  policy~ : QualityPolicy = QualityPolicy::default(),
) -> Summary raise JcampError {
  checked_spectrum(spectrum)
  check_policy(policy)
  let mut missing = 0
  let mut run = 0
  let mut longest = 0
  let mut count = 0
  let mut mean = 0.0
  let mut minimum : Double? = None
  let mut maximum : Double? = None
  let mut x_min = spectrum.points[0].x
  let mut x_max = x_min
  for p in spectrum.points {
    if p.x < x_min {
      x_min = p.x
    }
    if p.x > x_max {
      x_max = p.x
    }
    match p.y {
      None => {
        missing += 1
        run += 1
        if run > longest {
          longest = run
        }
      }
      Some(y) => {
        run = 0
        count += 1
        // Weighted incremental mean avoids summing all ordinates first.
        mean = mean * ((count - 1).to_double() / count.to_double()) +
          y / count.to_double()
        guard finite(mean) else {
          reject("QUALITY_RANGE", "mean calculation overflow")
        }
        minimum = match minimum {
          None => Some(y)
          Some(v) => Some(if y < v { y } else { v })
        }
        maximum = match maximum {
          None => Some(y)
          Some(v) => Some(if y > v { y } else { v })
        }
      }
    }
  }
  let direction = axis_direction(spectrum.points)
  let uniform = uniform_step(spectrum.points) is Some(_)
  let diagnostics : Array[Diagnostic] = []
  if spectrum.points.length() < policy.min_points {
    diagnostics.push(
      quality_diagnostic(
        "QUALITY_POINTS",
        "fewer than the required number of samples",
        spectrum.source_line,
      ),
    )
  }
  if missing.to_double() / spectrum.points.length().to_double() >
    policy.max_missing_fraction {
    diagnostics.push(
      quality_diagnostic(
        "QUALITY_MISSING",
        "missing-value fraction exceeds policy",
        spectrum.source_line,
      ),
    )
  }
  if policy.require_monotone && direction == 0 && spectrum.points.length() > 1 {
    diagnostics.push(
      quality_diagnostic(
        "QUALITY_AXIS",
        "axis is not strictly monotone",
        spectrum.source_line,
      ),
    )
  }
  if policy.require_uniform && !uniform {
    diagnostics.push(
      quality_diagnostic(
        "QUALITY_GRID",
        "axis is not uniformly sampled",
        spectrum.source_line,
      ),
    )
  }
  {
    title: spectrum.title,
    points: spectrum.points.length(),
    missing,
    x_min,
    x_max,
    y_min: minimum,
    y_max: maximum,
    y_mean: if count == 0 {
      None
    } else {
      Some(mean)
    },
    direction,
    uniform,
    longest_missing_run: longest,
    accepted: diagnostics.is_empty(),
    diagnostics,
  }
}

///|
pub fn inspect_batch(
  inputs : Array[BatchInput],
  policy~ : QualityPolicy = QualityPolicy::default(),
  options~ : ParseOptions = ParseOptions::default(),
) -> BatchReport raise JcampError {
  check_policy(policy)
  check_options(options)
  guard !inputs.is_empty() && inputs.length() <= options.limits.max_blocks else {
    reject("BATCH_SIZE", "batch must be nonempty and bounded")
  }
  let mut chars = 0
  let mut points = 0
  let names : Map[String, Bool] = Map([])
  for input in inputs {
    guard trim(input.name) != "" && !names.contains(input.name) else {
      reject("BATCH_NAME", "batch names must be nonempty and unique")
    }
    names[input.name] = true
    guard input.text.length() <= options.limits.max_chars - chars else {
      reject("LIMIT_TEXT", "batch text budget exceeded")
    }
    chars += input.text.length()
  }
  let items : Array[BatchItem] = []
  let mut accepted = 0
  for input in inputs {
    let item : BatchItem = try {
      let source = read_spectra(input.text, options~)
      let summaries : Array[Summary] = []
      for spectrum in source {
        guard spectrum.points.length() <= options.limits.max_points - points else {
          reject("LIMIT_POINTS", "aggregate batch point budget exceeded")
        }
        points += spectrum.points.length()
        summaries.push(summarize(spectrum, policy~))
      }
      {
        name: input.name,
        accepted: summaries.iter().all(s => s.accepted),
        spectra: summaries,
        diagnostics: [],
      }
    } catch {
      Invalid(d) =>
        { name: input.name, accepted: false, spectra: [], diagnostics: [d], }
    }
    if item.accepted {
      accepted += 1
    }
    items.push(item)
  }
  { accepted, rejected: inputs.length() - accepted, items, }
}

///|
fn parse_quality_policy(value : Json) -> QualityPolicy raise JcampError {
  let fields = json_object(
    value,
    [
      "max_missing_fraction", "require_monotone", "require_uniform", "min_points",
    ],
    "quality policy",
  )
  fn boolean(key : String, default : Bool) -> Bool raise JcampError {
    match fields.get(key) {
      None => default
      Some(True) => true
      Some(False) => false
      _ => reject("JSON_TYPE", key + " must be boolean")
    }
  }
  let policy = {
    max_missing_fraction: json_double(fields, "max_missing_fraction", 0.1),
    require_monotone: boolean("require_monotone", true),
    require_uniform: boolean("require_uniform", false),
    min_points: json_int(fields, "min_points", 2),
  }
  check_policy(policy)
  policy
}
