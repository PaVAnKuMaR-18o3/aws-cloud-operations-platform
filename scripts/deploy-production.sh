#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Controlled single-container production deployment.
# Requires root/Docker access on the EC2 host.
# A short outage is possible during cutover.
# Validate this script before production use.

REGION="ap-southeast-2"
REGISTRY="074494041866.dkr.ecr.ap-southeast-2.amazonaws.com"
REPOSITORY="cloud-operations-platform"
PRODUCTION="cloud-operations-platform"
PORT="80"
CONTAINER_PORT="3000"

LOG_GROUP="/cloud-operations-platform/app"
LOG_STREAM="ec2-app"

ROLLBACK_NEEDED=false
DOCKER_CONFIG_TEMP=""

die() {
  echo "ERROR: $*" >&2
  exit 1
}

TARGET_DIGEST="${1:-}"

[[ "$TARGET_DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]] ||
  die "Usage: bash scripts/deploy-production.sh sha256:<64-hex>"

TARGET_IMAGE="${REGISTRY}/${REPOSITORY}@${TARGET_DIGEST}"

# Prevent overlapping runs.
exec 9>/tmp/cop-production-deploy.lock
flock -n 9 || die "Another production deployment is running."

# Inspect the existing production container.
OLD_STATUS="$(docker inspect -f '{{.State.Status}}' "$PRODUCTION")"
OLD_IMAGE="$(docker inspect -f '{{.Config.Image}}' "$PRODUCTION")"
OLD_IMAGE_ID="$(docker inspect -f '{{.Image}}' "$PRODUCTION")"

[[ "$OLD_STATUS" == "running" ]] ||
  die "Production is not running."

[[ "$OLD_IMAGE" =~ ^${REGISTRY}/${REPOSITORY}@sha256:[a-f0-9]{64}$ ]] ||
  die "Production image is not an immutable ECR image reference."

[[ "$OLD_IMAGE_ID" =~ ^sha256:[a-f0-9]{64}$ ]] ||
  die "Production image ID is invalid."

# Independently validate the approved runtime configuration.
docker inspect "$PRODUCTION" | python3 -c '
import json,sys

c=json.load(sys.stdin)[0]

assert c["Config"]["User"] == "app"
assert c["Config"]["Entrypoint"] == ["docker-entrypoint.sh"]
assert c["Config"]["Cmd"] == ["node","app.js"]
assert c["HostConfig"]["RestartPolicy"]["Name"] == "unless-stopped"
assert c["HostConfig"]["NetworkMode"] == "default"

bindings=c["HostConfig"]["PortBindings"]
host_binding = bindings["3000/tcp"][0]

assert host_binding["HostPort"] == "80"
assert host_binding["HostIp"] in ("", "0.0.0.0")

assert c["HostConfig"]["LogConfig"]["Type"] == "awslogs"

cfg=c["HostConfig"]["LogConfig"]["Config"]
assert cfg["awslogs-group"] == "/cloud-operations-platform/app"
assert cfg["awslogs-region"] == "ap-southeast-2"
assert cfg["awslogs-stream"] == "ec2-app"
assert cfg["awslogs-create-group"] == "false"
assert cfg["mode"] == "non-blocking"
assert cfg["max-buffer-size"] == "4m"

assert not c["Mounts"]

print("Production configuration checks passed.")
' || die "Production configuration differs from approved baseline."

# Capture canonical runtime configuration for rollback comparison.
runtime_snapshot() {
  docker inspect "$1" | python3 -c '
import json, sys

c = json.load(sys.stdin)[0]

cfg = {
    "user": c["Config"]["User"],
    "entrypoint": c["Config"]["Entrypoint"],
    "cmd": c["Config"]["Cmd"],
    "restart": c["HostConfig"]["RestartPolicy"]["Name"],
    "network": c["HostConfig"]["NetworkMode"],
    "ports": c["HostConfig"]["PortBindings"],
    "log_type": c["HostConfig"]["LogConfig"]["Type"],
    "log_config": c["HostConfig"]["LogConfig"]["Config"],
    "mounts": c["Mounts"],
}

for bindings in cfg["ports"].values():
    for binding in bindings:
        if binding["HostIp"] in ("", "0.0.0.0"):
            binding["HostIp"] = "0.0.0.0"

print(json.dumps(cfg, sort_keys=True, separators=(",", ":")))
'
}

EXPECTED_RUNTIME_CONFIG="$(
  runtime_snapshot "$PRODUCTION"
)" || die "Could not capture production runtime configuration."

# Verify current production health before deployment.
curl --silent --fail --max-time 5 \
  http://127.0.0.1/health -o /dev/null ||
  die "Production is unhealthy before deployment."

if [[ "$TARGET_IMAGE" == "$OLD_IMAGE" ]]; then
  echo "Target is already running. No deployment needed."
  exit 0
fi

# Authenticate and pull the candidate before touching production.
DOCKER_CONFIG_TEMP="$(mktemp -d /tmp/cop-release-auth.XXXXXX)"
chmod 700 "$DOCKER_CONFIG_TEMP"
export DOCKER_CONFIG="$DOCKER_CONFIG_TEMP"

cleanup_auth() {
  if [[ -n "$DOCKER_CONFIG_TEMP" ]]; then
    docker logout "$REGISTRY" >/dev/null 2>&1 || true
    rm -rf -- "$DOCKER_CONFIG_TEMP"
    DOCKER_CONFIG_TEMP=""
  fi
}

trap cleanup_auth EXIT

echo "=== Authenticate to ECR ==="

aws ecr get-login-password --region "$REGION" |
  docker login --username AWS --password-stdin "$REGISTRY"

echo "=== Pull target image ==="

docker pull "$TARGET_IMAGE"

TARGET_IMAGE_ID="$(
  docker image inspect "$TARGET_IMAGE" -f '{{.Id}}'
)"

