#!/usr/bin/env bash
# post-grillme.sh — Post grillme agent output as PR comment(s).
#
# Runs on the trusted runner AFTER the sandbox is destroyed.
#
# Two-comment model for subsequent turns (when an answer was provided):
#   1. Short "Recorded: ..." acknowledgment comment
#   2. New top-level comment with the next question (or session summary)
#
# First-turn and session-complete turns post a single comment.
#
# SECURITY: Agent output is untrusted. We:
#   - Extract text via jq (no shell eval of agent strings)
#   - Truncate to a safe length (prevent comment-bomb)
#   - Post via --body-file - (no shell interpolation)
#   - Validate ISSUE_NUMBER is numeric
#   - Validate REPO_FULL_NAME matches owner/repo pattern

set -euo pipefail

_TOKEN="${REVIEW_TOKEN:-${GH_TOKEN:-}}"
if [[ -z "${_TOKEN}" ]]; then
  echo "::error::REVIEW_TOKEN or GH_TOKEN is required"
  exit 1
fi
echo "::add-mask::${_TOKEN}"
export GH_TOKEN="${_TOKEN}"

ISSUE_NUMBER="${ISSUE_NUMBER:-${PR_NUMBER:-}}"
if [[ ! "${ISSUE_NUMBER}" =~ ^[0-9]+$ ]]; then
  echo "::error::ISSUE_NUMBER/PR_NUMBER must be numeric, got: '${ISSUE_NUMBER:-}'"
  exit 1
fi

if [[ ! "${REPO_FULL_NAME:-}" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]]; then
  echo "::error::REPO_FULL_NAME is not set or invalid: '${REPO_FULL_NAME:-}'"
  exit 1
fi

# --- Find the output file ---

OUTPUT_FILE=""
if [[ -n "${FULLSEND_VALIDATED_ITERATION_DIR:-}" && -f "${FULLSEND_VALIDATED_ITERATION_DIR}/output.jsonl" ]]; then
  OUTPUT_FILE="${FULLSEND_VALIDATED_ITERATION_DIR}/output.jsonl"
else
  for dir in iteration-*/; do
    if [[ -f "${dir}/output.jsonl" ]]; then
      OUTPUT_FILE="${dir}/output.jsonl"
    fi
  done
fi

if [[ -z "${OUTPUT_FILE}" ]]; then
  echo "WARNING: output.jsonl not found — agent may have crashed before producing output"
  BODY="<!-- fullsend:grillme -->
## Grillme

⚠️ Grillme agent produced no output. Check the [workflow run](${RUN_URL:-}) for logs.

---
<sub>Posted by grillme agent · [Run logs](${RUN_URL:-})</sub>"
  printf '%s' "${BODY}" | gh issue comment "${ISSUE_NUMBER}" --repo "${REPO_FULL_NAME}" --body-file -
  exit 0
fi

echo "Reading agent output from: ${OUTPUT_FILE}"

# --- Extract the last assistant text block ---

SUMMARY=$(jq -s -r '
  [ .[]
    | select(.type == "assistant")
    | .message.content[]?
    | select(.type == "text")
    | .text
  ]
  | if length == 0 then empty else .[-1] end
' "${OUTPUT_FILE}")

if [[ -z "${SUMMARY}" ]]; then
  echo "WARNING: No assistant text found in output.jsonl"
  SUMMARY="⚠️ Grillme agent ran but produced no text output."
fi

SUMMARY="${SUMMARY:0:60000}"

# --- Post helper ---

post_comment() {
  local body="$1"
  printf '%s' "${body}" | gh issue comment "${ISSUE_NUMBER}" --repo "${REPO_FULL_NAME}" --body-file -
}

FOOTER="<sub>Reply with <code>/fs-grillme &lt;your answer&gt;</code> to continue · [Run logs](${RUN_URL:-})</sub>"
FOOTER_CLOSE="<sub>Start a new session with <code>/fs-grillme</code> · [Run logs](${RUN_URL:-})</sub>"

# --- Two-comment split ---
#
# If the agent output contains a "Recorded:" line followed by a "---"
# separator, split into an ack comment and a question/summary comment.
# The separator pattern is: line starting with **Recorded:**, then a line
# that is exactly "---", with the next-question block after.

if printf '%s' "${SUMMARY}" | grep -qE '^\*\*Recorded:\*\*'; then
  RECORDED_PART=$(printf '%s' "${SUMMARY}" | awk '
    /^---[[:space:]]*$/ && found { exit }
    { print; found=1 }
  ')
  QUESTION_PART=$(printf '%s' "${SUMMARY}" | awk '
    BEGIN { past_sep=0 }
    past_sep { print; next }
    /^---[[:space:]]*$/ && found { past_sep=1; next }
    { found=1 }
  ')

  if [[ -n "${RECORDED_PART}" && -n "${QUESTION_PART}" ]]; then
    # Comment 1: Ack
    ACK_COMMENT="<!-- fullsend:grillme:ack -->
${RECORDED_PART}

---
<sub>Posted by grillme agent</sub>"
    post_comment "${ACK_COMMENT}"
    echo "Ack comment posted"

    # Detect session-complete for a different footer.
    if printf '%s' "${QUESTION_PART}" | grep -qiE '(session complete|grill session complete)'; then
      Q_FOOTER="${FOOTER_CLOSE}"
    else
      Q_FOOTER="${FOOTER}"
    fi

    # Comment 2: Question or summary
    Q_COMMENT="<!-- fullsend:grillme -->
## 🔥 Grillme

${QUESTION_PART}

---
${Q_FOOTER}"
    post_comment "${Q_COMMENT}"
    echo "Question/summary comment posted to ${REPO_FULL_NAME}#${ISSUE_NUMBER}"
    exit 0
  fi
fi

# --- Single-comment fallback (first turn or unsplittable output) ---

if printf '%s' "${SUMMARY}" | grep -qiE '(session complete|grill session complete)'; then
  SINGLE_FOOTER="${FOOTER_CLOSE}"
else
  SINGLE_FOOTER="${FOOTER}"
fi

COMMENT="<!-- fullsend:grillme -->
## 🔥 Grillme

${SUMMARY}

---
${SINGLE_FOOTER}"

post_comment "${COMMENT}"
echo "Grillme turn posted to ${REPO_FULL_NAME}#${ISSUE_NUMBER}"
