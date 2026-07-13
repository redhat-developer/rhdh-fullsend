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
SCAFFOLD_DIR="${FULLSEND_SCAFFOLD_DIR:-}"

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

# --- System prompt reconstruction --------------------------------------
if [ -z "$SCAFFOLD_DIR" ]; then
  echo "[info] FULLSEND_SCAFFOLD_DIR not set — skipping prompt reconstruction"
fi

build_prompt_line() {
  local agent_name="$1" ts="$2" repo_claude_md="$3" repo_agents_md="$4"

  if [ -z "$SCAFFOLD_DIR" ]; then
    return 0
  fi

  local sections=()

  # 1. Agent definition
  local agent_file="${SCAFFOLD_DIR}/agents/${agent_name}.md"
  if [ -f "$agent_file" ]; then
    sections+=("## Agent Definition\n\n$(cat "$agent_file")")
  fi

  # 2. Project instructions (CLAUDE.md + AGENTS.md)
  local project_section=""
  if [ -n "$repo_claude_md" ]; then
    project_section="### CLAUDE.md\n\n${repo_claude_md}"
  fi

  local agents_md_content="$repo_agents_md"
  if [ -z "$agents_md_content" ] && [ -f "${SCAFFOLD_DIR}/AGENTS.md" ]; then
    agents_md_content="$(cat "${SCAFFOLD_DIR}/AGENTS.md")"
  fi
  if [ -n "$agents_md_content" ]; then
    [ -n "$project_section" ] && project_section="${project_section}\n\n"
    project_section="${project_section}### AGENTS.md\n\n${agents_md_content}"
  fi

  if [ -z "$repo_claude_md" ] && [ -n "$agents_md_content" ]; then
    local bridge="Project rules and instructions live in [AGENTS.md](AGENTS.md). Read that file now — it is the single source of truth for all agent-facing guidance in this repo."
    project_section="### CLAUDE.md (bridge)\n\n${bridge}\n\n${project_section}"
  fi

  if [ -n "$project_section" ]; then
    sections+=("## Project Instructions\n\n${project_section}")
  fi

  # 3. Skills from harness YAML
  local harness_file="${SCAFFOLD_DIR}/harness/${agent_name}.yaml"
  if [ -f "$harness_file" ]; then
    local skills_section=""
    while IFS= read -r skill_path; do
      local skill_name
      skill_name=$(basename "$skill_path")
      local skill_file="${SCAFFOLD_DIR}/${skill_path}/SKILL.md"
      if [ -f "$skill_file" ]; then
        [ -n "$skills_section" ] && skills_section="${skills_section}\n\n---\n\n"
        skills_section="${skills_section}### ${skill_name}\n\n$(cat "$skill_file")"
      fi
    done < <(grep -E '^\s*- skills/' "$harness_file" | sed 's/^[[:space:]]*- //')

    if [ -n "$skills_section" ]; then
      sections+=("## Skills\n\n${skills_section}")
    fi
  fi

  if [ ${#sections[@]} -eq 0 ]; then
    return 0
  fi

  local body
  body=$(printf '%s' "${sections[0]}")
  local idx
  for ((idx=1; idx < ${#sections[@]}; idx++)); do
    body=$(printf '%s\n\n---\n\n%s' "$body" "${sections[$idx]}")
  done

  local prompt_content
  prompt_content=$(printf '📋 System Prompt (reconstructed)\n\n%b' "$body")

  local tmpfile
  tmpfile=$(mktemp)
  printf '%s' "$prompt_content" > "$tmpfile"

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

  # Read cached repo CLAUDE.md / AGENTS.md
  repo_claude_md=""
  repo_agents_md=""
  [ -f "${repo_dir}/CLAUDE.md" ] && repo_claude_md=$(cat "${repo_dir}/CLAUDE.md")
  [ -f "${repo_dir}/AGENTS.md" ] && repo_agents_md=$(cat "${repo_dir}/AGENTS.md")

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

    # Skip if already converted
    if [ -f "$session_file" ]; then
      total_skipped=$((total_skipped + 1))
      rm -rf "$tmpdir"
      continue
    fi

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

    prompt_line=$(build_prompt_line "$agent_name" "$created" "$repo_claude_md" "$repo_agents_md" || true)

    # --- Write main session ---
    {
      echo "$agent_setting_line"
      echo "$meta_line"
      [ -n "$prompt_line" ] && echo "$prompt_line"
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