[[ "$TARGET_IMAGE_ID" =~ ^sha256:[a-f0-9]{64}$ ]] ||
  die "Target image ID unavailable or invalid."

echo "=== Record rollback baseline ==="
echo "Previous image: $OLD_IMAGE"
echo "Previous ID:    $OLD_IMAGE_ID"
echo "Target image:   $TARGET_IMAGE"
echo "Target ID:      $TARGET_IMAGE_ID"

rollback() {
  echo "=== ROLLBACK STARTED ===" >&2

  local rollback_image_id
  local restored_image_id
  local restored_status
  local restored_config

  # Verify previous image BEFORE removing the replacement.
  rollback_image_id="$(
    docker image inspect "$OLD_IMAGE" -f '{{.Id}}'
  )" || {
    echo "CRITICAL: Previous image unavailable." >&2
    return 1
  }

  [[ "$rollback_image_id" == "$OLD_IMAGE_ID" ]] || {
    echo "CRITICAL: Previous image identity mismatch." >&2
    return 1
  }

  # Remove the failed replacement.
  docker rm -f "$PRODUCTION" >/dev/null 2>&1 || true

  docker run -d \
    --name "$PRODUCTION" \
    --restart unless-stopped \
    --user app \
    --publish "0.0.0.0:${PORT}:${CONTAINER_PORT}" \
    --log-driver awslogs \
    --log-opt "awslogs-group=${LOG_GROUP}" \
    --log-opt "awslogs-region=${REGION}" \
    --log-opt "awslogs-stream=${LOG_STREAM}" \
    --log-opt "awslogs-create-group=false" \
    --log-opt "mode=non-blocking" \
    --log-opt "max-buffer-size=4m" \
    "$OLD_IMAGE" >/dev/null || {
      echo "CRITICAL: Could not recreate previous container." >&2
      return 1
    }

  # Verify actual restored image and running state.
  restored_image_id="$(
    docker inspect -f '{{.Image}}' "$PRODUCTION"
  )" || return 1

  restored_status="$(
    docker inspect -f '{{.State.Status}}' "$PRODUCTION"
  )" || return 1

  [[ "$restored_image_id" == "$OLD_IMAGE_ID" ]] || {
    echo "CRITICAL: Restored image identity mismatch." >&2
    return 1
  }

  [[ "$restored_status" == "running" ]] || {
    echo "CRITICAL: Restored container is not running." >&2
    return 1
  }

  # Verify critical runtime settings.
  restored_config="$(
    runtime_snapshot "$PRODUCTION"
  )" || {
    echo "CRITICAL: Could not inspect restored runtime configuration." >&2
    return 1
  }

  [[ "$restored_config" == "$EXPECTED_RUNTIME_CONFIG" ]] || {
    echo "CRITICAL: Restored runtime configuration mismatch." >&2
    return 1
  }

  # Verify host and application health.
  for attempt in $(seq 1 30); do
    if curl --silent --fail --max-time 3 \
      http://127.0.0.1/health -o /dev/null &&
      docker exec "$PRODUCTION" node -e '
        const http = require("http");
        const req = http.get("http://127.0.0.1:3000/health", res => {
          let body = "";
          res.setEncoding("utf8");
          res.on("data", x => body += x);
          res.on("end", () => {
            try {
              const d = JSON.parse(body);
              process.exit(
                res.statusCode === 200 &&
                d.status === "healthy" &&
                d.service === "cloud-operations-platform" ? 0 : 1
              );
            } catch { process.exit(1); }
          });
        }).on("error", () => process.exit(1));
        req.setTimeout(3000, () => {
          req.destroy(new Error("Health check timed out"));
        });
      '; then
      echo "Rollback image, runtime configuration and health verified."
      return 0
    fi

    sleep 2
  done

  echo "CRITICAL: Rollback verification failed." >&2
  return 1
}

