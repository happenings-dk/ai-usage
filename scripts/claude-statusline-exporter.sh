#!/usr/bin/env bash
set -u

input="$(cat)"
default_cache_file="${HOME}/.claude/ai-usage-rate-limits.json"
cache_file="${AI_USAGE_CLAUDE_RATE_LIMIT_CACHE:-$default_cache_file}"
cache_dir="$(dirname "$cache_file")"

if command -v jq >/dev/null 2>&1; then
  if printf '%s' "$input" | jq -e '.rate_limits? | objects' >/dev/null 2>&1; then
    mkdir -p "$cache_dir"
    tmp_file="${cache_file}.$$"
    if { printf '%s' "$input" | jq -c '{updated_at: (now | todateiso8601), source: "claude-statusline", rate_limits: .rate_limits}' > "$tmp_file"; } 2>/dev/null; then
      mv "$tmp_file" "$cache_file"
    else
      rm -f "$tmp_file"
    fi
  fi
fi

jq_value() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null
  fi
}

current_dir="$(jq_value '.workspace.current_dir')"
model="$(jq_value '.model.id')"
ctx="$(jq_value '.context_window.used_percentage')"
branch="$(jq_value '.git.branch_name')"
dirty="$(jq_value '.git.dirty_files')"
in_tok="$(jq_value '(.session.cost.input_tokens // .session.input_tokens // .context_window.total_input_tokens)')"
out_tok="$(jq_value '(.session.cost.output_tokens // .session.output_tokens // .context_window.total_output_tokens)')"
msgs="$(jq_value '.session.message_count')"

dirty="${dirty:-0}"
in_tok="${in_tok:-0}"
out_tok="${out_tok:-0}"
msgs="${msgs:-0}"
model="${model:-claude}"

dir_display="${current_dir/#$HOME/~}"
if [ -z "$dir_display" ]; then
  dir_display="~"
fi

fmt_tok() {
  n="$1"
  sym="$2"
  if [ "$n" -ge 1000000 ] 2>/dev/null; then
    awk -v n="$n" -v s="$sym" 'BEGIN{printf "%.1fM%s", n/1000000, s}'
  elif [ "$n" -ge 1000 ] 2>/dev/null; then
    awk -v n="$n" -v s="$sym" 'BEGIN{printf "%.1fk%s", n/1000, s}'
  else
    printf '%s%s' "$n" "$sym"
  fi
}

out="$(printf '%s@%s %s' "$(whoami)" "$(hostname -s)" "$dir_display")"
if [ -n "$branch" ]; then
  git_part="$branch"
  if [ "$dirty" -gt 0 ] 2>/dev/null; then
    git_part="$git_part +$dirty"
  fi
  out="$out | $git_part"
fi

out="$out | $model"
if [ -n "$ctx" ]; then
  out="$(printf '%s | ctx: %.0f%%' "$out" "$ctx")"
fi
if [ "$msgs" -gt 0 ] 2>/dev/null; then
  out="$out | msgs: $msgs"
fi
if [ "$in_tok" -gt 0 ] 2>/dev/null; then
  tok_str="$(fmt_tok "$in_tok" " in") $(fmt_tok "$out_tok" " out")"
  out="$out | $tok_str"
fi

echo "$out"
