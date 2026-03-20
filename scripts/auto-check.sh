#!/usr/bin/env bash
# repo-memory auto-check: SessionStart 时自动检查记忆是否需要更新
# 被 Claude Code Hook 调用，通过 additionalContext 注入检查结果给 Claude
#
# 输出 JSON 格式，通过 stdout 返回给 Claude Code：
# - 如果记忆不存在 → 提示需要初始化
# - 如果记忆过旧 → 提示需要增量更新，并附带变更摘要
# - 如果记忆是最新的 → 静默，不打扰用户

set -euo pipefail

# 获取当前工作目录（Claude Code 会传入 cwd）
CWD=$(jq -r '.cwd // "."' 2>/dev/null || echo ".")
MEMORY_DIR="$CWD/.repo-memory"

# ─── 情况1：没有 .repo-memory 目录 ───
if [ ! -d "$MEMORY_DIR" ]; then
    # 检查是否是一个代码仓库（有 src/ 或常见项目文件）
    IS_REPO=false
    for indicator in "package.json" "requirements.txt" "go.mod" "Cargo.toml" "pom.xml" "pyproject.toml" "src" "lib" "app"; do
        if [ -e "$CWD/$indicator" ]; then
            IS_REPO=true
            break
        fi
    done

    if [ "$IS_REPO" = true ]; then
        cat <<'ENDJSON'
{
  "additionalContext": "[repo-memory] 检测到这是一个代码仓库，但尚未建立仓库记忆（.repo-memory/ 不存在）。如果用户的任务涉及理解或修改代码，建议先执行仓库记忆初始化（使用 repo-memory skill 的 init 模式）。可以在回复中简要提及这一点，让用户决定是否建档。"
}
ENDJSON
    fi
    # 如果不是代码仓库，静默退出
    exit 0
fi

# ─── 情况2：有 .repo-memory 但没有 meta.json ───
if [ ! -f "$MEMORY_DIR/meta.json" ]; then
    cat <<'ENDJSON'
{
  "additionalContext": "[repo-memory] .repo-memory/ 目录存在但 meta.json 缺失，记忆数据可能不完整。建议重新执行 init 建档。"
}
ENDJSON
    exit 0
fi

# ─── 情况3：有完整记忆，检查是否过旧 ───
LAST_COMMIT=$(grep -o '"last_commit": "[^"]*"' "$MEMORY_DIR/meta.json" | cut -d'"' -f4 2>/dev/null || echo "unknown")

# 如果没有 git，无法检查，静默退出
if [ ! -d "$CWD/.git" ]; then
    exit 0
fi

CURRENT_COMMIT=$(cd "$CWD" && git rev-parse HEAD 2>/dev/null || echo "unknown")

# 如果 commit 相同，记忆是最新的，静默退出
if [ "$LAST_COMMIT" = "$CURRENT_COMMIT" ]; then
    exit 0
fi

# 如果上次 commit 不在历史中（比如 rebase 了），标记为需要检查
if ! cd "$CWD" && git cat-file -t "$LAST_COMMIT" >/dev/null 2>&1; then
    cat <<ENDJSON
{
  "additionalContext": "[repo-memory] 仓库记忆的基准 commit ($LAST_COMMIT) 在当前 git 历史中不存在（可能经历了 rebase/force push）。建议重新执行全量建档。"
}
ENDJSON
    exit 0
fi

# 计算 commit 差距
COMMIT_COUNT=$(cd "$CWD" && git rev-list --count "$LAST_COMMIT..$CURRENT_COMMIT" 2>/dev/null || echo "0")

if [ "$COMMIT_COUNT" = "0" ]; then
    exit 0
fi

# 获取变更文件数量（排除生成代码目录）
CHANGED_FILES=$(cd "$CWD" && git diff --name-only "$LAST_COMMIT" "$CURRENT_COMMIT" 2>/dev/null \
    | grep -v -E "node_modules/|dist/|build/|\.next/|__pycache__/|vendor/|\.git/|openspec/" \
    | wc -l | tr -d ' ')

# 获取最近几条 commit message
RECENT_COMMITS=$(cd "$CWD" && git log --oneline "$LAST_COMMIT..$CURRENT_COMMIT" 2>/dev/null | head -5)

# 根据差距决定策略
if [ "$COMMIT_COUNT" -le 3 ]; then
    URGENCY="低"
    SUGGESTION="记忆略有滞后，建议在涉及变更区域时顺便更新"
elif [ "$COMMIT_COUNT" -le 10 ]; then
    URGENCY="中"
    SUGGESTION="建议尽快执行增量更新以保持记忆准确性"
else
    URGENCY="高"
    SUGGESTION="记忆严重滞后，强烈建议立即执行增量更新"
fi

# 输出结构化上下文（转义换行符用于 JSON）
COMMITS_ESCAPED=$(echo "$RECENT_COMMITS" | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|/\\n/g')

cat <<ENDJSON
{
  "additionalContext": "[repo-memory] 仓库记忆需要更新。\\n- 滞后: ${COMMIT_COUNT} 个提交（紧急度: ${URGENCY}）\\n- 变更文件: ${CHANGED_FILES} 个\\n- 最近提交:\\n${COMMITS_ESCAPED}\\n- 建议: ${SUGGESTION}\\n\\n如果用户当前任务涉及代码修改或理解，请先使用 repo-memory skill 的 update 模式执行增量更新，然后再处理用户的任务。对于紧急度为「高」的情况，应主动告知用户并执行更新；紧急度为「低」或「中」时，可在回复中简要提及记忆状态，让用户决定。"
}
ENDJSON
