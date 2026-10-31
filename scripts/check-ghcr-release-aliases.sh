#!/usr/bin/env bash
set -Eeuo pipefail

# Read-only GHCR release alias preflight.
# Required environment:
#   RELEASE_IMAGE: ghcr.io/owner/package
#   IMAGE_TAGS: newline-separated full image references

: "${RELEASE_IMAGE:?RELEASE_IMAGE is required}"
: "${IMAGE_TAGS:?IMAGE_TAGS is required}"

EXPECTED_REPOSITORY="${RELEASE_IMAGE#ghcr.io/}"

if [[ "$RELEASE_IMAGE" != ghcr.io/* ]] ||
   [[ "$EXPECTED_REPOSITORY" == "$RELEASE_IMAGE" ]] ||
   [[ "$EXPECTED_REPOSITORY" == */*/* ]]; then
  echo "Invalid GHCR image repository."
  exit 1
fi

declare -A SEEN_TAGS=()
declare -a TAGS=()

while IFS= read -r ref; do
  [[ -n "$ref" ]] || continue

  prefix="${RELEASE_IMAGE}:"
  if [[ "$ref" != "$prefix"* ]]; then
    echo "Unexpected image reference: $ref"
    exit 1
  fi

  tag="${ref#"$prefix"}"

  if [[ ! "$tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
    echo "Invalid image tag: $tag"
    exit 1
  fi

  if [[ -n "${SEEN_TAGS[$tag]+x}" ]]; then
    echo "Duplicate release alias: $tag"
    exit 1
  fi

  SEEN_TAGS["$tag"]=1
  TAGS+=("$tag")
done <<< "$IMAGE_TAGS"

if (( ${#TAGS[@]} == 0 )); then
  echo "No release aliases supplied."
  exit 1
fi

# Obtain a pull token without logging its contents.
TOKEN_RESPONSE="$(
  curl --fail-with-body --silent --show-error \
    --connect-timeout 5 --max-time 20 \
    --get 'https://ghcr.io/token' \
    --data-urlencode "scope=repository:${EXPECTED_REPOSITORY}:pull"
)" || {
  echo "Unable to obtain GHCR pull token."
  exit 1
}

TOKEN="$(jq -er '.token // .access_token' <<< "$TOKEN_RESPONSE")"
unset TOKEN_RESPONSE

cleanup() {
  unset TOKEN
}
trap cleanup EXIT

for tag in "${TAGS[@]}"; do
  URL="https://ghcr.io/v2/${EXPECTED_REPOSITORY}/manifests/${tag}"

  # Capture the HTTP result; curl transport errors remain failures.
  STATUS="$(
    curl --silent --show-error \
      --connect-timeout 5 --max-time 20 \
      --output /dev/null \
      --write-out '%{http_code}' \
      --head \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json" \
      "$URL"
  )" || {
    echo "Registry request failed for alias: $tag"
    exit 1
  }

  case "$STATUS" in
    200)
      echo "Release alias already exists: $tag"
      exit 1
      ;;
    404)
      echo "Alias confirmed absent: $tag"
      ;;
    *)
      echo "Unexpected GHCR response for $tag: HTTP $STATUS"
      exit 1
      ;;
  esac
done

echo "Preflight passed: all release aliases are currently absent."
