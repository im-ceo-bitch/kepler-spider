"""Safe diagnostics for Apple Distribution signing."""
import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from signing import pkcs12_error_message, validate_p12_private_key


class PKCS12DiagnosticTests(unittest.TestCase):
    def test_wrong_password(self):
        self.assertIn("password is wrong", pkcs12_error_message(b"Mac verify error: invalid password?"))

    def test_unsupported_cipher(self):
        self.assertIn("unsupported", pkcs12_error_message(b"unsupported: Algorithm (RC2-40-CBC)"))

    def test_corrupted_file(self):
        self.assertIn("not decode", pkcs12_error_message(b"ASN1 wrong tag"))

    def test_other_failure(self):
        self.assertIn("Unable to open", pkcs12_error_message(b"generic error"))

    def test_actual_pkcs12_contains_matching_private_key(self):
        with tempfile.TemporaryDirectory() as dirname:
            d = pathlib.Path(dirname)
            cert, key, p12 = [d / name for name in ("cert.pem", "key.pem", "signing.p12")]
            subprocess.run(["openssl", "req", "-new", "-x509", "-nodes", "-newkey", "rsa:2048",
                            "-keyout", str(key), "-out", str(cert), "-days", "3", "-subj", "/CN=Test"],
                           check=True, capture_output=True)
            subprocess.run(["openssl", "pkcs12", "-export", "-inkey", str(key), "-in", str(cert),
                            "-out", str(p12), "-passout", "pass:test-password"],
                           check=True, capture_output=True)
            from unittest.mock import patch
            with patch.dict('os.environ', {'APPLE_DISTRIBUTION_P12_PASSWORD': 'test-password'}):
                validate_p12_private_key(p12, cert)


if __name__ == "__main__":
    unittest.main()
