"""Real Swift typecheck for the public Coinbase stream, independent of Xcode build."""
import platform
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = [ROOT / 'Console/WalletCore/WalletMarketModels.swift',
           ROOT / 'Console/WalletCore/WalletLiveMarket.swift']

class WalletLiveCompileGates(unittest.TestCase):
    def test_public_market_module_typechecks(self):
        if not shutil.which('swiftc'):
            self.skipTest('Swift compiler not installed; Xcode build is required')
        with tempfile.TemporaryDirectory(prefix='spyder-market-typecheck-') as work:
            args = ['swiftc', '-swift-version', '5', '-typecheck', str(SOURCES[0])]
            if platform.system() == 'Linux':
                # Only substitute Combine's property wrapper for Linux: URLSession and parsing
                # still undergo real Swift type checking, including actor isolation.
                text = SOURCES[1].read_text().replace('import Combine', '')
                shim = '''import Foundation
import FoundationNetworking
protocol ObservableObject: AnyObject {}
@propertyWrapper struct Published<Value> {
  var wrappedValue: Value
  init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
'''
                source = Path(work) / 'WalletLiveMarket.swift'
                source.write_text(shim + text)
                args.append(str(source))
            else:
                args.append(str(SOURCES[1]))
            result = subprocess.run(args, text=True, capture_output=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stderr)

if __name__ == '__main__': unittest.main()
