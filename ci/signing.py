#!/usr/bin/env python3
"""Validate Apple CI signing inputs; does not create or revoke certificates.

The .p12, distribution profile and App Store Connect API key must be created in
Apple Developer / App Store Connect before the TestFlight workflow is run.
"""

import argparse
import base64
import binascii
import datetime as dt
import json
import os
import pathlib
import plistlib
import subprocess
import sys


def fail(message: str) -> None:
    raise SystemExit(f"SIGNING ERROR: {message}")


def decode_secret(name: str, destination: pathlib.Path, *, allow_pem: bool = False) -> None:
    raw = os.getenv(name, "").strip()
    if not raw:
        fail(f"Missing GitHub Actions secret {name}. See SIGNING_SETUP_RU.md.")
    if allow_pem and "-----BEGIN PRIVATE KEY-----" in raw:
        data = raw.encode("utf-8")
    else:
        try:
            data = base64.b64decode("".join(raw.split()), validate=True)
        except (binascii.Error, ValueError):
            fail(f"Secret {name} is not valid base64 data.")
    if not data:
        fail(f"Secret {name} is empty after decoding.")
    destination.write_bytes(data)
    destination.chmod(0o600)


def verify_profile(profile: dict, team: str, bundle: str, certificate_der: bytes) -> dict:
    profile_team = profile.get("TeamIdentifier", [None])[0]
    if profile_team != team:
        fail(f"Provisioning profile team mismatch: profile team is {profile_team!r}, expected APPLE_TEAM_ID={team!r}.")
    prefixes = profile.get("ApplicationIdentifierPrefix", [])
    if not prefixes:
        fail("Profile has no ApplicationIdentifierPrefix.")
    entitlements = profile.get("Entitlements", {})
    profile_app_id = entitlements.get("application-identifier") or entitlements.get("com.apple.application-identifier")
    expected_id = f"{prefixes[0]}.{bundle}"
    if profile_app_id != expected_id:
        fail(f"Profile App ID mismatch: {profile_app_id!r}; expected {expected_id!r}.")
    if entitlements.get("get-task-allow") is not False:
        fail("Expected an App Store distribution profile (get-task-allow must be false), not a development profile.")
    if profile.get("ProvisionedDevices") is not None or profile.get("ProvisionsAllDevices"):
        fail("Expected an App Store distribution profile; Ad Hoc/Development/Enterprise profile supplied.")
    if "iOS" not in profile.get("Platform", ["iOS"]):
        fail("Profile is not for iOS.")
    expiry = profile.get("ExpirationDate")
    now = dt.datetime.now(dt.timezone.utc)
    if not isinstance(expiry, dt.datetime):
        fail("Profile expiration date is missing.")
    if expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=dt.timezone.utc)
    if expiry <= now + dt.timedelta(days=1):
        fail(f"Profile is expired or expires within 24 hours ({expiry.date()}).")
    if certificate_der not in profile.get("DeveloperCertificates", []):
        fail("The P12 signing certificate does not match the certificate in the provisioning profile. Generate a profile using this exact Apple Distribution certificate.")
    uuid = profile.get("UUID")
    name = profile.get("Name")
    if not isinstance(uuid, str) or not uuid or not isinstance(name, str) or not name:
        fail("Profile UUID or Name is missing.")
    return {"uuid": uuid, "name": name, "expiration": expiry.isoformat()}


def run(command: list[str], *, env: dict | None = None) -> bytes:
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    if result.returncode:
        # Do not leak OpenSSL passwords/private keys in printed diagnostic output.
        fail(f"Could not validate signing file with {' '.join(command[:2])}; ensure the P12 password and distribution credentials are correct.")
    return result.stdout


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=pathlib.Path, required=True)
    parser.add_argument("--bundle-id", default="com.console.beta")
    args = parser.parse_args()
    directory = args.out.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    directory.chmod(0o700)
    team = os.getenv("APPLE_TEAM_ID", "").strip()
    key_id = os.getenv("APP_STORE_CONNECT_KEY_ID", "").strip()
    issuer = os.getenv("APP_STORE_CONNECT_ISSUER_ID", "").strip()
    if not all([team, key_id, issuer]):
        fail("Missing APPLE_TEAM_ID, APP_STORE_CONNECT_KEY_ID or APP_STORE_CONNECT_ISSUER_ID.")
    if not os.getenv("APPLE_DISTRIBUTION_P12_PASSWORD"):
        fail("Missing APPLE_DISTRIBUTION_P12_PASSWORD (password of Apple Distribution .p12).")
    key_path = directory / f"AuthKey_{key_id}.p8"
    p12_path = directory / "distribution.p12"
    mobileprovision = directory / "distribution.mobileprovision"
    decode_secret("APP_STORE_CONNECT_API_KEY_BASE64", key_path, allow_pem=True)
    if b"-----BEGIN PRIVATE KEY-----" not in key_path.read_bytes():
        fail("APP_STORE_CONNECT_API_KEY_BASE64 is not an App Store Connect .p8 key.")
    decode_secret("APPLE_DISTRIBUTION_P12_BASE64", p12_path)
    decode_secret("APPLE_APPSTORE_PROFILE_BASE64", mobileprovision)
    profile_data = run(["security", "cms", "-D", "-i", str(mobileprovision)])
    try:
        profile = plistlib.loads(profile_data)
    except Exception:
        fail("Apple provisioning profile does not contain a valid plist.")
    cert_pem = directory / "distribution.cer.pem"
    cert_pem.write_bytes(run(["openssl", "pkcs12", "-in", str(p12_path), "-clcerts", "-nokeys", "-passin", "env:APPLE_DISTRIBUTION_P12_PASSWORD"]))
    cert_der = run(["openssl", "x509", "-in", str(cert_pem), "-outform", "DER"])
    if run(["openssl", "x509", "-in", str(cert_pem), "-checkend", "86400", "-noout"]) is None:
        fail("Expired certificate")
    subject = run(["openssl", "x509", "-in", str(cert_pem), "-noout", "-subject"]).decode("utf-8")
    if "Apple Distribution" not in subject and "iPhone Distribution" not in subject:
        fail("The P12 is not an Apple Distribution certificate.")
    data = verify_profile(profile, team, args.bundle_id, cert_der)
    sha1 = run(["openssl", "x509", "-in", str(cert_pem), "-noout", "-fingerprint", "-sha1"]).decode().strip().split("=", 1)[-1].replace(":", "")
    data["sha1"] = sha1
    data["key_path"] = str(key_path)
    data["p12_path"] = str(p12_path)
    data["profile_path"] = str(mobileprovision)
    (directory / "metadata.json").write_text(json.dumps(data), encoding="utf-8")
    print(f"Signing files validated: team {team}, bundle {args.bundle_id}, profile '{data['name']}', expires {data['expiration'][:10]}.")


if __name__ == "__main__":
    main()
