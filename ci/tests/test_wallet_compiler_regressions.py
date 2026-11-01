"""Preflight checks for actual Swift type errors in wallet history.

Runs a real swiftc -typecheck when Swift is installed, with minimal external
symbols. On Linux, FoundationNetworking and an equivalent Combine shim are
used only in a temporary copy of the target file. On macOS the Apple Combine
module is used, so this detects compiler errors before the expensive archive.
"""
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
HISTORY = ROOT / 'Console/WalletCore/WalletActivityHistory.swift'
HOME = ROOT / 'Console/Features/Wallet/WalletHomeView.swift'
TOKENS = ROOT / 'Console/WalletCore/WalletTokenCatalog.swift'

STUBS = '''
import Foundation
enum SpyderChain: String, CaseIterable, Hashable { case bitcoin, ethereum, solana }
struct SpyderAddress { let chain: SpyderChain; let value: String }
enum WalletPublicRPCError: LocalizedError { case badResponse }
'''
COMBINE = '''
public protocol ObservableObject: AnyObject {}
@propertyWrapper public struct Published<Value> {
  public var wrappedValue: Value
  public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
'''


def run_compiler(args):
    command = ['swiftc', '-swift-version', '5', *args]
    result = subprocess.run(command, capture_output=True, text=True, timeout=120)
    if result.returncode:
        raise AssertionError(f"Swift compiler failed: {' '.join(command)}\n{result.stdout}\n{result.stderr}")


class WalletCompileRegressions(unittest.TestCase):
    def test_history_typechecks_with_real_swift_compiler(self):
        if not shutil.which('swiftc'):
            self.skipTest('Swift compiler unavailable; macOS Xcode build remains required')
        with tempfile.TemporaryDirectory(prefix='spyder-typecheck-') as temp:
            directory = Path(temp)
            stubs = directory / 'Stubs.swift'
            stubs.write_text(STUBS)
            source = HISTORY
            module_flags = []
            if platform.system() == 'Linux':
                combine = directory / 'Combine.swift'
                combine.write_text(COMBINE)
                run_compiler(['-emit-module', '-module-name', 'Combine',
                              '-emit-module-path', str(directory / 'Combine.swiftmodule'), str(combine)])
                source = directory / 'WalletActivityHistory.swift'
                source.write_text(HISTORY.read_text().replace(
                    'import Foundation\n', 'import Foundation\nimport FoundationNetworking\n', 1))
                module_flags = ['-I', str(directory)]
            run_compiler(['-typecheck', '-module-name', 'WalletHistoryTypecheck',
                          *module_flags, str(stubs), str(TOKENS), str(source)])

    def test_home_swiftui_modifiers_stay_inside_conditional_branch(self):
        home = HOME.read_text(encoding='utf-8')
        self.assertRegex(home, r'if\s+!privacyHidden\s*\{\s*Text\("USD"\)\s*\.font\(')
        self.assertNotRegex(home, r'(?m)^\s*if\s+[^\n]*\{\s*(?:Text|Image|Label)\([^\n]*\)\s*\}\s*\n\s*\.(?:font|foregroundStyle)\(')

    def test_error_and_amount_patterns_are_not_regressed(self):
        history = HISTORY.read_text(encoding='utf-8')
        self.assertNotIn('Decimal.init(string:)', history)
        self.assertNotIn('&& !(try container.decodeNil(forKey: .err))', history)
        self.assertIn('Locale(identifier: "en_US_POSIX")', history)


if __name__ == '__main__':
    unittest.main()
