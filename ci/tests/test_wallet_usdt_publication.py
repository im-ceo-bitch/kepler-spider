"""Execute the release publication boundary with a mock RPC. No real funds/network."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
class USDTProductionBoundaryTests(unittest.TestCase):
    def compile_run(self, language):
        swift=shutil.which('swiftc')
        if not swift:self.skipTest('Swift compiler unavailable')
        files=['WalletEVMPreflight.swift','WalletEVMUnsignedIntent.swift','WalletEVMKeccak256.swift',
               'WalletUSDTChatBinding.swift','WalletUSDTTransferJournal.swift','WalletEthereumRPC.swift','WalletUSDTPublication.swift']
        with tempfile.TemporaryDirectory() as directory:
            exe=str(Path(directory)/'usdt-tests')
            command=[swift,'-swift-version',language]+[str(ROOT/'Console/WalletCore'/name) for name in files]+[
                str(ROOT/'ci/tests/wallet_usdt_publication_driver.swift'),'-o',exe]
            built=subprocess.run(command,capture_output=True,text=True,timeout=90)
            self.assertEqual(built.returncode,0,built.stdout+built.stderr)
            run=subprocess.run([exe],capture_output=True,text=True,timeout=30)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            self.assertIn('USDT production publication tests passed',run.stdout)
    def test_swift5_release_publication(self):self.compile_run('5')
    def test_swift6_release_publication(self):self.compile_run('6')
