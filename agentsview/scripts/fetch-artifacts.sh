#!/usr/bin/env bash
set -euo pipefail

# Phase 1: Download fullsend artifact ZIPs from GitHub Actions.
#
# Artifacts are cached in artifacts/<repo>/<run_id>_<artifact_name>.zip
# with .json metadata and .log workflow-job sidecars. Revision-pinned files
# used to assemble the agent context are cached once under
# artifacts/<repo>/revisions/<head_sha>/. Conversion into the AgentsView
# layout is handled separately by convert-artifacts.sh.
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
total_logs_fetched=0

cache_revision_file() {
  local repo="$1" ref="$2" relative_path="$3" revision_dir="$4"
  [ -n "$relative_path" ] || return 1
  case "$relative_path" in
    /*|*../*) return 1 ;;
  esac

  local destination="${revision_dir}/${relative_path}"
  [ -f "$destination" ] && return 0

  local encoded tmpfile
  if ! encoded=$(gh api -X GET "repos/${repo}/contents/${relative_path}" \
      -f ref="$ref" --jq '.content // empty' 2>/dev/null); then
    return 1
  fi
  [ -n "$encoded" ] || return 1

  mkdir -p "$(dirname "$destination")"
  tmpfile=$(mktemp)
  if ! printf '%s' "$encoded" | base64 -d > "$tmpfile" 2>/dev/null; then
    rm -f "$tmpfile"
    return 1
  fi
  mv "$tmpfile" "$destination"
}

first_cached_revision_path() {
  local repo="$1" ref="$2" revision_dir="$3"
  shift 3
  local candidate
  for candidate in "$@"; do
    [ -n "$candidate" ] || continue
    if cache_revision_file "$repo" "$ref" "$candidate" "$revision_dir"; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

log_context_path() {
  local log_file="$1" label="$2"
  sed -nE "s#.*${label}: .*/(\\.fullsend/[^[:space:]]+).*#\\1#p" "$log_file" | tail -1
}

