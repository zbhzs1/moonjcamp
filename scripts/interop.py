"""Independent compatibility checks; reference code is fetched, never vendored."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import urllib.request

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
REV = "9a4af7d3f0cf6aa8d27913426334dec1f5b06130"
SHA = "e25dab4bdf025612404df522597a2a4229669e5a152eafff864da74696f13317"
REF = ROOT / ".interop" / "jcamp.py"


def reference():
    if not REF.exists():
        REF.parent.mkdir(parents=True, exist_ok=True)
        url = f"https://raw.githubusercontent.com/nzhagen/jcamp/{REV}/jcamp.py"
        with urllib.request.urlopen(url, timeout=60) as response:
            data = response.read(200000)
        if hashlib.sha256(data).hexdigest() != SHA:
            raise AssertionError("reference SHA-256 mismatch")
        REF.write_bytes(data)
    if hashlib.sha256(REF.read_bytes()).hexdigest() != SHA:
        raise AssertionError("cached reference SHA-256 mismatch")
    spec = importlib.util.spec_from_file_location("reference_jcamp", REF)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def call(operation, **fields):
    result = subprocess.run(
        ["node", "bin/moonjcamp.mjs", "--protocol"], cwd=ROOT,
        input=json.dumps(dict(operation=operation, **fields)), text=True,
        capture_output=True, check=True, timeout=30,
    )
    response = json.loads(result.stdout)
    if not response["ok"]:
        raise AssertionError(response)
    return response["value"]


def main():
    ref = reference()
    x = np.arange(40, dtype=float) + 100
    y = np.array([0, 1, 2, 3, 4, -2, -1, 0, 8, 16] * 4, dtype=float)
    spectrum = dict(title="Synthetic interoperability", data_type="INFRARED SPECTRUM",
                    x_units="1/CM", y_units="ABSORBANCE",
                    points=[dict(x=float(a), y=float(b)) for a, b in zip(x, y)])
    cases = []
    for encoding in ("affn", "pac", "sqz", "difdup"):
        for width in (2, 5, 8):
            text = call("write", spectrum=spectrum,
                        write_options=dict(encoding=encoding, points_per_line=width))["text"]
            warnings = io.StringIO()
            with contextlib.redirect_stdout(warnings):
                result = ref.read(io.StringIO(text))
            if warnings.getvalue().strip():
                raise AssertionError(f"reference diagnostic: {warnings.getvalue()}")
            np.testing.assert_allclose(result["x"], x, rtol=1e-12, atol=1e-12)
            np.testing.assert_allclose(result["y"], y, rtol=1e-12, atol=1e-12)
            cases.append(f"MoonBit->{encoding}/{width}->Python")
    for descending in (False, True):
        for factor in (1.0, 0.25):
            axis = x[::-1].copy() if descending else x
            data = dict(title="Python producer", **{"data type": "INFRARED SPECTRUM"},
                        xunits="1/CM", yunits="ABSORBANCE", x=axis, y=y * factor)
            with contextlib.redirect_stdout(io.StringIO()):
                text = ref.write(data, linewidth=45)
            # The reference writer emits JCAMP-DX before TITLE. Move only TITLE
            # to the required first-record position; do not change numeric data.
            lines = text.splitlines()
            title = next(line for line in lines if line.startswith("##TITLE="))
            text = "\n".join([title] + [line for line in lines if line != title]) + "\n"
            result = call("read", text=text)["spectra"][0]["points"]
            np.testing.assert_allclose([p["x"] for p in result], axis)
            np.testing.assert_allclose([p["y"] for p in result], y * factor)
            cases.append(f"Python->MoonBit/descending={descending}/amplitude={factor}")
    report = dict(reference=f"nzhagen/jcamp@{REV}", sha256=SHA,
                  passed=len(cases), cases=cases,
                  limitation="Reference writer TITLE record reordered; numerical payload unchanged.")
    out = ROOT / "evidence" / "generated"
    out.mkdir(parents=True, exist_ok=True)
    (out / "interop.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
