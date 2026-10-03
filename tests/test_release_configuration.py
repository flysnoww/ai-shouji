"""Static release invariants; actual compilation is verified by macOS iOS CI."""
import plistlib
import re
import struct
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ReleaseConfigurationTests(unittest.TestCase):
    def test_production_identity_is_empty_and_profile_is_app_only(self):
        project = (ROOT / "ios/AIQuickNote.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        configurations = re.findall(r"isa = XCBuildConfiguration; buildSettings = \{(.*?)\}; name = (Debug|Release);", project)
        app = [(settings, name) for settings, name in configurations if "PRODUCT_BUNDLE_IDENTIFIER = org.tmiai.aiquicknote;" in settings]
        self.assertEqual(len(app), 2)
        release = next(settings for settings, name in app if name == "Release")
        self.assertIn("FIRESEED_IDENTITY_ENVIRONMENT = PRODUCTION;", release)
        for key in ("ENDPOINT", "ISSUER", "CLIENT_ID"):
            self.assertIn(f'FIRESEED_IDENTITY_{key} = "";', release)
        self.assertNotIn("trycloudflare.com", project)
        for settings, _ in configurations:
            if "org.tmiai.aiquicknote" not in settings:
                self.assertNotIn("PROVISIONING_PROFILE_SPECIFIER", settings)

    def test_callback_orientations_and_export_bundle(self):
        info = plistlib.loads((ROOT / "ios/AIQuickNote/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleURLTypes"][0]["CFBundleURLSchemes"], ["com.fireseed.aiquicknote"])
        self.assertGreaterEqual(len(info["UISupportedInterfaceOrientations~ipad"]), 4)
        self.assertIn("UIInterfaceOrientationPortrait", info["UISupportedInterfaceOrientations"])
        export = plistlib.loads((ROOT / ".github/ExportOptions-TestFlight.plist").read_bytes())
        self.assertEqual(set(export["provisioningProfiles"]), {"org.tmiai.aiquicknote"})
        self.assertEqual(export["method"], "app-store-connect")

    def test_app_icon_and_manual_upload_boundary(self):
        png = (ROOT / "ios/AIQuickNote/Assets.xcassets/AppIcon.appiconset/AppIcon.png").read_bytes()
        self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(struct.unpack(">II", png[16:24]), (1024, 1024))
        workflow = (ROOT / ".github/workflows/ios-testflight.yml").read_text(encoding="utf-8")
        triggers = workflow.split("permissions:")[0]
        self.assertIn("workflow_dispatch:", triggers)
        self.assertNotRegex(triggers, r"(?m)^  (push|pull_request|schedule):")
        for key in ("identity_environment", "identity_endpoint", "identity_client_id"):
            self.assertIn(f"      {key}:", triggers)
        ordinary = (ROOT / ".github/workflows/ios-ci.yml").read_text(encoding="utf-8")
        self.assertNotIn("--upload-app", ordinary)
        self.assertNotIn("secrets.", ordinary)
