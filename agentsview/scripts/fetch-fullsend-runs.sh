#!/usr/bin/env bash
set -euo pipefail

# Download fullsend agent run transcripts from GitHub Actions and
# organise them so AgentsView can ingest them as Claude sessions.
#
# Usage:
#   ./fetch-fullsend-runs.sh                          # default repos
#   ./fetch-fullsend-runs.sh org/repo1 org/repo2      # custom repos
#
# Prerequisites: gh (authenticated), jq
#
# Directory layout produced (matches AgentsView Claude discovery):
#   runs/<repo>_<agent>/<run-id>_issue-<N>_<transcript>.jsonl

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNS_DIR="${RUNS_DIR:-${SCRIPT_DIR}/../runs}"

if [ $# -gt 0 ]; then
  REPOS=("$@")
else
  REPOS=("redhat-developer/rhdh-agentic" "redhat-developer/rhdh-plugins")
fi

for cmd in gh jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "error: $cmd is required" >&2; exit 1; }
done

mkdir -p "$RUNS_DIR"

echo "Fetching fullsend runs -> $RUNS_DIR"
echo "Repos: ${REPOS[*]}"
echo

total_fetched=0
total_skipped=0

for repo in "${REPOS[@]}"; do
  repo_name=$(basename "$repo")
  echo "--- $repo ---"

  # Fetch all artifacts with automatic pagination
  artifacts=$(gh api --paginate "repos/${repo}/actions/artifacts?per_page=100" \
    --jq '[.artifacts[] | select(.name | startswith("fullsend-")) | select(.expired == false) | {id:.id, name:.name, run_id:.workflow_run.id, created:.created_at}]' 2>/dev/null \
    | jq -s 'add // []') || {
    echo "  [skip] could not list artifacts"
    continue
  }

  count=$(echo "$artifacts" | jq 'length')
  echo "  $count fullsend artifact(s)"

  for i in $(seq 0 $((count - 1))); do
    art_name=$(echo "$artifacts" | jq -r ".[$i].name")
    run_id=$(echo "$artifacts" | jq -r ".[$i].run_id")
    created=$(echo "$artifacts" | jq -r ".[$i].created")
    agent_name=${art_name#fullsend-}

    # Skip if we already have files for this run+agent
    project_dir="${repo_name}_${agent_name}"
    if compgen -G "${RUNS_DIR}/${project_dir}/${run_id}_*.jsonl" >/dev/null 2>&1; then
      total_skipped=$((total_skipped + 1))
      continue
    fi

    # Get run metadata (title, conclusion, URL)
    run_meta=$(gh api "repos/${repo}/actions/runs/${run_id}" \
      --jq '{title:.display_title, conclusion:.conclusion, url:.html_url}' 2>/dev/null) || continue
    title=$(echo "$run_meta" | jq -r '.title')
    conclusion=$(echo "$run_meta" | jq -r '.conclusion')
    run_url=$(echo "$run_meta" | jq -r '.url')

    echo "  run $run_id | $art_name | $conclusion"

    tmpdir=$(mktemp -d)

    if ! gh run download "$run_id" --repo "$repo" --dir "$tmpdir" --name "$art_name" 2>/dev/null; then
      rm -rf "$tmpdir"
      echo "    (download failed)"
      continue
    fi

    # Extract issue number from artifact directory name: agent-<type>-<issue>-<hash>
    issue_num=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d -name 'agent-*' \
      | head -1 | xargs basename 2>/dev/null \
      | grep -oE 'agent-[a-z]+-([0-9]+)' | grep -oE '[0-9]+$' || true)
    [ -z "$issue_num" ] && issue_num="unknown"

    dest_dir="${RUNS_DIR}/${project_dir}"

    found=false
    while IFS= read -r -d '' jsonl; do
      found=true
      mkdir -p "$dest_dir"

      dest_file="${dest_dir}/${run_id}_issue-${issue_num}_$(basename "$jsonl")"

      # Prepend a context message so the session shows repo/issue/agent in AgentsView
      meta_line=$(jq -nc \
        --arg repo "$repo" \
        --arg issue "$issue_num" \
        --arg agent "$agent_name" \
        --arg conclusion "$conclusion" \
        --arg url "$run_url" \
        --arg ts "$created" \
        --arg cwd "/fullsend/${project_dir}" \
        '{
          type: "user",
          timestamp: $ts,
          message: {
            content: ("[Fullsend: \($agent)] \($repo)#\($issue) (\($conclusion))\n\($url)")
          },
          cwd: $cwd
        }')

      { echo "$meta_line"; cat "$jsonl"; } > "$dest_file"
      echo "    -> ${project_dir}/$(basename "$dest_file")"
      total_fetched=$((total_fetched + 1))
    done < <(find "$tmpdir" -name '*.jsonl' -path '*/transcripts/*' -print0)

    if [ "$found" = "false" ]; then
      echo "    (no transcripts in artifact)"
    fi

    rm -rf "$tmpdir"
  done

  echo
done

echo "Done: ${total_fetched} fetched, ${total_skipped} skipped"
if [ "$total_fetched" -gt 0 ] || [ "$total_skipped" -gt 0 ]; then
  echo "Start viewer: make fullsend-up   (or: podman compose -f docker-compose.fullsend.yaml up -d)"
fi
