from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_wallet_index_is_reserved_before_seed_write():
    source = (ROOT / "Console/Security/WalletVault.swift").read_text()
    save = source.split("static func save(_ rawPhrase: String", 1)[1].split("static func revealForBackup", 1)[0]
    assert save.index("try registerAccount(id)") < save.index("SecItemAdd(attributes as CFDictionary, nil)")
    assert "try unregisterAccount(id)" in save


def test_account_index_rollback_never_touches_seed_material():
    source = (ROOT / "Console/Security/WalletVault.swift").read_text()
    rollback = source.split("private static func unregisterAccount", 1)[1].split("static func makeNewPhrase", 1)[0]
    assert "writeAccountIDs(try readAccountIDs().filter { $0 != id })" in rollback
    assert "SecItemDelete" not in rollback
    assert "phrase" not in rollback


def test_wallet_seed_remains_device_bound_and_user_presence_protected():
    source = (ROOT / "Console/Security/WalletVault.swift").read_text()
    assert "kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly" in source
    assert ".userPresence" in source
    assert "kSecAttrSynchronizable as String: false" in source


def test_index_mutation_fails_closed_and_is_serialized():
    source = (ROOT / "Console/Security/WalletVault.swift").read_text()
    assert "mutationLock.lock(); defer { mutationLock.unlock() }" in source
    assert "guard status == errSecSuccess else { throw VaultError.failed(status) }" in source
    assert "try writeAccountIDs(try readAccountIDs() + [id])" in source
    assert "if status != errSecDuplicateItem { try unregisterAccount(id) }" in source
