
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Candidate validation ONLY.
# Never replaces or restarts production.

REGION="ap-southeast-2"
REPOSITORY="cloud-operations-platform"
REGISTRY="074494041866.dkr.ecr.ap-southeast-2.amazonaws.com"
PRODUCTION="cloud-operations-platform"
CANDIDATE="cloud-operations-platform-candidate"
CANDIDATE_PORT="18080"
EXPECTED_PROD_IMAGE="${REGISTRY}/${REPOSITORY}@sha256:2654baa36c8355f51c09cd4065985536bd14026ab1b06af0fb1ef3067fdebbbc"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

IMAGE_DIGEST="${1:-}"

[[ "$IMAGE_DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]] ||
  die "Usage: bash scripts/deploy.sh sha256:<64-hex>"

IMAGE="${REGISTRY}/${REPOSITORY}@${IMAGE_DIGEST}"

# Serialize this script to prevent overlapping test runs.
LOCK="/tmp/cop-candidate-deploy.lock"
exec 9>"$LOCK"
flock -n 9 || die "Another candidate test is running."

# Use a temporary, private Docker credential configuration.
DOCKER_CONFIG_TEMP="$(mktemp -d /tmp/cop-docker-config.XXXXXX)"
chmod 700 "$DOCKER_CONFIG_TEMP"

CANDIDATE_CREATED=false

cleanup() {
  rc=$?
  trap - EXIT

  if [[ "$CANDIDATE_CREATED" == "true" ]]; then
    echo "Removing candidate container..."
    docker rm -f "$CANDIDATE" >/dev/null 2>&1 || {
      echo "WARNING: Candidate cleanup failed. Inspect it manually." >&2
      rc=1
    }
  fi

  docker logout "$REGISTRY" \
    --config "$DOCKER_CONFIG_TEMP" >/dev/null 2>&1 || true

  rm -rf -- "$DOCKER_CONFIG_TEMP"
  exit "$rc"
}

trap cleanup EXIT

echo "=== Docker availability ==="
docker info >/dev/null

echo "=== Production verification ==="

PROD_STATUS="$(docker inspect -f '{{.State.Status}}' "$PRODUCTION")"
PROD_IMAGE="$(docker inspect -f '{{.Config.Image}}' "$PRODUCTION")"

[[ "$PROD_STATUS" == "running" ]] ||
  die "Production is not running."

[[ "$PROD_IMAGE" == "$EXPECTED_PROD_IMAGE" ]] ||
  die "Production image differs from the expected baseline."

echo "Production is running expected image."

echo "=== Candidate checks ==="

if docker inspect "$CANDIDATE" >/dev/null 2>&1; then
  die "Candidate already exists. Inspect it manually."
fi

if ss -ltn | grep -Eq '127\.0\.0\.1:18080|0\.0\.0\.0:18080|\[::\]:18080'; then
  die "Candidate port appears occupied."
fi

echo "=== ECR authentication ==="

export DOCKER_CONFIG="$DOCKER_CONFIG_TEMP"

aws ecr get-login-password --region "$REGION" |
  docker login \
    --username AWS \
    --password-stdin "$REGISTRY"

echo "=== Pull candidate image ==="
docker pull "$IMAGE"

echo "=== Verify pulled image ==="

EXPECTED_IMAGE_ID="$(docker image inspect "$IMAGE" -f '{{.Id}}')"
[[ -n "$EXPECTED_IMAGE_ID" ]] ||
  die "Could not determine expected image ID."

echo "=== Start isolated candidate ==="

# Mark before docker run so cleanup handles partial creation.
CANDIDATE_CREATED=true

docker run -d \
  --name "$CANDIDATE" \
  --restart no \
  --publish "127.0.0.1:${CANDIDATE_PORT}:3000" \
  "$IMAGE" >/dev/null

ACTUAL_IMAGE_ID="$(docker inspect -f '{{.Image}}' "$CANDIDATE")"
ACTUAL_IMAGE_REF="$(docker inspect -f '{{.Config.Image}}' "$CANDIDATE")"

[[ "$ACTUAL_IMAGE_ID" == "$EXPECTED_IMAGE_ID" ]] ||
  die "Candidate image ID mismatch."

[[ "$ACTUAL_IMAGE_REF" == "$IMAGE" ]] ||
  die "Candidate configured image reference mismatch."

echo "=== Candidate health verification ==="

HEALTHY=false

for attempt in $(seq 1 30); do
  if curl --silent --fail --max-time 3 \
      "http://127.0.0.1:${CANDIDATE_PORT}/health" \
      -o /dev/null; then

    if docker exec "$CANDIDATE" node -e '
      const http = require("http");
      http.get("http://127.0.0.1:3000/health", res => {
        let body = "";
        res.setEncoding("utf8");
        res.on("data", chunk => body += chunk);
        res.on("end", () => {
          try {
            const d = JSON.parse(body);
            process.exit(
              res.statusCode === 200 &&
              d.status === "healthy" &&
              d.service === "cloud-operations-platform" ? 0 : 1
            );
          } catch {
            process.exit(1);
          }
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
  die "Candidate health verification failed."

echo "Candidate health verified."
echo "Candidate image: $ACTUAL_IMAGE_REF"
echo "Candidate image ID: $ACTUAL_IMAGE_ID"
echo "Production was NOT modified."
