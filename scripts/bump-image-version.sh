#!/usr/bin/env bash
set -euo pipefail

# CI-friendly image bump + PR opener using HTTPS + PAT
#
# Usage:
#   ./bump-image.sh <OVERLAY_DIR> <IMAGE_NAME> <NEW_TAG>
#
# Example:
#   ./bump-image.sh ping/overlays/dev daoquocquyen/ping 1.0.3
#
# Required env (CI):
#   GH_TOKEN or GITHUB_TOKEN   # Personal Access Token or Actions token
#
if [[ $# -lt 3 ]]; then
  echo "ERROR: Missing arguments." >&2
  echo "Usage: $0 <OVERLAY_DIR> <IMAGE_NAME> <NEW_TAG>" >&2
  exit 1
fi

OVERLAY_DIR="$1"
IMAGE_NAME="$2"
NEW_TAG="$3"

BASE_BRANCH="${BASE_BRANCH:-main}"
REMOTE="${REMOTE:-origin}"

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "${TOKEN}" ]]; then
  echo "ERROR: GH_TOKEN or GITHUB_TOKEN must be set for CI authentication." >&2
  exit 1
fi

# --- Preconditions -----------------------------------------------------------
command -v git >/dev/null 2>&1 || { echo "ERROR: git not found."; exit 1; }
command -v gh  >/dev/null 2>&1 || { echo "ERROR: gh (GitHub CLI) not found."; exit 1; }
command -v sed >/dev/null 2>&1 || { echo "ERROR: sed not found."; exit 1; }

# Ensure we're in a git repo
cd ${OVERLAY_DIR}
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "ERROR: Not inside a git repository." >&2
  exit 1
}

# Set git identity to jenkins-bot if not already configured (common in CI)
if ! git config user.name >/dev/null; then
  git config user.name "jenkins-bot"
fi
if ! git config user.email >/dev/null; then
  git config user.email "jenkins-bot@localhost"
fi

# --- Locate file and verify image entry --------------------------------------
KFILE="kustomization.yaml"
if [[ ! -f "$KFILE" ]]; then
  echo "ERROR: File not found: $KFILE" >&2
  exit 1
fi

# --- Update newTag ---
sed -Ei "s/^([[:space:]]*newTag:[[:space:]]*).*/\1${NEW_TAG}/" "$KFILE"

# Quick sanity output: print the image line and the following line
echo "Updated tag in $KFILE:"
awk -v img="$IMAGE_NAME" '
  $0 ~ "^[[:space:]]*-[[:space:]]*name:[[:space:]]*"img"[[:space:]]*$" {print; getline; print; exit}
' "$KFILE" || true

# --- Branch, commit, push, PR -----------------------------------------------
SAFE_IMG="${IMAGE_NAME//\//-}"
SAFE_TAG="$(echo "$NEW_TAG" | tr -c '[:alnum:]._-' '-')"
BRANCH="bump-${SAFE_IMG}-${SAFE_TAG}"

git checkout -b "$BRANCH"
git add "$KFILE"

if git diff --cached --quiet; then
  echo "No changes detected in $KFILE; nothing to commit."
else
  # Commit the change
  git commit -m "chore(${OVERLAY_DIR}): bump ${IMAGE_NAME} to ${NEW_TAG}"

  # Set up git to use the token for authentication
  git remote set-url origin "https://jenkins-bot:${GH_TOKEN}@github.com/daoquocquyen/pingpong-gitops-config.git"

  # Push the branch to origin
  git push -u origin "$BRANCH"

  gh pr create \
    --base "$BASE_BRANCH" \
    --head "$BRANCH" \
    --title "chore(${OVERLAY_DIR}): bump ${IMAGE_NAME} to ${NEW_TAG}" \
    --body "Update \`${KFILE}\` to set \`newTag: ${NEW_TAG}\` for \`${IMAGE_NAME}\`."

  echo "Created PR to bump ${IMAGE_NAME} to ${NEW_TAG}."
fi

