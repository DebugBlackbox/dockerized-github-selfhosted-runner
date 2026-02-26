#!/usr/bin/env bash
set -euo pipefail

# ── Required environment variables ────────────────────────────────────────────
: "${GITHUB_OWNER:?GITHUB_OWNER is required (e.g. my-org or my-user)}"
: "${GITHUB_REPO:?GITHUB_REPO is required (leave empty string for org-level runner)}"
: "${GITHUB_PAT:?GITHUB_PAT (Personal Access Token) is required}"

RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,linux,arm64}"
RUNNER_GROUP="${RUNNER_GROUP:-Default}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-/tmp/_work}"

# ── Derive the registration URL & token endpoint ──────────────────────────────
if [[ -n "${GITHUB_REPO}" ]]; then
  REGISTRATION_URL="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}"
  TOKEN_API="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/actions/runners/registration-token"
else
  # Org-level runner
  REGISTRATION_URL="https://github.com/${GITHUB_OWNER}"
  TOKEN_API="https://api.github.com/orgs/${GITHUB_OWNER}/actions/runners/registration-token"
fi

echo "[runner] Fetching registration token from ${TOKEN_API} …"
REG_TOKEN=$(curl -fsSL \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_PAT}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "${TOKEN_API}" | jq -r '.token')

if [[ -z "${REG_TOKEN}" || "${REG_TOKEN}" == "null" ]]; then
  echo "[runner] ERROR: Failed to obtain a registration token. Check GITHUB_PAT and org/repo settings." >&2
  exit 1
fi

# ── Configure the runner ──────────────────────────────────────────────────────
echo "[runner] Configuring runner '${RUNNER_NAME}' → ${REGISTRATION_URL}"
./config.sh \
  --unattended \
  --replace \
  --url "${REGISTRATION_URL}" \
  --token "${REG_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${RUNNER_LABELS}" \
  --runnergroup "${RUNNER_GROUP}" \
  --work "${RUNNER_WORKDIR}" \
  --ephemeral

# ── Graceful cleanup on SIGTERM / SIGINT ─────────────────────────────────────
cleanup() {
  echo "[runner] Received shutdown signal — deregistering runner …"
  REMOVE_TOKEN=$(curl -fsSL \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_PAT}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${TOKEN_API/registration/remove}" | jq -r '.token')
  ./config.sh remove --unattended --token "${REMOVE_TOKEN}" 2>/dev/null || true
  echo "[runner] Done."
}

trap cleanup SIGTERM SIGINT

# ── Start the runner (foreground) ─────────────────────────────────────────────
echo "[runner] Starting …"
./run.sh &
wait $!
