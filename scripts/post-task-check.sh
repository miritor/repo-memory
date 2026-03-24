#!/usr/bin/env bash
# repo-memory post-task-check: Stop hook — check if code changes need memory sync
# stdout → JSON for Claude | stderr → visible to user in terminal

set -euo pipefail

CWD="${PWD:-.}"
MEMORY_DIR="$CWD/.repo-memory"

# ─── Language detection ───
is_zh() {
    echo "${LANG:-}${LC_ALL:-}${LANGUAGE:-}" | grep -qi "zh"
}

# No memory system, silent exit
if [ ! -d "$MEMORY_DIR" ] || [ ! -f "$MEMORY_DIR/meta.json" ]; then
    exit 0
fi

# No git, can't check
if [ ! -d "$CWD/.git" ]; then
    exit 0
fi

EXCLUDE="node_modules/|dist/|build/|\.next/|__pycache__/|vendor/|\.repo-memory/|openspec/"

UNSTAGED=$(cd "$CWD" && git diff --name-only 2>/dev/null \
    | grep -v -E "$EXCLUDE" \
    | wc -l | tr -d ' ')

STAGED=$(cd "$CWD" && git diff --cached --name-only 2>/dev/null \
    | grep -v -E "$EXCLUDE" \
    | wc -l | tr -d ' ')

TOTAL_CHANGES=$((UNSTAGED + STAGED))

if [ "$TOTAL_CHANGES" -gt 0 ]; then
    CHANGED=$(cd "$CWD" && { git diff --name-only 2>/dev/null; git diff --cached --name-only 2>/dev/null; } \
        | grep -v -E "$EXCLUDE" \
        | sort -u | head -10)

    FILES_ESCAPED=$(echo "$CHANGED" | tr '\n' '|' | sed 's/|/\\n  - /g' | sed 's/\\n  - $//')

    if is_zh; then
        echo "🧠 [repo-memory] 检测到 ${TOTAL_CHANGES} 个文件变更，记忆文档可能需要同步。" >&2
    else
        echo "🧠 [repo-memory] ${TOTAL_CHANGES} file(s) changed — memory docs may need syncing." >&2
    fi

    cat <<ENDJSON
{
  "additionalContext": "[repo-memory] Detected ${TOTAL_CHANGES} file change(s) in this session. Please ensure the corresponding memory docs (L2/L3/LF etc.) have been updated.\\nChanged files:\\n  - ${FILES_ESCAPED}"
}
ENDJSON
else
    if is_zh; then
        echo "🧠 [repo-memory] 未检测到代码变更，记忆已同步。" >&2
    else
        echo "🧠 [repo-memory] No code changes detected. Memory is in sync." >&2
    fi
fi
