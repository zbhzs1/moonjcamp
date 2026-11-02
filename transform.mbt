///|
fn transformed(
  source : Spectrum,
  points : Array[Point],
  operation : Json,
  x_units~ : String = source.x_units,
  y_units~ : String = source.y_units,
) -> Spectrum raise JcampError {
  let mut records = remove_records(source.records, [
    "NPOINTS", "FIRSTX", "LASTX", "FIRSTY", "LASTY", "MINX", "MAXX", "MINY", "MAXY",
    "DELTAX", "XFACTOR", "YFACTOR", "DATACLASS",
  ])
  let history : Array[Json] = match
    record_value(records, "$MOONJCAMP.HISTORY") {
    None => []
    Some(text) => {
      let value = @json.parse(text[:], reject_duplicate_keys=true) catch {
        _ => reject("PROVENANCE_INVALID", "history must be a JSON array")
      }
      guard value is Array(items) && items.length() < 100 else {
        reject("PROVENANCE_LIMIT", "history must have fewer than 100 steps")
      }
      items.copy()
    }
  }
  history.push(operation)
  records = set_record(records, "$MOONJCAMP.HISTORY", Json(history).stringify())
  records = set_record(records, "XUNITS", x_units)
  records = set_record(records, "YUNITS", y_units)
  let result = { ..source, points, records, x_units, y_units, source_line: 0, }
  checked_spectrum(result)
  result
}

///|
pub fn crop(
  spectrum : Spectrum,
  minimum : Double,
  maximum : Double,
) -> Spectrum raise JcampError {
  checked_spectrum(spectrum)
  guard finite(minimum) && finite(maximum) && minimum <= maximum else {
    reject("CROP_RANGE", "crop bounds must be finite and ordered")
  }
  let points = spectrum.points.filter(p => p.x >= minimum && p.x <= maximum)
  guard !points.is_empty() else {
    reject("CROP_EMPTY", "crop selects no data points")
  }
  transformed(spectrum, points, {
    "operation": "crop",
    "minimum": minimum,
    "maximum": maximum,
  })
}

///|
fn axis_direction(points : Array[Point]) -> Int32 {
  if points.length() < 2 {
    return 0
  }
  let direction = if points[1].x > points[0].x {
    1
  } else if points[1].x < points[0].x {
    -1
  } else {
    0
  }
  if direction == 0 {
    return 0
  }
  for i = 1; i < points.length(); i = i + 1 {
    if (direction > 0 && points[i].x <= points[i - 1].x) ||
      (direction < 0 && points[i].x >= points[i - 1].x) {
      return 0
    }
  }
  direction
}

///|
pub fn resample(
  spectrum : Spectrum,
  start : Double,
  end : Double,
  count : Int32,
) -> Spectrum raise JcampError {
  checked_spectrum(spectrum)
  guard count >= 2 &&
    count <= Limits::default().max_points &&
    finite(start) &&
    finite(end) &&
    start != end else {
    reject(
      "RESAMPLE_GRID", "resampling requires a finite nonzero interval and 2..max_points samples",
    )
  }
  let direction = axis_direction(spectrum.points)
  guard direction != 0 else {
    reject(
      "RESAMPLE_AXIS", "resampling requires a strictly monotone axis with at least two points",
    )
  }
  let source = if direction > 0 {
    spectrum.points.copy()
  } else {
    spectrum.points.rev()
  }
  let low = if start < end { start } else { end }
  let high = if start > end { start } else { end }
  guard low >= source[0].x && high <= source[source.length() - 1].x else {
    reject(
      "RESAMPLE_EXTRAPOLATION", "resampling does not extrapolate beyond measured data",
    )
  }
  let step = (high - low) / (count - 1).to_double()
  guard finite(step) && step > 0.0 else {
    reject("RESAMPLE_GRID", "resampling step overflow or underflow")
  }
  let points : Array[Point] = []
  let mut cursor = 0
  for i = 0; i < count; i = i + 1 {
    let x = if i == count - 1 { high } else { low + i.to_double() * step }
    guard finite(x) && (points.is_empty() || x > points[points.length() - 1].x) else {
      reject("RESAMPLE_PRECISION", "grid points collapse at binary64 precision")
    }
    while cursor + 1 < source.length() - 1 && source[cursor + 1].x < x {
      cursor += 1
    }
    let left = source[cursor]
    let right = source[cursor + 1]
    let y = if x == left.x {
      left.y
    } else if x == right.x {
      right.y
    } else {
      match (left.y, right.y) {
        (Some(a), Some(b)) => {
          let denominator = right.x - left.x
          guard finite(denominator) else {
            reject("RESAMPLE_RANGE", "interpolation interval overflow")
          }
          let weight = (x - left.x) / denominator
          let value = a * (1.0 - weight) + b * weight
          guard finite(value) else {
            reject("RESAMPLE_RANGE", "interpolation overflow")
          }
          Some(value)
        }
        _ => None
      }
    }
    points.push({ x, y, })
  }
  let points = if start > end { points.rev() } else { points }
  transformed(spectrum, points, {
    "operation": "linear-resample",
    "start": start,
    "end": end,
    "count": count,
    "missing": "propagate",
    "extrapolate": false,
  })
}

