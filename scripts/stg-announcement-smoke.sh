#!/usr/bin/env bash
set -euo pipefail

# STG-only smoke test for announcement APIs.
# Usage:
#   STG_BASE_URL="https://stg-api.example.com/assistant" \
#   STG_BEARER_TOKEN="xxx" \
#   ./scripts/stg-announcement-smoke.sh

if [[ -z "${STG_BASE_URL:-}" ]]; then
  echo "STG_BASE_URL is required"
  exit 1
fi

if [[ -z "${STG_BEARER_TOKEN:-}" ]]; then
  echo "STG_BEARER_TOKEN is required"
  exit 1
fi

if [[ "${STG_BASE_URL}" != *"stg"* && "${STG_BASE_URL}" != *"staging"* ]]; then
  echo "Refusing to run: STG_BASE_URL does not look like STG (${STG_BASE_URL})"
  exit 1
fi

echo "[1/3] GET active announcements (scene=chat_list, platform=android)"
ACTIVE_JSON="$(
  curl -fsS \
    -H "Authorization: Bearer ${STG_BEARER_TOKEN}" \
    -H "Content-Type: application/json" \
    "${STG_BASE_URL}/api/announcements/active?scene=chat_list&platform=android"
)"

echo "${ACTIVE_JSON}"

ANNOUNCEMENT_ID="$(printf '%s' "${ACTIVE_JSON}" | sed -n 's/.*"announcement_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
if [[ -z "${ANNOUNCEMENT_ID}" ]]; then
  echo "No announcement_id found in active response, stop here."
  exit 0
fi

echo "[2/3] POST impression event: ${ANNOUNCEMENT_ID}"
curl -fsS \
  -X POST \
  -H "Authorization: Bearer ${STG_BEARER_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"event_type\":\"impression\",\"scene\":\"chat_list\",\"platform\":\"android\",\"occurred_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
  "${STG_BASE_URL}/api/announcements/${ANNOUNCEMENT_ID}/events"
echo

echo "[3/3] POST click event: ${ANNOUNCEMENT_ID}"
curl -fsS \
  -X POST \
  -H "Authorization: Bearer ${STG_BEARER_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"event_type\":\"click\",\"scene\":\"chat_list\",\"platform\":\"android\",\"occurred_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
  "${STG_BASE_URL}/api/announcements/${ANNOUNCEMENT_ID}/events"
echo

echo "STG announcement smoke test completed."
