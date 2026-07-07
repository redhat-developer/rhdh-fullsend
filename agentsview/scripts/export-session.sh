#!/usr/bin/env bash
# Export a Claude Code session transcript to the shared sessions repo.
#
# Called by the SessionEnd hook — receives session metadata as JSON on stdin.
#
# Usage (hook):
#   bash agentsview/scripts/export-session.sh    # stdin: JSON with transcript_path, session_id, cwd
#
# Usage (manual test):
#   echo '{"transcript_path":"/path/to.jsonl","session_id":"abc-123","cwd":"/Users/me/myproject"}' \
#     | bash agentsview/scripts/export-session.sh
#
# Prerequisites: jq, git
#
# Configuration:
#   ~/.config/fullsend/sessions.env must define FULLSEND_SESSIONS_REPO=/path/to/repo
#
# Directory layout produced (matches AgentsView Claude discovery):
#   <sessions-repo>/<user>_<project>/<session-id>.jsonl

set -euo pipefail

CONFIG_FILE="${HOME}/.config/fullsend/sessions.env"

# --- Load config -----------------------------------------------------------

if [ ! -f "$CONFIG_FILE" ]; then
  exit 0
fi

# shellcheck source=/dev/null
. "$CONFIG_FILE"

if [ -z "${FULLSEND_SESSIONS_REPO:-}" ]; then
  exit 0
fi

if [ ! -d "$FULLSEND_SESSIONS_REPO" ]; then
  exit 0
fi

# --- Parse stdin JSON -------------------------------------------------------

INPUT="$(cat)"

TRANSCRIPT_PATH="$(echo "$INPUT" | jq -r '.transcript_path // empty')"
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
SESSION_CWD="$(echo "$INPUT" | jq -r '.cwd // empty')"

if [ -z "$TRANSCRIPT_PATH" ] || [ -z "$SESSION_ID" ]; then
  exit 0
fi

if [ ! -f "$TRANSCRIPT_PATH" ] || [ ! -s "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

# --- Derive names -----------------------------------------------------------

USERNAME="$(git config user.name 2>/dev/null | tr ' ' '-' | tr '[:upper:]' '[:lower:]' || echo "${USER:-unknown}")"
PROJECT="$(basename "${SESSION_CWD:-unknown}")"

PROJECT_DIR="${FULLSEND_SESSIONS_REPO}/${USERNAME}_${PROJECT}"
DEST_FILE="${PROJECT_DIR}/${SESSION_ID}.jsonl"

if [ -f "$DEST_FILE" ]; then
  exit 0
fi

# --- Build metadata line ----------------------------------------------------

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

META_LINE="$(jq -nc \
  --arg project "$PROJECT" \
  --arg user "$USERNAME" \
  --arg ts "$TIMESTAMP" \
  --arg cwd "/sessions/${USERNAME}_${PROJECT}" \
  '{
    type: "user",
    timestamp: $ts,
    message: { content: ("[Session: \($project)] by \($user)\nProject: \($cwd)") },
    cwd: $cwd
  }'
)"

# --- Copy transcript with metadata -----------------------------------------

mkdir -p "$PROJECT_DIR"

{ echo "$META_LINE"; cat "$TRANSCRIPT_PATH"; } > "$DEST_FILE"

# --- Commit in sessions repo ------------------------------------------------

git -C "$FULLSEND_SESSIONS_REPO" add "${USERNAME}_${PROJECT}/${SESSION_ID}.jsonl"
git -C "$FULLSEND_SESSIONS_REPO" commit -q -m "feat: add session ${USERNAME}/${PROJECT}/${SESSION_ID}" \
  2>/dev/null || true
