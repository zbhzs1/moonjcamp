///|
fn main {
  let input =
    #|##TITLE=Minimal MoonBit example
    #|##JCAMP-DX=5.01
    #|##DATA TYPE=INFRARED SPECTRUM
    #|##XUNITS=1/CM
    #|##YUNITS=ABSORBANCE
    #|##FIRSTX=1000
    #|##LASTX=1002
    #|##NPOINTS=3
    #|##XYDATA=(X++(Y..Y))
    #|1000 1 2 3
    #|##END=
  try {
    let spectra = @jcamp.read_spectra(input)
    let selected = @jcamp.crop(spectra[0], 1001.0, 1002.0)
    let output = @jcamp.write_spectrum(selected)
    println(output)
    println(@jcamp.inspect(output).valid)
  } catch {
    @jcamp.Invalid(diagnostic) =>
      println(diagnostic.code + ": " + diagnostic.message)
  }
}
