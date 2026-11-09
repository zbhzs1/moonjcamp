"""Optional fetch-only checks against pinned historical IUPAC archive data.

The datasets retain their original ownership. Do not vendor or upload them.
"""
import hashlib
import contextlib
import io
import json
from pathlib import Path
import urllib.request

import numpy as np
from interop import ROOT, call, reference

REV = "797bb84ece314a867b21d24242c1bc4c6775a251"
FILES = {
    "BRUKAFFN.DX": "4fc2463ca5fe0f00628b00381032fc7c1da31501a07d6e5b0e1ec22deb9417a4",
    "BRUKDIF.DX": "9de483ea265ee2407fb7a6f7a90f1f5eb0247e128785517bc5fc8db9af3a88ea",
    "BRUKPAC.DX": "5e093417f8f27cae62180d913d5f742599872ba73ddbc18d86cc8fd5485da432",
    "BRUKSQZ.DX": "dc8c9effe8532229651f05575d4def47906c835b3054a2824477283a374b22b2",
    "PE1800.DX": "e6473ca929605bf1277ea07e30309effde65c22a7ebd8d3101821073bb94c440",
    "TEST32.DX": "7d385441ba505f72afe7b761cf513a9b8eb6a18aa658c46c34bd59124282dd85",
    "TESTSPEC.DX": "2666ead11e702f168e063278fa5a375adbc3ad5e6171232ef7c2d924abe9d3f3",
}


def main():
    ref = reference()
    results = {}
    vectors = {}
    for name, sha in FILES.items():
        target = ROOT / ".interop" / name
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            url = f"https://raw.githubusercontent.com/IUPAC/JCAMP-DX/{REV}/jcamp-dx.org_test_data/{name}"
            with urllib.request.urlopen(url, timeout=60) as response:
                data = response.read(2000000)
            if hashlib.sha256(data).hexdigest() != sha:
                raise AssertionError(f"SHA mismatch: {name}")
            target.write_bytes(data)
        data = target.read_bytes()
        assert hashlib.sha256(data).hexdigest() == sha, name
        # The historical data is ASCII-compatible; strict ASCII is intentional.
        result = call("read", text=data.decode("ascii"))
        points = result["spectra"][0]["points"]
        vectors[name] = np.array([[p["x"], p["y"]] for p in points], dtype=float)
        messages = io.StringIO()
        if name == "TESTSPEC.DX":
            results[name] = dict(points=len(points), sha256=sha, reference_limitation="Python crashes on exponent-looking terminal SQZ checkpoint; compared to BRUKDIF after its integer quantization instead.")
            continue
        with contextlib.redirect_stdout(messages):
            reference_text = "\n".join(line.split("$$", 1)[0].strip() for line in data.decode("ascii").splitlines())
            expected = ref.read(io.StringIO(reference_text))
        np.testing.assert_allclose(vectors[name][:, 0], expected["x"], rtol=1e-6, atol=1e-6, err_msg=name)
        np.testing.assert_allclose(vectors[name][:, 1], expected["y"], rtol=1e-6, atol=1e-6, err_msg=name)
        results[name] = dict(points=len(points), sha256=sha, reference_output=messages.getvalue())
    for name in ("BRUKPAC.DX", "BRUKSQZ.DX"):
        np.testing.assert_allclose(vectors[name], vectors["BRUKAFFN.DX"], rtol=1e-6, atol=1e-6)
    np.testing.assert_allclose(vectors["TESTSPEC.DX"][:, 0], vectors["BRUKDIF.DX"][:, 0], rtol=1e-6, atol=1e-6)
    np.testing.assert_array_equal(np.trunc(vectors["TESTSPEC.DX"][:, 1]), vectors["BRUKDIF.DX"][:, 1])
    report = dict(archive=f"IUPAC/JCAMP-DX@{REV}", passed=results,
                  equivalent_encodings=["BRUKAFFN.DX", "BRUKPAC.DX", "BRUKSQZ.DX"],
                  limitation="Python input has $$ comments and outer whitespace stripped; MoonBit receives original files. TESTSPEC truncated toward zero is checked exactly against integer BRUKDIF, not against the crashing Python reader. BRUKDIF differs from BRUKAFFN. Other archive files are not covered by this script. Not a complete conformance suite.")
    out = ROOT / "evidence" / "generated"
    out.mkdir(parents=True, exist_ok=True)
    (out / "archive.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
