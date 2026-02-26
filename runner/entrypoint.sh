#!/usr/bin/env bash
set -euo pipefail

# ── Docker socket GID fix (cross-platform) ────────────────────────────────────
# When the host mounts /var/run/docker.sock, the socket's group GID differs by OS:
#   Linux         → host's docker group GID (e.g. 108, 998, 1001, …)
#   macOS/Windows → typically 0 (root) via Docker Desktop
# We detect it at runtime and update the in-container docker group GID to match,
# so the runner user can always reach the socket regardless of host OS.
if [ "$(id -u)" = "0" ]; then
  SOCK=/var/run/docker.sock
  if [ -S "$SOCK" ]; then
    SOCK_GID=$(stat -c '%g' "$SOCK")
    CURRENT_GID=$(getent group docker | cut -d: -f3)
    if [ "$SOCK_GID" = "0" ]; then
      # macOS / Windows Docker Desktop: socket is owned by root (GID 0).
      # We can't groupmod docker to GID 0 (already taken by root), so instead
      # we chown the socket to the docker group inside the container.
      chown root:docker "$SOCK"
      chmod 660 "$SOCK"
    elif [ "$SOCK_GID" != "$CURRENT_GID" ]; then
      # Linux: sync the docker group GID to match the host socket's GID.
      groupmod -g "$SOCK_GID" docker
    fi
    usermod -aG docker runner
  fi
  # Re-exec as the runner user now that the socket is accessible.
  exec sudo -u runner -E "$0" "$@"
fi

# ── Required environment variables ────────────────────────────────────────────
: "${GITHUB_OWNER:?GITHUB_OWNER is required (e.g. my-org or my-user)}"
: "${GITHUB_REPO?GITHUB_REPO is required (leave empty string for org-level runner)}"
: "${GITHUB_PAT:?GITHUB_PAT (Personal Access Token) is required}"

# Give each runner a readable name: "runner-<project>-<short-id>"
# This appears in the GitHub runner dashboard. Users can override via RUNNER_NAME in .env.
RUNNER_NAME="${RUNNER_NAME:-runner-${COMPOSE_PROJECT_NAME:-dbwrap}-$(hostname | cut -c1-8)}"
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
