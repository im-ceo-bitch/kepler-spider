#!/usr/bin/env python3
"""Platform-independent static integrity checks before invoking Xcode."""
import json
from pathlib import Path
import plistlib
import sys
import re

ROOT = Path(__file__).resolve().parent.parent


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"REPO CHECK FAILED: {message}")


def main() -> None:
    plist = plistlib.loads((ROOT / "Config/Console-Info.plist").read_bytes())
    require(plist.get("CFBundleDisplayName") == "Spyder Wallet", "wrong app display name")
    require(plist.get("NSFaceIDUsageDescription"), "missing Face ID usage description")
    require((ROOT / "project.yml").exists(), "missing XcodeGen spec")
    project = (ROOT / "project.yml").read_text(encoding="utf-8")
    require(re.search(r"^\s*PRODUCT_BUNDLE_IDENTIFIER:\s*com\.spyder\.wallet\s*$", project, re.M) is not None,
            "project.yml must use com.spyder.wallet")
    require("com.console.beta" not in project, "old Console Bundle ID still present in project.yml")
    require((ROOT / "Console/ConsoleApp.swift").exists(), "missing SwiftUI app entry point")
    require((ROOT / "Console/Security/WalletVault.swift").exists(), "missing Keychain implementation")
    swift_files = list((ROOT / "Console").rglob("*.swift"))
    require(len(swift_files) >= 10, "incomplete SwiftUI source tree")
    for source in swift_files:
        data = source.read_text(encoding="utf-8")
        require("\x00" not in data, f"NUL byte in {source.relative_to(ROOT)}")
        require('SecureField("12 или 24 слова, через пробел", text: $importText, axis:' not in data,
                f"unsupported SecureField multiline initializer in {source.relative_to(ROOT)}")
    catalog = ROOT / "Console/Resources/Assets.xcassets"
    count = 0
    for json_path in catalog.rglob("Contents.json"):
        count += 1
        content = json.loads(json_path.read_text(encoding="utf-8"))
        for record in content.get("images", []):
            filename = record.get("filename")
            if filename:
                require((json_path.parent / filename).is_file(), f"missing asset {filename} in {json_path}")
        for record in content.get("colors", []):
            require("color" in record, f"invalid color asset in {json_path}")
    require(count > 0, "missing asset catalog")
    server_package = json.loads((ROOT / "server/package.json").read_text(encoding="utf-8"))
    require("scripts" in server_package, "server/package.json has no scripts")
    print(f"Static integrity checks passed: {len(swift_files)} Swift files, {count} asset manifests, app plist and server package.")


if __name__ == "__main__":
    main()
