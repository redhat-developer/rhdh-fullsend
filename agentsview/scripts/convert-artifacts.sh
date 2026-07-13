#!/usr/bin/env bash
set -euo pipefail

# Phase 2: Convert cached artifact ZIPs into AgentsView-compatible layout.
#
# Reads ZIPs + metadata sidecars from artifacts/<repo>/ (produced by
# fetch-artifacts.sh) and writes the nested directory structure that
# AgentsView expects for Claude session discovery:
#
#   runs/<repo>/<session-id>.jsonl
#   runs/<repo>/<session-id>/subagents/agent-<id>.jsonl
#
# Usage:
#   ./convert-artifacts.sh                          # convert new artifacts
#   ./convert-artifacts.sh --force                  # re-convert everything
#   ./convert-artifacts.sh --repo rhdh-agentic      # one repo only
#
# Prerequisites: jq, unzip

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${SCRIPT_DIR}/../artifacts}"
RUNS_DIR="${RUNS_DIR:-${SCRIPT_DIR}/../runs}"

# --- Parse flags --------------------------------------------------------
FORCE=false
REPO_FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=true; shift ;;
    --repo)  REPO_FILTER="$2"; shift 2 ;;
    *)       echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

for cmd in jq unzip; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "error: $cmd is required" >&2; exit 1; }
done

if [ "$FORCE" = true ]; then
  echo "Force mode: clearing $RUNS_DIR"
  rm -rf "$RUNS_DIR"
fi
mkdir -p "$RUNS_DIR"

