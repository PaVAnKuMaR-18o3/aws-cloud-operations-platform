
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = (
    Path(__file__).resolve().parents[1]
    / "scripts"
    / "deployment-state.py"
)

OLD_IMAGE = "registry.example/app@sha256:" + "a" * 64
TARGET_IMAGE = "registry.example/app@sha256:" + "b" * 64


class DeploymentStateTests(unittest.TestCase):

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.state = self.root / "state.json"

    def run_state(self, *args):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *map(str, args)],
            capture_output=True,
            text=True,
        )

    def init_state(self):
        return self.run_state(
            "init",
            "--file", self.state,
            "--deployment-id", "test-deploy-001",
            "--old-image", OLD_IMAGE,
            "--target-image", TARGET_IMAGE,
        )

    def read_state(self):
        return json.loads(self.state.read_text())

    def test_init_creates_prepared_state(self):
        result = self.init_state()

        self.assertEqual(result.returncode, 0)
        state = self.read_state()
        self.assertEqual(state["stage"], "PREPARED")
        self.assertEqual(state["outcome"], "IN_PROGRESS")
        self.assertEqual(state["previous_image"], OLD_IMAGE)
        self.assertEqual(state["target_image"], TARGET_IMAGE)

    def test_init_refuses_overwrite(self):
        self.assertEqual(self.init_state().returncode, 0)
        original = self.state.read_bytes()

        result = self.init_state()

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state.read_bytes(), original)

    def test_valid_transition_to_cutover(self):
        self.assertEqual(self.init_state().returncode, 0)

        result = self.run_state(
            "stage", "--file", self.state, "--value", "CUTOVER"
        )

        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.read_state()["stage"], "CUTOVER")

    def test_invalid_transition_is_rejected(self):
        self.assertEqual(self.init_state().returncode, 0)

        result = self.run_state(
            "stage", "--file", self.state, "--value", "COMMITTED"
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.read_state()["stage"], "PREPARED")

    def test_unverified_rollback_is_rejected(self):
        self.assertEqual(self.init_state().returncode, 0)

        result = self.run_state(
            "stage", "--file", self.state, "--value", "ROLLED_BACK"
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.read_state()["stage"], "PREPARED")

    def test_verified_rollback_is_accepted(self):
        self.assertEqual(self.init_state().returncode, 0)
        self.assertEqual(self.run_state(
            "stage", "--file", self.state, "--value", "CUTOVER"
        ).returncode, 0)
        self.assertEqual(self.run_state(
            "stage", "--file", self.state, "--value", "ROLLBACK_REQUIRED"
        ).returncode, 0)

        evidence = {
            "deployment_id": "test-deploy-001",
            "restored_image": OLD_IMAGE,
            "container_running": True,
            "runtime_config_verified": True,
            "health_check_passed": True,
            "verified_at_utc": "2026-10-30T10:00:00+00:00",
        }
        evidence_path = self.root / "evidence.json"
        evidence_bytes = json.dumps(evidence).encode()
        evidence_path.write_bytes(evidence_bytes)

        result = self.run_state(
            "verify-rollback",
            "--file", self.state,
            "--evidence", evidence_path,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        state = self.read_state()
        self.assertEqual(state["stage"], "ROLLED_BACK")
        self.assertEqual(state["outcome"], "FAILURE")
        self.assertEqual(state["recovery_status"], "VERIFIED")
        self.assertEqual(
            state["recovery_evidence_sha256"],
            hashlib.sha256(evidence_bytes).hexdigest(),
        )

    def test_rollback_rejects_wrong_restored_image(self):
        self.assertEqual(self.init_state().returncode, 0)
        self.assertEqual(self.run_state(
            "stage", "--file", self.state, "--value", "CUTOVER"
        ).returncode, 0)
        self.assertEqual(self.run_state(
            "stage", "--file", self.state, "--value", "ROLLBACK_REQUIRED"
        ).returncode, 0)

        evidence_path = self.root / "evidence.json"
        evidence_path.write_text(json.dumps({
            "deployment_id": "test-deploy-001",
            "restored_image": TARGET_IMAGE,
            "container_running": True,
            "runtime_config_verified": True,
            "health_check_passed": True,
            "verified_at_utc": "2026-10-30T10:00:00+00:00",
        }))

        result = self.run_state(
            "verify-rollback",
            "--file", self.state,
            "--evidence", evidence_path,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(
            self.read_state()["stage"], "ROLLBACK_REQUIRED"
        )


if __name__ == "__main__":
    unittest.main()