# Recovery handler for unexpected exits during cutover.
on_exit() {
  local rc=$?
  trap - EXIT

  if [[ "$ROLLBACK_NEEDED" == "true" ]]; then
    if rollback; then
      echo "Previous release restored and verified." >&2
    else
      echo "CRITICAL: MANUAL RECOVERY REQUIRED." >&2
      rc=1
    fi
  fi

  cleanup_auth
  exit "$rc"
}

# Register the recovery handler before cutover.
trap on_exit EXIT

# Recovery is armed before touching production.
ROLLBACK_NEEDED=true

echo "=== Stop and remove previous container ==="

docker rm -f "$PRODUCTION" >/dev/null

echo "=== Start target release ==="

docker run -d \
  --name "$PRODUCTION" \
  --restart unless-stopped \
  --user app \
  --publish "0.0.0.0:${PORT}:${CONTAINER_PORT}" \
  --log-driver awslogs \
  --log-opt "awslogs-group=${LOG_GROUP}" \
  --log-opt "awslogs-region=${REGION}" \
  --log-opt "awslogs-stream=${LOG_STREAM}" \
  --log-opt "awslogs-create-group=false" \
  --log-opt "mode=non-blocking" \
  --log-opt "max-buffer-size=4m" \
  "$TARGET_IMAGE" >/dev/null

NEW_IMAGE_ID="$(
  docker inspect -f '{{.Image}}' "$PRODUCTION"
)"

[[ "$NEW_IMAGE_ID" == "$TARGET_IMAGE_ID" ]] ||
  die "Running production image identity mismatch."

echo "=== Verify target health ==="

HEALTHY=false

for attempt in $(seq 1 30); do
  if curl --silent --fail --max-time 3 \
    http://127.0.0.1/health -o /dev/null; then

    if docker exec "$PRODUCTION" node -e '
      const http = require("http");
      const req = http.get("http://127.0.0.1:3000/health", res => {
        let body = "";
        res.setEncoding("utf8");
        res.on("data", x => body += x);
        res.on("end", () => {
          try {
            const d = JSON.parse(body);
            process.exit(
              res.statusCode === 200 &&
              d.status === "healthy" &&
              d.service === "cloud-operations-platform" ? 0 : 1
            );
          } catch { process.exit(1); }
        });
      }).on("error", () => process.exit(1));
      req.setTimeout(3000, () => {
        req.destroy(new Error("Health check timed out"));
      });
    '; then
      HEALTHY=true
      break
    fi
  fi

  sleep 2
done

[[ "$HEALTHY" == "true" ]] ||
  die "Target health verification failed."

# Commit the deployment only after successful verification.
ROLLBACK_NEEDED=false

echo "=== DEPLOYMENT SUCCESS ==="
echo "Image: $TARGET_IMAGE"
echo "Image ID: $NEW_IMAGE_ID"