# --- Fullsend execution-context reconstruction -------------------------
# Backticks below are literal Markdown in printf format strings.
# shellcheck disable=SC2016,SC2129
build_execution_context_line() {
  local agent_name="$1" ts="$2" meta_file="$3" agent_dir="$4" repo_dir="$5"
  local head_sha revision_dir workflow_log log_file output_jsonl init_json
  local agent_path harness_path policy_path agent_file harness_file policy_file
  local claude_file agents_file tmpfile

  head_sha=$(jq -r '.head_sha // empty' "$meta_file")
  revision_dir="${repo_dir}/revisions/${head_sha}"
  workflow_log=$(jq -r '.workflow_log // empty' "$meta_file")
  log_file=""
  if [ -n "$workflow_log" ] && [ "$(basename "$workflow_log")" = "$workflow_log" ] && \
     [ -f "${repo_dir}/${workflow_log}" ]; then
    log_file="${repo_dir}/${workflow_log}"
  fi

  agent_path=$(jq -r '.context.agent_path // empty' "$meta_file")
  harness_path=$(jq -r '.context.harness_path // empty' "$meta_file")
  policy_path=$(jq -r '.context.policy_path // empty' "$meta_file")
  agent_file="${revision_dir}/${agent_path}"
  harness_file="${revision_dir}/${harness_path}"
  policy_file="${revision_dir}/${policy_path}"
  claude_file="${revision_dir}/CLAUDE.md"
  agents_file="${revision_dir}/AGENTS.md"

  output_jsonl=$(find "$agent_dir" -type f -path '*/iteration-*/output.jsonl' | sort | head -1)
  init_json='{}'
  if [ -n "$output_jsonl" ] && [ -f "$output_jsonl" ]; then
    init_json=$(jq -sc '[.[] | select(.type == "system" and .subtype == "init")][0] // {}' \
      "$output_jsonl" 2>/dev/null || printf '{}')
  fi

  tmpfile=$(mktemp)
  printf '📋 Fullsend Execution Context\n\n' > "$tmpfile"
  printf "> Built from the workflow provenance and Claude runtime metadata available in this cached run. This is not Claude's proprietary built-in system prompt.\n\n" >> "$tmpfile"

  printf '## Provenance\n\n' >> "$tmpfile"
  printf -- '- Agent: `%s`\n' "$agent_name" >> "$tmpfile"
  [ -n "$head_sha" ] && printf -- '- Target revision: `%s`\n' "$head_sha" >> "$tmpfile"
  local job_name
  job_name=$(jq -r '.job_name // empty' "$meta_file")
  [ -n "$job_name" ] && printf -- '- Workflow job: `%s`\n' "$job_name" >> "$tmpfile"
  if [ -n "$log_file" ]; then
    local fullsend_version image resolved_urls
    fullsend_version=$(sed -nE 's/.*fullsend ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' "$log_file" | tail -1)
    image=$(sed -nE 's#.*Image: ([^[:space:]]+).*#\1#p' "$log_file" | tail -1)
    [ -n "$fullsend_version" ] && printf -- '- Fullsend: `%s`\n' "$fullsend_version" >> "$tmpfile"
    [ -n "$image" ] && printf -- '- Sandbox image: `%s`\n' "$image" >> "$tmpfile"
    resolved_urls=$(sed -nE 's#.*Base: (https://[^[:space:]]+).*#\1#p' "$log_file" | sort -u)
    if [ -n "$resolved_urls" ]; then
      printf '\n### Resolved remote resources\n\n' >> "$tmpfile"
      while IFS= read -r resource_url; do
        [ -n "$resource_url" ] && printf -- '- <%s>\n' "$resource_url" >> "$tmpfile"
      done <<< "$resolved_urls"
    fi
  fi

  if [ "$init_json" != '{}' ]; then
    local model claude_version permission_mode cwd tools agents skills plugins
    model=$(echo "$init_json" | jq -r '.model // empty')
    claude_version=$(echo "$init_json" | jq -r '.claude_code_version // empty')
    permission_mode=$(echo "$init_json" | jq -r '.permissionMode // empty')
    cwd=$(echo "$init_json" | jq -r '.cwd // empty')
    tools=$(echo "$init_json" | jq -r '(.tools // []) | join(", ")')
    agents=$(echo "$init_json" | jq -r '(.agents // []) | join(", ")')
    skills=$(echo "$init_json" | jq -r '(.skills // []) | join(", ")')
    plugins=$(echo "$init_json" | jq -r '(.plugins // []) | map(.name) | join(", ")')

    printf '\n## Claude Runtime\n\n' >> "$tmpfile"
    [ -n "$model" ] && printf -- '- Model: `%s`\n' "$model" >> "$tmpfile"
    [ -n "$claude_version" ] && printf -- '- Claude Code: `%s`\n' "$claude_version" >> "$tmpfile"
    [ -n "$permission_mode" ] && printf -- '- Permission mode: `%s`\n' "$permission_mode" >> "$tmpfile"
    [ -n "$cwd" ] && printf -- '- Working directory: `%s`\n' "$cwd" >> "$tmpfile"
    [ -n "$tools" ] && printf -- '- Tools: %s\n' "$tools" >> "$tmpfile"
    [ -n "$agents" ] && printf -- '- Agents: %s\n' "$agents" >> "$tmpfile"
    [ -n "$skills" ] && printf -- '- Available skills: %s\n' "$skills" >> "$tmpfile"
    [ -n "$plugins" ] && printf -- '- Plugins: %s\n' "$plugins" >> "$tmpfile"
    [ -n "$skills" ] && printf '\nFull skill instructions appear later in the transcript when a skill is actually loaded.\n' >> "$tmpfile"
  fi

  if [ -n "$agent_path" ] && [ -f "$agent_file" ]; then
    printf '\n---\n\n## Agent Definition\n\n_Source: `%s` at `%s`_\n\n' "$agent_path" "$head_sha" >> "$tmpfile"
    printf '%s\n' "$(cat "$agent_file")" >> "$tmpfile"
  fi

  if [ -f "$claude_file" ] || [ -f "$agents_file" ]; then
    printf '\n---\n\n## Project Instructions\n' >> "$tmpfile"
    if [ -f "$claude_file" ]; then
      printf '\n### CLAUDE.md\n\n%s\n' "$(cat "$claude_file")" >> "$tmpfile"
    fi
    if [ -f "$agents_file" ]; then
      printf '\n### AGENTS.md\n\n%s\n' "$(cat "$agents_file")" >> "$tmpfile"
    fi
  fi

  if [ -n "$harness_path" ] && [ -f "$harness_file" ]; then
    printf '\n---\n\n## Harness\n\n_Source: `%s` at `%s`_\n\n```yaml\n%s\n```\n' \
      "$harness_path" "$head_sha" "$(cat "$harness_file")" >> "$tmpfile"
  fi
  if [ -n "$policy_path" ] && [ -f "$policy_file" ]; then
    printf '\n## Policy\n\n_Source: `%s` at `%s`_\n\n```yaml\n%s\n```\n' \
      "$policy_path" "$head_sha" "$(cat "$policy_file")" >> "$tmpfile"
  fi

  jq -nc --rawfile content "$tmpfile" \
    --arg ts "$ts" \
    '{type: "user", timestamp: $ts, message: {content: $content}}'
  rm -f "$tmpfile"
}