for repo in "${REPOS[@]}"; do
  repo_name=$(basename "$repo")
  echo "--- $repo ---"

  repo_dir="${ARTIFACTS_DIR}/${repo_name}"
  mkdir -p "$repo_dir"

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
    meta_file="${zip_file%.zip}.json"
    log_file="${zip_file%.zip}.log"
    agent_name=${art_name#fullsend-}

    # A complete cache hit needs all three sidecars. Older caches only have the
    # ZIP and minimal JSON, so let them fall through for in-place enrichment.
    if [ -f "$zip_file" ] && [ -f "$log_file" ] && [ -f "$meta_file" ] && \
       [ -n "$(jq -r '.head_sha // empty' "$meta_file" 2>/dev/null)" ]; then
      total_skipped=$((total_skipped + 1))
      continue
    fi

    # Fetch immutable run provenance as well as display metadata.
    run_meta=$(gh api "repos/${repo}/actions/runs/${run_id}" \
      --jq '{conclusion:.conclusion, url:.html_url, head_sha:.head_sha, head_branch:.head_branch, event:.event}' 2>/dev/null) || continue
    conclusion=$(echo "$run_meta" | jq -r '.conclusion')
    run_url=$(echo "$run_meta" | jq -r '.url')
    head_sha=$(echo "$run_meta" | jq -r '.head_sha // empty')
    head_branch=$(echo "$run_meta" | jq -r '.head_branch // empty')
    event=$(echo "$run_meta" | jq -r '.event // empty')

    echo "  run $run_id | $art_name | $conclusion"

    if [ ! -f "$zip_file" ]; then
      # Download artifact ZIP via GitHub API.
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
      total_fetched=$((total_fetched + 1))
    fi

    # Select the job that actually ran this agent, then cache its complete log.
    job_id=""
    job_name=""
    if jobs=$(gh api "repos/${repo}/actions/runs/${run_id}/jobs?per_page=100" 2>/dev/null); then
      job=$(echo "$jobs" | jq -c --arg agent "$agent_name" '
        ([.jobs[] | select(any(.steps[]?; ((.name | ascii_downcase) == ("run " + ($agent | ascii_downcase) + " agent"))))] | first)
        // ([.jobs[] | select(.conclusion != "skipped" and (.steps | length) > 0)] | last)
        // {}')
      job_id=$(echo "$job" | jq -r '.id // empty')
      job_name=$(echo "$job" | jq -r '.name // empty')
    fi

    if [ ! -f "$log_file" ] && [ -n "$job_id" ]; then
      tmp_log=$(mktemp)
      if gh run view "$run_id" --repo "$repo" --job "$job_id" --log > "$tmp_log" 2>/dev/null && \
         [ -s "$tmp_log" ]; then
        mv "$tmp_log" "$log_file"
        total_logs_fetched=$((total_logs_fetched + 1))
      else
        rm -f "$tmp_log"
        echo "    [warn] could not download workflow job log"
      fi
    fi

    # Cache the exact repository instructions and local Fullsend configuration
    # from the commit that the workflow checked out. Revisions are shared by
    # many runs, so each file is downloaded only once per SHA.
    agent_path=""
    harness_path=""
    policy_path=""
    if [ -n "$head_sha" ]; then
      revision_dir="${repo_dir}/revisions/${head_sha}"
      mkdir -p "$revision_dir"
      cache_revision_file "$repo" "$head_sha" "CLAUDE.md" "$revision_dir" || true
      cache_revision_file "$repo" "$head_sha" "AGENTS.md" "$revision_dir" || true

      if [ -f "$log_file" ]; then
        agent_path=$(log_context_path "$log_file" "Agent")
        harness_path=$(log_context_path "$log_file" "Loading harness")
        policy_path=$(log_context_path "$log_file" "Policy")
      fi

      agent_path=$(first_cached_revision_path "$repo" "$head_sha" "$revision_dir" \
        "$agent_path" ".fullsend/rhdh/agents/${agent_name}.md" \
        ".fullsend/agents/${agent_name}.md" "agents/${agent_name}.md" || true)
      harness_path=$(first_cached_revision_path "$repo" "$head_sha" "$revision_dir" \
        "$harness_path" ".fullsend/rhdh/harness/${agent_name}.yaml" \
        ".fullsend/harness/${agent_name}.yaml" "harness/${agent_name}.yaml" || true)
      policy_path=$(first_cached_revision_path "$repo" "$head_sha" "$revision_dir" \
        "$policy_path" ".fullsend/rhdh/policies/${agent_name}.yaml" \
        ".fullsend/policies/${agent_name}.yaml" "policies/${agent_name}.yaml" || true)
    fi

    # Write metadata sidecar (everything the convert step needs).
    jq -nc \
      --arg run_id "$run_id" \
      --arg repo "$repo" \
      --arg artifact_name "$art_name" \
      --arg agent_name "$agent_name" \
      --arg conclusion "$conclusion" \
      --arg run_url "$run_url" \
      --arg created "$created" \
      --arg head_sha "$head_sha" \
      --arg head_branch "$head_branch" \
      --arg event "$event" \
      --arg job_id "$job_id" \
      --arg job_name "$job_name" \
      --arg log_file "$(basename "$log_file")" \
      --arg agent_path "$agent_path" \
      --arg harness_path "$harness_path" \
      --arg policy_path "$policy_path" \
      '{
        run_id: $run_id,
        repo: $repo,
        artifact_name: $artifact_name,
        agent_name: $agent_name,
        conclusion: $conclusion,
        run_url: $run_url,
        created: $created,
        head_sha: $head_sha,
        head_branch: $head_branch,
        event: $event,
        job_id: $job_id,
        job_name: $job_name,
        workflow_log: $log_file,
        context: {
          agent_path: $agent_path,
          harness_path: $harness_path,
          policy_path: $policy_path
        }
      }' > "$meta_file"

    echo "    -> $(basename "$zip_file")"
  done

  echo
done

echo "Done: ${total_fetched} artifact(s) fetched, ${total_logs_fetched} log(s) fetched, ${total_skipped} cached"
