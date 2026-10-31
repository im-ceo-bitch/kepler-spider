"""Regression coverage for source issues that previously broke CI."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SourceRegressionTests(unittest.TestCase):
    def test_spider_store_catch_does_not_shadow_error_property(self):
        source = (ROOT / "Console/SpiderDevnet/SpiderDevnetStore.swift").read_text(encoding="utf-8")
        self.assertNotRegex(source, r"(?<![.\w])error\s*=\s*error\.localizedDescription\b")
        self.assertEqual(source.count("self.error = error.localizedDescription"), 2)

    def test_marketing_version_set_manually_in_project(self):
        project = (ROOT / "project.yml").read_text(encoding="utf-8")
        self.assertRegex(project, r"(?m)^\s*MARKETING_VERSION:\s*[\"']?1\.0[\"']?\s*$")

if __name__ == "__main__":
    unittest.main()