# --- Main conversion loop ----------------------------------------------
echo "Converting artifacts -> $RUNS_DIR"
echo

total_converted=0
total_skipped=0

for repo_dir in "$ARTIFACTS_DIR"/*/; do
  [ -d "$repo_dir" ] || continue
  repo_name=$(basename "$repo_dir")
  [ -n "$REPO_FILTER" ] && [ "$repo_name" != "$REPO_FILTER" ] && continue

  echo "--- $repo_name ---"
  dest_dir="${RUNS_DIR}/${repo_name}"
  mkdir -p "$dest_dir"

  for zip_file in "$repo_dir"/*.zip; do
    [ -f "$zip_file" ] || continue

    base=$(basename "$zip_file" .zip)
    meta_file="${repo_dir}/${base}.json"

    if [ ! -f "$meta_file" ]; then
      echo "  [skip] no metadata sidecar: $base"
      continue
    fi

    # Read sidecar metadata
    run_id=$(jq -r '.run_id' "$meta_file")
    agent_name=$(jq -r '.agent_name' "$meta_file")
    conclusion=$(jq -r '.conclusion' "$meta_file")
    run_url=$(jq -r '.run_url' "$meta_file")
    created=$(jq -r '.created' "$meta_file")

    # Extract ZIP to temp dir
    tmpdir=$(mktemp -d)
    if ! unzip -qo "$zip_file" -d "$tmpdir" 2>/dev/null; then
      rm -rf "$tmpdir"
      echo "  [skip] extraction failed: $base"
      continue
    fi

    # Find agent run directory (agent-<type>-<id>-<hash>/)
    agent_dir=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d -name 'agent-*' | head -1)
    if [ -z "$agent_dir" ]; then
      rm -rf "$tmpdir"
      echo "  [skip] no agent directory: $base"
      continue
    fi

    # Classify transcripts: main session vs subagents
    main_jsonl=""
    subagent_jsonls=()
    while IFS= read -r -d '' jsonl; do
      fname=$(basename "$jsonl")
      case "$fname" in
        *-agent-a*) subagent_jsonls+=("$jsonl") ;;
        *)          main_jsonl="$jsonl" ;;
      esac
    done < <(find "$tmpdir" -name '*.jsonl' -path '*/transcripts/*' -print0)

    if [ -z "$main_jsonl" ]; then
      rm -rf "$tmpdir"
      echo "  [skip] no main transcript: $base"
      continue
    fi

    # Session ID = main transcript filename without .jsonl
    session_id=$(basename "$main_jsonl" .jsonl)
    session_file="${dest_dir}/${session_id}.jsonl"

    # Keep complete sessions idempotent, but automatically upgrade sessions
    # created by the old prompt-less/scaffold-based converter.
    if [ -f "$session_file" ] && grep -Fq '📋 Fullsend Execution Context' "$session_file"; then
      total_skipped=$((total_skipped + 1))
      rm -rf "$tmpdir"
      continue
    fi
    [ -f "$session_file" ] && echo "  [refresh] execution context: $base"

    echo "  $run_id | $agent_name | $conclusion"

    # Extract run metrics from run-summary.json
    summary_file="${agent_dir}/run-summary.json"
    issue_num="unknown"
    entity_type="issue"
    cost_usd="" duration_s="" num_turns=""

    case "$agent_name" in
      review|fix) entity_type="pr" ;;
    esac

    if [ -f "$summary_file" ]; then
      work_item_url=$(jq -r '."fullsend.work_item_id" // empty' "$summary_file")
      if [ -n "$work_item_url" ]; then
        issue_num=$(echo "$work_item_url" | grep -oE '[0-9]+$' || true)
        case "$work_item_url" in
          */pull/*) entity_type="pr" ;;
          *)        entity_type="issue" ;;
        esac
      fi
      cost_usd=$(jq -r '.metrics.total_cost_usd // empty' "$summary_file")
      duration_s=$(jq -r '(.duration_ms // 0) / 1000 | floor' "$summary_file")
      num_turns=$(jq -r '.metrics.num_turns // empty' "$summary_file")
    fi
    [ -z "$issue_num" ] && issue_num="unknown"

    # Extract agent result (triage summary, review comment, etc.)
    result_file=$(find "$agent_dir" -name 'agent-result.json' -type f | head -1)
    result_comment=""
    if [ -n "$result_file" ] && [ -f "$result_file" ]; then
      result_comment=$(jq -r '.comment // empty' "$result_file")
    fi

    # --- Build injected header lines ---
    agent_setting_line=$(jq -nc \
      --arg agent "$agent_name" \
      --arg ts "$created" \
      '{type: "agent-setting", agentSetting: ("fs-" + $agent), timestamp: $ts}')

    title_extra=""
    [ -n "${cost_usd:-}" ] && title_extra=" · \$${cost_usd}"
    [ -n "${duration_s:-}" ] && title_extra="${title_extra} · ${duration_s}s"
    [ -n "${num_turns:-}" ] && title_extra="${title_extra} · ${num_turns} turns"

    meta_line=$(jq -nc \
      --arg entity "$entity_type" \
      --arg issue "$issue_num" \
      --arg run_id "$run_id" \
      --arg agent "$agent_name" \
      --arg conclusion "$conclusion" \
      --arg extra "$title_extra" \
      --arg url "$run_url" \
      --arg ts "$created" \
      --arg cwd "/fullsend/${repo_name}" \
      '{
        type: "user",
        timestamp: $ts,
        message: {
          content: ("\($agent) \($entity) #\($issue) - run \($run_id) [\($conclusion)\($extra)]\n\($url)")
        },
        cwd: $cwd
      }')

    result_line=""
    if [ -n "$result_comment" ]; then
      result_line=$(jq -nc \
        --arg comment "$result_comment" \
        --arg ts "$created" \
        '{
          type: "assistant",
          message: {
            role: "assistant",
            type: "message",
            content: [{ type: "text", text: $comment }],
            stop_reason: "end_turn"
          },
          timestamp: $ts
        }')
    fi

    context_line=$(build_execution_context_line "$agent_name" "$created" "$meta_file" "$agent_dir" "$repo_dir" || true)

    # --- Write main session ---
    {
      echo "$agent_setting_line"
      echo "$meta_line"
      [ -n "$context_line" ] && echo "$context_line"
      cat "$main_jsonl"
      [ -n "$result_line" ] && echo "$result_line"
    } > "$session_file"
    echo "    -> ${repo_name}/${session_id}.jsonl"

    # --- Write subagent transcripts (nested under session dir) ---
    if [ ${#subagent_jsonls[@]} -gt 0 ]; then
      subagent_dir="${dest_dir}/${session_id}/subagents"
      mkdir -p "$subagent_dir"
      for sa_jsonl in "${subagent_jsonls[@]}"; do
        sa_fname=$(basename "$sa_jsonl")
        # Strip prefix to match AgentsView expectation: agent-a<hex>.jsonl
        # e.g. code-agent-a5fcbf19e4906f43b.jsonl → agent-a5fcbf19e4906f43b.jsonl
        sa_clean="agent-${sa_fname#*-agent-}"
        cp "$sa_jsonl" "${subagent_dir}/${sa_clean}"
        echo "    -> ${repo_name}/${session_id}/subagents/${sa_clean}"
      done
    fi

    total_converted=$((total_converted + 1))
    rm -rf "$tmpdir"
  done

  echo
done

echo "Done: ${total_converted} converted, ${total_skipped} skipped (existing)"
if [ "$total_converted" -gt 0 ]; then
  echo "Start viewer: make viewer   (or: podman compose -f docker-compose.fullsend.yaml up -d)"
fi
