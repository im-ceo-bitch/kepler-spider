"""Negative and positive cases for Apple provisioning profile validation."""
import datetime as dt
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from signing import verify_profile


class SigningValidationTests(unittest.TestCase):
    def valid(self):
        return {
            "TeamIdentifier": ["ABCDEFGHIJ"],
            "ApplicationIdentifierPrefix": ["ABCDEFGHIJ"],
            "Entitlements": {"application-identifier": "ABCDEFGHIJ.com.spyder.wallet", "get-task-allow": False},
            "Platform": ["iOS"],
            "ExpirationDate": dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=120),
            "DeveloperCertificates": [b"test-certificate-der"],
            "UUID": "7E9F4C4F-B2CD-4AD7-BFA6-1C0974E013F3",
            "Name": "SpyderWallet AppStore",
        }

    def test_valid(self):
        result = verify_profile(self.valid(), "ABCDEFGHIJ", "com.spyder.wallet", b"test-certificate-der")
        self.assertEqual(result["name"], "SpyderWallet AppStore")

    def test_wrong_team(self):
        with self.assertRaises(SystemExit):
            verify_profile(self.valid(), "DIFFERENT", "com.spyder.wallet", b"test-certificate-der")

    def test_wrong_bundle_id(self):
        with self.assertRaises(SystemExit):
            verify_profile(self.valid(), "ABCDEFGHIJ", "com.other.bundle", b"test-certificate-der")

    def test_development_profile(self):
        profile = self.valid()
        profile["Entitlements"]["get-task-allow"] = True
        with self.assertRaises(SystemExit):
            verify_profile(profile, "ABCDEFGHIJ", "com.spyder.wallet", b"test-certificate-der")

    def test_wrong_certificate(self):
        with self.assertRaises(SystemExit):
            verify_profile(self.valid(), "ABCDEFGHIJ", "com.spyder.wallet", b"other")

    def test_expired_profile(self):
        profile = self.valid()
        profile["ExpirationDate"] = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=1)
        with self.assertRaises(SystemExit):
            verify_profile(profile, "ABCDEFGHIJ", "com.spyder.wallet", b"test-certificate-der")

    def test_adhoc_profile(self):
        profile = self.valid()
        profile["ProvisionedDevices"] = ["TESTUDID"]
        with self.assertRaises(SystemExit):
            verify_profile(profile, "ABCDEFGHIJ", "com.spyder.wallet", b"test-certificate-der")


if __name__ == "__main__":
    unittest.main()
