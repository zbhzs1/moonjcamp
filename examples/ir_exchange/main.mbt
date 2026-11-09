///|
fn main raise {
  let input = "##TITLE=Synthetic IR exchange\r\n##JCAMP-DX=4.24\r\n##DATA TYPE=INFRARED SPECTRUM\r\n##ORIGIN=MoonJCAMP example\r\n##OWNER=Synthetic data, MIT\r\n##XUNITS=1/CM\r\n##YUNITS=ABSORBANCE\r\n##XFACTOR=1\r\n##YFACTOR=0.1\r\n##FIRSTX=4000\r\n##LASTX=3997\r\n##FIRSTY=0.1\r\n##NPOINTS=4\r\n##XYDATA=(X++(Y..Y))\r\n4000 AJU\r\n3997 D\r\n##END=\r\n"
  let imported = @jcamp.read_spectra(input)[0]
  let output = @jcamp.write_ir_424(imported, options={
    ..@jcamp.WriteOptions::default(),
    encoding: @jcamp.Difference,
    y_factor: 0.1,
  })
  assert_true(@jcamp.validate_ir_424(output).valid)
  assert_true(@jcamp.compare_documents(input, output).equivalent)
  println("4.24 IR exchange: 4 points, strict validation and roundtrip passed")
}