///|
fn x_unit(unit : String) -> String raise JcampError {
  match canonical_label(unit) {
    "1/CM" | "CM1" | "CM^1" => "1/CM"
    "NM" | "NANOMETERS" => "NM"
    "UM" | "MICROMETERS" | "MICRONS" => "MICROMETERS"
    _ => reject("X_UNIT", "supported X units are 1/CM, NM and MICROMETERS")
  }
}

///|
pub fn convert_x(
  spectrum : Spectrum,
  target : String,
) -> Spectrum raise JcampError {
  checked_spectrum(spectrum)
  let from = x_unit(spectrum.x_units)
  let to = x_unit(target)
  let points : Array[Point] = []
  for p in spectrum.points {
    guard p.x > 0.0 else {
      reject("UNIT_DOMAIN", "wavelength and wavenumber must be positive")
    }
    let nm = match from {
      "1/CM" => 10000000.0 / p.x
      "MICROMETERS" => p.x * 1000.0
      _ => p.x
    }
    let x = if from == to {
      p.x
    } else {
      match to {
        "1/CM" => 10000000.0 / nm
        "MICROMETERS" => nm / 1000.0
        _ => nm
      }
    }
    guard finite(nm) && finite(x) && nm > 0.0 && x > 0.0 else {
      reject("UNIT_RANGE", "unit conversion overflow or underflow")
    }
    points.push({ ..p, x, })
  }
  transformed(
    spectrum,
    points,
    { "operation": "convert-x", "from": from, "to": to },
    x_units=to,
  )
}

///|
fn y_unit(unit : String) -> String raise JcampError {
  match canonical_label(unit) {
    "ABSORBANCE" => "ABSORBANCE"
    "TRANSMITTANCE" => "TRANSMITTANCE"
    "%TRANSMITTANCE" | "PERCENTTRANSMITTANCE" => "%TRANSMITTANCE"
    _ =>
      reject(
        "Y_UNIT", "supported Y units are ABSORBANCE, TRANSMITTANCE and %TRANSMITTANCE",
      )
  }
}

///|
pub fn convert_y(
  spectrum : Spectrum,
  target : String,
) -> Spectrum raise JcampError {
  checked_spectrum(spectrum)
  let from = y_unit(spectrum.y_units)
  let to = y_unit(target)
  let points : Array[Point] = []
  for p in spectrum.points {
    let y = match p.y {
      None => None
      Some(value) => {
        let transmission = match from {
          "ABSORBANCE" => {
            guard value >= 0.0 else {
              reject(
                "UNIT_DOMAIN", "negative absorbance requires an explicit physical policy outside this profile",
              )
            }
            @math.pow(10.0, -value)
          }
          "%TRANSMITTANCE" => value / 100.0
          _ => value
        }
        guard finite(transmission) && transmission > 0.0 && transmission <= 1.0 else {
          reject(
            "UNIT_DOMAIN", "transmittance must be in (0,1], or (0,100] percent",
          )
        }
        let result = if from == to {
          value
        } else {
          match to {
            "ABSORBANCE" => -@math.log10(transmission)
            "%TRANSMITTANCE" => transmission * 100.0
            _ => transmission
          }
        }
        guard finite(result) else {
          reject("UNIT_RANGE", "unit conversion produced a nonfinite value")
        }
        Some(result)
      }
    }
    points.push({ ..p, y, })
  }
  transformed(
    spectrum,
    points,
    { "operation": "convert-y", "from": from, "to": to },
    y_units=to,
  )
}
