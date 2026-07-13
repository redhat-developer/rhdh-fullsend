#!/usr/bin/env bash
set -euo pipefail

# Phase 1: Download fullsend artifact ZIPs from GitHub Actions.
#
# Artifacts are cached in artifacts/<repo>/<run_id>_<artifact_name>.zip
# with a sidecar .json containing run metadata.  Conversion into the
# AgentsView layout is handled separately by convert-artifacts.sh.
#
# Usage:
#   ./fetch-artifacts.sh                          # default repos (7 days)
#   ./fetch-artifacts.sh --since 30d              # last 30 days
#   ./fetch-artifacts.sh --all                    # all available artifacts
#   ./fetch-artifacts.sh org/repo1 org/repo2      # custom repos
#   ./fetch-artifacts.sh --since 14d org/repo1    # custom repos + window
#
# Prerequisites: gh (authenticated), jq, curl

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${SCRIPT_DIR}/../artifacts}"

# The Actions artifacts endpoint only supports exact-name filtering. Keep the
# known fullsend agent artifact names configurable so new agents can be added
# without falling back to enumerating every artifact in a busy repository.
FULLSEND_ARTIFACT_NAMES=${FULLSEND_ARTIFACT_NAMES:-"fullsend-code fullsend-debug fullsend-fix fullsend-retro fullsend-review fullsend-triage"}
read -r -a ARTIFACT_NAMES <<< "$FULLSEND_ARTIFACT_NAMES"

# --- Parse flags --------------------------------------------------------
SINCE_DAYS=7
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE_DAYS="${2%d}"; shift 2 ;;
    --all)   SINCE_DAYS=0; shift ;;
    *)       break ;;
  esac
done

if [ $# -gt 0 ]; then
  REPOS=("$@")
else
  REPOS=(
    "redhat-developer/rhdh-agentic"
    "redhat-developer/rhdh-plugins"
    "redhat-developer/rhdh-plugin-export-overlays"
  )
fi

# --- Cutoff date --------------------------------------------------------
if [ "$SINCE_DAYS" -gt 0 ]; then
  if date -v-1d >/dev/null 2>&1; then
    SINCE_DATE=$(date -v-"${SINCE_DAYS}"d -u +%Y-%m-%dT00:00:00Z)
  else
    SINCE_DATE=$(date -u -d "${SINCE_DAYS} days ago" +%Y-%m-%dT00:00:00Z)
  fi
else
  SINCE_DATE=""
fi

# --- Prerequisites ------------------------------------------------------
for cmd in gh jq curl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "error: $cmd is required" >&2; exit 1; }
done

GH_TOKEN=$(gh auth token)
mkdir -p "$ARTIFACTS_DIR"

echo "Fetching fullsend artifacts -> $ARTIFACTS_DIR"
echo "Repos: ${REPOS[*]}"
if [ -n "$SINCE_DATE" ]; then
  echo "Since: $SINCE_DATE (${SINCE_DAYS}d)"
else
  echo "Since: all available"
fi
echo

total_fetched=0
total_skipped=0

for repo in "${REPOS[@]}"; do
  repo_name=$(basename "$repo")
  echo "--- $repo ---"

  # Cache repo CLAUDE.md / AGENTS.md (for prompt reconstruction in convert step)
  repo_dir="${ARTIFACTS_DIR}/${repo_name}"
  mkdir -p "$repo_dir"

  repo_claude=$(gh api "repos/${repo}/contents/CLAUDE.md" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || true)
  [ -n "$repo_claude" ] && printf '%s' "$repo_claude" > "${repo_dir}/CLAUDE.md"

  repo_agents=$(gh api "repos/${repo}/contents/AGENTS.md" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || true)
  [ -n "$repo_agents" ] && printf '%s' "$repo_agents" > "${repo_dir}/AGENTS.md"

  # Query exact fullsend artifact names at the API level. Busy repositories can
  # retain tens of thousands of unrelated artifacts, so fetching every page and
  # filtering locally is prohibitively slow. Pages are newest-first; for a
  # bounded date window, stop as soon as the page reaches older artifacts.
  artifacts='[]'
  for artifact_name in "${ARTIFACT_NAMES[@]}"; do
    page=1
    while true; do
      if ! response=$(gh api "repos/${repo}/actions/artifacts?name=${artifact_name}&per_page=100&page=${page}" 2>/dev/null); then
        echo "  [warn] could not list ${artifact_name} artifacts"
        break
      fi

      page_count=$(echo "$response" | jq '.artifacts | length')
      [ "$page_count" -eq 0 ] && break

      page_artifacts=$(echo "$response" | jq \
        --arg since "$SINCE_DATE" \
        '[.artifacts[]
          | select(.expired == false)
          | select($since == "" or .created_at >= $since)
          | {id:.id, name:.name, run_id:.workflow_run.id, created:.created_at}]')
      artifacts=$(jq -cn \
        --argjson existing "$artifacts" \
        --argjson incoming "$page_artifacts" \
        '$existing + $incoming')

      oldest_created=$(echo "$response" | jq -r '.artifacts[-1].created_at // empty')
      if [ "$page_count" -lt 100 ] || \
         { [ -n "$SINCE_DATE" ] && [[ "$oldest_created" < "$SINCE_DATE" ]]; }; then
        break
      fi
      page=$((page + 1))
    done
  done

  count=$(echo "$artifacts" | jq 'length')
  echo "  $count fullsend artifact(s)"

  for ((i = 0; i < count; i++)); do
    art_id=$(echo "$artifacts" | jq -r ".[$i].id")
    art_name=$(echo "$artifacts" | jq -r ".[$i].name")
    run_id=$(echo "$artifacts" | jq -r ".[$i].run_id")
    created=$(echo "$artifacts" | jq -r ".[$i].created")

    zip_file="${repo_dir}/${run_id}_${art_name}.zip"

    # Cache hit — ZIP already downloaded
    if [ -f "$zip_file" ]; then
      total_skipped=$((total_skipped + 1))
      continue
    fi

    # Fetch run metadata (conclusion, URL)
    run_meta=$(gh api "repos/${repo}/actions/runs/${run_id}" \
      --jq '{conclusion:.conclusion, url:.html_url}' 2>/dev/null) || continue
    conclusion=$(echo "$run_meta" | jq -r '.conclusion')
    run_url=$(echo "$run_meta" | jq -r '.url')

    echo "  run $run_id | $art_name | $conclusion"

    # Download artifact ZIP via GitHub API
    http_code=$(curl -sL -w '%{http_code}' \
      -H "Authorization: Bearer ${GH_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${repo}/actions/artifacts/${art_id}/zip" \
      -o "$zip_file" 2>/dev/null)

    if [ "$http_code" != "200" ]; then
      rm -f "$zip_file"
      echo "    (download failed: HTTP $http_code)"
      continue
    fi

    # Write metadata sidecar (everything the convert step needs)
    agent_name=${art_name#fullsend-}
    jq -nc \
      --arg run_id "$run_id" \
      --arg repo "$repo" \
      --arg artifact_name "$art_name" \
      --arg agent_name "$agent_name" \
      --arg conclusion "$conclusion" \
      --arg run_url "$run_url" \
      --arg created "$created" \
      '{
        run_id: $run_id,
        repo: $repo,
        artifact_name: $artifact_name,
        agent_name: $agent_name,
        conclusion: $conclusion,
        run_url: $run_url,
        created: $created
      }' > "${zip_file%.zip}.json"

    echo "    -> $(basename "$zip_file")"
    total_fetched=$((total_fetched + 1))
  done

  echo
done

echo "Done: ${total_fetched} fetched, ${total_skipped} cached"
