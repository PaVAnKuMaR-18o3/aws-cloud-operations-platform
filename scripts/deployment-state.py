#!/usr/bin/env python3
"""Atomic deployment transaction state tracking."""

import argparse
import hashlib
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

VALID_STAGES = {
    "PREPARED",
    "CUTOVER",
    "VERIFYING",
    "COMMITTED",
    "ROLLBACK_REQUIRED",
    "ROLLED_BACK",
    "MANUAL_RECOVERY_REQUIRED",
}

ALLOWED_TRANSITIONS = {
    "PREPARED": {"CUTOVER", "MANUAL_RECOVERY_REQUIRED"},
    "CUTOVER": {
        "VERIFYING", "ROLLBACK_REQUIRED",
        "MANUAL_RECOVERY_REQUIRED",
    },
    "VERIFYING": {
        "COMMITTED", "ROLLBACK_REQUIRED",
        "MANUAL_RECOVERY_REQUIRED",
    },
    "ROLLBACK_REQUIRED": {"MANUAL_RECOVERY_REQUIRED"},
    "MANUAL_RECOVERY_REQUIRED": set(),
    "COMMITTED": set(),
    "ROLLED_BACK": set(),
}

def utc_now():
    return datetime.now(timezone.utc).isoformat()

def write_atomic(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)

    fd, tmp = tempfile.mkstemp(
        prefix=".deployment-state-",
        dir=str(path.parent)
    )

    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())

        os.replace(tmp, path)

        # Persist the directory entry where supported.
        dir_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def main():
    p = argparse.ArgumentParser()
    p.add_argument("action", choices=["init", "stage", "show", "verify-rollback"])
    p.add_argument("--file", required=True)
    p.add_argument("--deployment-id")
    p.add_argument("--old-image")
    p.add_argument("--target-image")
    p.add_argument("--value")
    p.add_argument("--evidence")
    args = p.parse_args()

    path = Path(args.file)

    if args.action == "init":
        if path.exists():
            sys.exit("ERROR: State file already exists; refusing overwrite.")

        if not all([
            args.deployment_id,
            args.old_image,
            args.target_image
        ]):
            sys.exit("ERROR: init requires deployment ID and both images.")

        state = {
            "deployment_id": args.deployment_id,
            "started_at_utc": utc_now(),
            "updated_at_utc": utc_now(),
            "previous_image": args.old_image,
            "target_image": args.target_image,
            "stage": "PREPARED",
            "outcome": "IN_PROGRESS",
            "recovery_status": "NOT_REQUIRED",
        }
        write_atomic(path, state)
        print("State initialized: PREPARED")
        return

    if not path.is_file():
        sys.exit("ERROR: State file does not exist.")

    with path.open() as f:
        state = json.load(f)

    if args.action == "show":
        print(json.dumps(state, indent=2))
        return

    if args.action == "verify-rollback":
        if state.get("stage") != "ROLLBACK_REQUIRED":
            sys.exit(
                "ERROR: Recovery verification requires ROLLBACK_REQUIRED."
            )

        if not args.evidence:
            sys.exit("ERROR: --evidence is required.")

        evidence_path = Path(args.evidence)
        if not evidence_path.is_file():
            sys.exit("ERROR: Evidence file does not exist.")

        try:
            evidence_bytes = evidence_path.read_bytes()
            evidence = json.loads(evidence_bytes)
        except (json.JSONDecodeError, OSError, UnicodeDecodeError) as exc:
            sys.exit(f"ERROR: Invalid evidence file: {exc}")

        if not isinstance(evidence, dict):
            sys.exit("ERROR: Evidence must be a JSON object.")

        required = {
            "deployment_id",
            "restored_image",
            "container_running",
            "runtime_config_verified",
            "health_check_passed",
            "verified_at_utc",
        }

        missing = sorted(required - evidence.keys())
        if missing:
            sys.exit(f"ERROR: Missing evidence fields: {missing}")

        if evidence["deployment_id"] != state.get("deployment_id"):
            sys.exit("ERROR: Deployment ID mismatch.")

        if evidence["restored_image"] != state.get("previous_image"):
            sys.exit("ERROR: Restored image does not match previous image.")

        for key in (
            "container_running",
            "runtime_config_verified",
            "health_check_passed",
        ):
            if evidence[key] is not True:
                sys.exit(f"ERROR: Recovery evidence failed: {key}")

        verified_at = evidence["verified_at_utc"]
        if not isinstance(verified_at, str):
            sys.exit("ERROR: Invalid verification timestamp.")

        try:
            parsed_time = datetime.fromisoformat(
                verified_at.replace("Z", "+00:00")
            )
            if parsed_time.tzinfo is None:
                raise ValueError("Timezone required.")
        except ValueError:
            sys.exit(
                "ERROR: verified_at_utc must be ISO 8601 with timezone."
            )

        evidence_sha256 = hashlib.sha256(evidence_bytes).hexdigest()

        state["stage"] = "ROLLED_BACK"
        state["outcome"] = "FAILURE"
        state["recovery_status"] = "VERIFIED"
        state["recovery_evidence"] = evidence
        state["recovery_evidence_sha256"] = evidence_sha256
        state["recovery_verified_at_utc"] = verified_at
        state["updated_at_utc"] = utc_now()

        write_atomic(path, state)
        print("Recovery verified: ROLLED_BACK")
        print(f"Evidence SHA-256: {evidence_sha256}")
        return

    if args.value == "ROLLED_BACK":
        sys.exit(
            "ERROR: ROLLED_BACK requires dedicated recovery verification."
        )

    if args.value not in VALID_STAGES:
        sys.exit("ERROR: Invalid stage.")

    current = state.get("stage")

    allowed = ALLOWED_TRANSITIONS.get(current, set())
    if args.value not in allowed:
        sys.exit(
            f"ERROR: Invalid transition: {current} -> {args.value}"
        )

    state["stage"] = args.value
    state["updated_at_utc"] = utc_now()

    if args.value == "COMMITTED":
        state["outcome"] = "SUCCESS"
        state["recovery_status"] = "NOT_REQUIRED"
    elif args.value in {
        "ROLLBACK_REQUIRED",
        "MANUAL_RECOVERY_REQUIRED",
    }:
        state["outcome"] = "FAILURE"
        state["recovery_status"] = "REQUIRED"

    write_atomic(path, state)
    print(f"State updated: {args.value}")

if __name__ == "__main__":
    main()
