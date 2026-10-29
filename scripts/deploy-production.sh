#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Controlled single-container production deployment.
# Requires root/Docker access on the EC2 host.
# A short outage is possible during cutover.

REGION="ap-southeast-2"
REGISTRY="074494041866.dkr.ecr.ap-southeast-2.amazonaws.com"
REPOSITORY="cloud-operations-platform"
PRODUCTION="cloud-operations-platform"
PORT="80"
CONTAINER_PORT="3000"

LOG_GROUP="/cloud-operations-platform/app"
LOG_STREAM="ec2-app"

EXPECTED_INITIAL="${REGISTRY}/${REPOSITORY}@sha256:2654baa36c8355f51c09cd4065985536bd14026ab1b06af0fb1ef3067fdebbbc"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

TARGET_DIGEST="${1:-}"

[[ "$TARGET_DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]] ||
  die "Usage: bash scripts/deploy-production.sh sha256:<64-hex>"

TARGET_IMAGE="${REGISTRY}/${REPOSITORY}@${TARGET_DIGEST}"

# Prevent overlapping runs of this script.
exec 9>/tmp/cop-production-deploy.lock
flock -n 9 || die "Another production deployment is running."

# Refuse unknown production state.
OLD_STATUS="$(docker inspect -f '{{.State.Status}}' "$PRODUCTION")"
OLD_IMAGE="$(docker inspect -f '{{.Config.Image}}' "$PRODUCTION")"

[[ "$OLD_STATUS" == "running" ]] ||
  die "Production is not running."

[[ "$OLD_IMAGE" == "$EXPECTED_INITIAL" ]] ||
  die "Production image differs from approved initial baseline. Inspect manually."

# Refuse unexpected runtime configuration.
docker inspect "$PRODUCTION" | python3 -c '
import json,sys
c=json.load(sys.stdin)[0]
assert c["Config"]["User"] == "app"
assert c["Config"]["Entrypoint"] == ["docker-entrypoint.sh"]
assert c["Config"]["Cmd"] == ["node","app.js"]
assert c["HostConfig"]["RestartPolicy"]["Name"] == "unless-stopped"
assert c["HostConfig"]["NetworkMode"] == "default"
assert c["HostConfig"]["PortBindings"]["3000/tcp"][0]["HostPort"] == "80"
assert c["HostConfig"]["LogConfig"]["Type"] == "awslogs"
assert c["HostConfig"]["LogConfig"]["Config"]["awslogs-group"] == "/cloud-operations-platform/app"
assert c["HostConfig"]["LogConfig"]["Config"]["awslogs-stream"] == "ec2-app"
assert not c["Mounts"]
print("Production configuration checks passed.")
' || die "Production configuration differs from expected baseline."

curl --silent --fail --max-time 5 \
  http://127.0.0.1/health >/dev/null ||
  die "Production is unhealthy before deployment."

if [[ "$TARGET_IMAGE" == "$OLD_IMAGE" ]]; then
  echo "Target is already running. No deployment needed."
  exit 0
fi

# Confirm the target can be pulled before touching production.
DOCKER_CONFIG_TEMP="$(mktemp -d /tmp/cop-release-auth.XXXXXX)"
chmod 700 "$DOCKER_CONFIG_TEMP"
export DOCKER_CONFIG="$DOCKER_CONFIG_TEMP"

cleanup_auth() {
  docker logout "$REGISTRY" >/dev/null 2>&1 || true
  rm -rf -- "$DOCKER_CONFIG_TEMP"
}
trap cleanup_auth EXIT

echo "=== Authenticate to ECR ==="
aws ecr get-login-password --region "$REGION" |
  docker login --username AWS --password-stdin "$REGISTRY"

echo "=== Pull target image ==="
docker pull "$TARGET_IMAGE"

TARGET_IMAGE_ID="$(docker image inspect "$TARGET_IMAGE" -f '{{.Id}}')"
[[ -n "$TARGET_IMAGE_ID" ]] || die "Target image ID unavailable."

echo "=== Record rollback baseline ==="
echo "Previous image: $OLD_IMAGE"
echo "Target image:   $TARGET_IMAGE"

# We have a single fixed production container and a single fixed port.
# Replacement introduces a short service interruption.
# Arm recovery BEFORE touching production.
ROLLBACK_NEEDED=true

echo "=== Stop and remove previous container ==="
docker rm -f "$PRODUCTION" >/dev/null

rollback() {
  echo "=== ROLLBACK STARTED ===" >&2

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

  for attempt in $(seq 1 30); do
    if curl --silent --fail --max-time 3 \
      http://127.0.0.1/health -o /dev/null; then
      echo "Rollback health verified."
      return 0
    fi
    sleep 2
  done

  echo "CRITICAL: Rollback container started but health failed." >&2
  return 1
}

# If this shell exits unexpectedly after cutover, attempt rollback.
on_exit() {
  rc=$?
  trap - EXIT

  if [[ "$ROLLBACK_NEEDED" == "true" ]]; then
    if ! rollback; then
      echo "CRITICAL: MANUAL RECOVERY REQUIRED." >&2
      rc=1
    fi
  fi

  cleanup_auth
  exit "$rc"
}
trap on_exit EXIT

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

NEW_IMAGE_ID="$(docker inspect -f '{{.Image}}' "$PRODUCTION")"

[[ "$NEW_IMAGE_ID" == "$TARGET_IMAGE_ID" ]] ||
  die "Running production image identity mismatch."

echo "=== Verify target health ==="

HEALTHY=false

for attempt in $(seq 1 30); do
  if curl --silent --fail --max-time 3 \
    http://127.0.0.1/health -o /dev/null; then

    if docker exec "$PRODUCTION" node -e '
      const http = require("http");
      http.get("http://127.0.0.1:3000/health", res => {
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
    '; then
      HEALTHY=true
      break
    fi
  fi

  sleep 2
done

[[ "$HEALTHY" == "true" ]] ||
  die "New release failed health verification."

ROLLBACK_NEEDED=false

echo "=== RELEASE SUCCESS ==="
echo "Production image: $TARGET_IMAGE"
echo "Production health verified."
echo "Previous image: $OLD_IMAGE"
echo "Deployment complete."
