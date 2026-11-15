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
    # Regression: in a `catch` block, implicit `error` is the immutable caught
    # exception, not SpiderDevnetStore.error. This previously broke TestFlight.
    devnet_store = (ROOT / "Console/SpiderDevnet/SpiderDevnetStore.swift").read_text(encoding="utf-8")
    require(re.search(r"(?<![.\w])error\s*=\s*error\.localizedDescription\b", devnet_store) is None,
            "SpiderDevnetStore catch shadowing: assign to self.error")
    # Spyder ID is compiled into the app and three signed extensions. Check the
    # target wiring and checked-in plists before starting an expensive archive.
    group = "group.com.spyder.wallet.id"
    key_group = "$(AppIdentifierPrefix)com.spyder.wallet.id"
    targets = {"Console": "com.spyder.wallet", "SpyderAutoFill": "com.spyder.wallet.id.autofill",
               "SpyderSafari": "com.spyder.wallet.id.safari", "SpyderShare": "com.spyder.wallet.id.share"}
    for name, bundle in targets.items():
        config = plistlib.loads((ROOT / f"Config/{name}-Info.plist").read_bytes())
        entitlements = plistlib.loads((ROOT / f"Config/{name}.entitlements").read_bytes())
        require(group in entitlements.get("com.apple.security.application-groups", []), f"missing shared App Group: {name}")
        require(key_group in entitlements.get("keychain-access-groups", []), f"missing shared Keychain group: {name}")
        target = re.search(rf"^  {name}:\s*\n(.*?)(?=^  \w+:\s*$|\Z)", project, re.M | re.S)
        require(target is not None, f"missing XcodeGen target: {name}")
        require(f"PRODUCT_BUNDLE_IDENTIFIER: {bundle}" in target[1], f"wrong bundle ID: {name}")
        require("path: Shared/SpyderID" in target[1], f"missing shared Swift sources: {name}")
        if name != "Console":
            require(config.get("CFBundleIdentifier") == bundle, f"wrong extension plist identifier: {name}")
            require(config.get("CFBundleVersion") == "$(CURRENT_PROJECT_VERSION)" and
                    config.get("CFBundleShortVersionString") == "$(MARKETING_VERSION)", f"extension version drift: {name}")
            require(config.get("NSExtension", {}).get("NSExtensionPrincipalClass", "").startswith("$(PRODUCT_MODULE_NAME)."), f"missing extension principal class: {name}")
            require("APPLICATION_EXTENSION_API_ONLY: YES" in target[1], f"extension API safety disabled: {name}")
            require(re.search(rf"- target: {name}\s*\n\s+embed: true", project) is not None, f"extension not embedded: {name}")
    autofill = plistlib.loads((ROOT / "Config/SpyderAutoFill-Info.plist").read_bytes())
    caps = autofill["NSExtension"]["NSExtensionAttributes"]["ASCredentialProviderExtensionCapabilities"]
    require(caps.get("ProvidesPasskeys") and caps.get("ProvidesPasswords"), "missing AutoFill capabilities")
    require(plist.get("ASCredentialProviderExtensionCapabilities", {}).get("ProvidesPasskeys"), "missing app passkey capability")
    for name in ("Console", "SpyderAutoFill"):
        entitlements = plistlib.loads((ROOT / f"Config/{name}.entitlements").read_bytes())
        require(entitlements.get("com.apple.developer.authentication-services.autofill-credential-provider"), f"missing AutoFill entitlement: {name}")
    resources = ROOT / "Extensions/SpyderSafari/Resources"
    manifest = json.loads((resources / "manifest.json").read_text())
    require((resources / manifest["action"]["default_popup"]).is_file(), "missing Safari popup")
    for name in ("popup.js", "form.js", "popup.css"):
        require((resources / name).is_file(), f"missing Safari resource: {name}")
    print("Spyder ID target, entitlement, bundle ID and Safari resource checks passed.")
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
