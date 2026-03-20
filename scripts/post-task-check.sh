#!/usr/bin/env bash
# repo-memory post-task-check: 在 Claude Code 回复结束时检查是否有未同步的代码变更
# 被 Stop hook 调用
#
# 如果本次对话中产生了代码变更但记忆未更新，提醒 Claude 同步记忆

set -euo pipefail

CWD=$(jq -r '.cwd // "."' 2>/dev/null || echo ".")
MEMORY_DIR="$CWD/.repo-memory"

# 没有记忆系统，静默退出
if [ ! -d "$MEMORY_DIR" ] || [ ! -f "$MEMORY_DIR/meta.json" ]; then
    exit 0
fi

# 没有 git，无法检查
if [ ! -d "$CWD/.git" ]; then
    exit 0
fi

EXCLUDE="node_modules/|dist/|build/|\.next/|__pycache__/|vendor/|\.repo-memory/|openspec/"

# 检查工作区是否有未提交的变更（说明本次对话可能修改了代码）
UNSTAGED=$(cd "$CWD" && git diff --name-only 2>/dev/null \
    | grep -v -E "$EXCLUDE" \
    | wc -l | tr -d ' ')

STAGED=$(cd "$CWD" && git diff --cached --name-only 2>/dev/null \
    | grep -v -E "$EXCLUDE" \
    | wc -l | tr -d ' ')

TOTAL_CHANGES=$((UNSTAGED + STAGED))

if [ "$TOTAL_CHANGES" -gt 0 ]; then
    # 获取变更的文件列表
    CHANGED=$(cd "$CWD" && { git diff --name-only 2>/dev/null; git diff --cached --name-only 2>/dev/null; } \
        | grep -v -E "$EXCLUDE" \
        | sort -u | head -10)
    
    FILES_ESCAPED=$(echo "$CHANGED" | tr '\n' '|' | sed 's/|/\\n  - /g' | sed 's/\\n  - $//')

    cat <<ENDJSON
{
  "additionalContext": "[repo-memory] 检测到本次对话产生了 ${TOTAL_CHANGES} 个文件变更，请确保已同步更新对应的记忆文档（L2/L3/LF 等）。\\n变更文件:\\n  - ${FILES_ESCAPED}"
}
ENDJSON
fi
