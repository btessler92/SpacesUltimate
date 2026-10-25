"""Exercise helper scripts with fake commands; never contact or launch the user's app."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class HelperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.log = self.directory / "calls.jsonl"
        self.app = self.directory / "Test App.app"
        self.app.mkdir()
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith("SPACESULTIMATE_")}
        self.env.update({
            "PATH": f"{self.directory}:{os.environ['PATH']}",
            "HELPER_TEST_LOG": str(self.log),
            "HELPER_TEST_RESPONSE": json.dumps({"app": "SpacesUltimate", "privateNote": "DO_NOT_PRINT"}),
            "SPACESULTIMATE_API": "http://127.0.0.1:1",
            "SPACESULTIMATE_APP": str(self.app),
        })
        for command in ("curl", "open", "pkill", "swift"):
            path = self.directory / command
            path.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
command = pathlib.Path(sys.argv[0]).name
with open(os.environ["HELPER_TEST_LOG"], "a") as log:
    log.write(json.dumps([command, *sys.argv[1:]]) + "\\n")
if command == "curl":
    if os.environ.get("HELPER_TEST_CURL_FAIL"):
        sys.exit(7)
    response = os.environ["HELPER_TEST_RESPONSE"]
    if "--output" in sys.argv or "-o" in sys.argv:
        flag = "--output" if "--output" in sys.argv else "-o"
        pathlib.Path(sys.argv[sys.argv.index(flag) + 1]).write_text(response)
    else:
        print(response)
elif command != "open":
    sys.exit(99)
''')
            path.chmod(0o755)

    def run_script(self, name):
        return subprocess.run(["bash", str(ROOT / "scripts" / name)], env=self.env,
                              text=True, capture_output=True, timeout=10)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_smoke_only_reads_state_and_does_not_print_private_payloads(self):
        result = self.run_script("smoke_test_api.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        allowed = {"status", "login-item/status", "config/backups", "config/invalid",
                   "config/name-bindings", "settings/defaults", "rules/suggestions",
                   "previews/status", "overlay/status"}
        paths = []
        for command, *args in self.calls():
            self.assertEqual(command, "curl")
            paths.append(args[-1].removeprefix(self.env["SPACESULTIMATE_API"] + "/"))
        self.assertEqual(set(paths), allowed)
        self.assertEqual(len(paths), len(allowed))
        self.assertNotIn("DO_NOT_PRINT", result.stdout + result.stderr)

    def test_smoke_rejects_invalid_json_api_errors_and_wrong_service(self):
        for response in ("not json", '{"ok":false}', '{"error":"failed"}', '{"app":"Other"}'):
            with self.subTest(response=response):
                self.env["HELPER_TEST_RESPONSE"] = response
                self.assertNotEqual(self.run_script("smoke_test_api.sh").returncode, 0)

    def test_smoke_stops_on_connection_failure(self):
        self.env["HELPER_TEST_CURL_FAIL"] = "1"
        self.assertNotEqual(self.run_script("smoke_test_api.sh").returncode, 0)
        self.assertEqual(len(self.calls()), 1)

    def test_old_destructive_mode_fails_before_contacting_app(self):
        self.env["SPACESULTIMATE_DESTRUCTIVE"] = "1"
        self.assertNotEqual(self.run_script("smoke_test_api.sh").returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_editor_only_requests_editor_without_changing_preferences(self):
        self.assertEqual(self.run_script("open_editor.sh").returncode, 0)
        self.assertEqual(len(self.calls()), 1)
        self.assertEqual(self.calls()[0][-1], self.env["SPACESULTIMATE_API"] + "/editor/show")

    def test_editor_failure_does_not_restart_or_install_app(self):
        self.env["HELPER_TEST_CURL_FAIL"] = "1"
        result = self.run_script("open_editor.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Launch SpacesUltimate", result.stderr)
        self.assertEqual([call[0] for call in self.calls()], ["curl"])

    def test_launch_reuses_app_without_quitting_or_building(self):
        result = self.run_script("launch_app.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [["open", str(self.app)]])

    def test_missing_custom_app_fails_without_building_another_copy(self):
        self.app.rmdir()
        result = self.run_script("launch_app.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("App not found", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_menu_validation_does_not_claim_on_screen_visibility(self):
        self.env["SPACESULTIMATE_EXPECTED_EXECUTABLE"] = "/test/SpacesUltimate"
        self.env["HELPER_TEST_RESPONSE"] = json.dumps({
            "appIdentity": {"executablePath": "/test/SpacesUltimate"},
            "menuBar": {"isVisible": True, "badgeText": "D6", "screenCount": 1,
                        "buttonWindowOcclusionVisible": False,
                        "menuItemTitles": ["Desktop 6", "SpacesUltimate Settings...",
                            "Open Space Editor", "Open Overview", "Show Desktop Notes Overlay",
                            "Status Item Display", "Debug Panel", "Refresh Spaces",
                            "Reset Menu Bar Item", "Quit SpacesUltimate"]}})
        result = self.run_script("validate_menu_bar_status.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("on-screen visibility needs a visual check", result.stdout)
        self.assertIn("window occlusion reports visible: False", result.stdout)
        self.env["SPACESULTIMATE_EXPECTED_EXECUTABLE"] = "/wrong/app"
        self.assertNotEqual(self.run_script("validate_menu_bar_status.sh").returncode, 0)
