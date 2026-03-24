#!/usr/bin/env bash
set -euo pipefail

CWD="${PWD:-.}"
MEMORY_DIR="$CWD/.repo-memory"

IS_ZH=false
echo "${LANG:-}${LC_ALL:-}${LANGUAGE:-}" | grep -qi "zh" && IS_ZH=true

# ─── Case 1: no .repo-memory directory ───
if [ ! -d "$MEMORY_DIR" ]; then
    IS_REPO=false
    for indicator in "package.json" "requirements.txt" "go.mod" "Cargo.toml" "pom.xml" "pyproject.toml" "src" "lib" "app"; do
        if [ -e "$CWD/$indicator" ]; then
            IS_REPO=true
            break
        fi
    done

    if [ "$IS_REPO" = true ]; then
        if [ "$IS_ZH" = true ]; then
            echo "🧠 [repo-memory] 未找到仓库记忆，建议执行 init 建档。" >&2
        else
            echo "🧠 [repo-memory] No memory found. Recommend running init." >&2
        fi
        cat <<'ENDJSON'
{
  "additionalContext": "[repo-memory] Detected a code repository but no .repo-memory/ exists. If the user's task involves understanding or modifying code, suggest initializing repo memory first (using repo-memory skill init mode). Briefly mention this in your response and let the user decide."
}
ENDJSON
    else
        if [ "$IS_ZH" = true ]; then
            echo "🧠 [repo-memory] 非代码仓库，跳过。" >&2
        else
            echo "🧠 [repo-memory] Not a code repo, skipping." >&2
        fi
    fi
    exit 0
fi

# ─── Case 2: .repo-memory exists but meta.json missing ───
if [ ! -f "$MEMORY_DIR/meta.json" ]; then
    if [ "$IS_ZH" = true ]; then
        echo "🧠 [repo-memory] 记忆目录存在但 meta.json 缺失，数据可能不完整。" >&2
    else
        echo "🧠 [repo-memory] Memory directory found but meta.json is missing." >&2
    fi
    cat <<'ENDJSON'
{
  "additionalContext": "[repo-memory] .repo-memory/ directory exists but meta.json is missing. Memory data may be incomplete. Suggest re-running init."
}
ENDJSON
    exit 0
fi

# ─── Case 3: memory exists, check staleness ───
LAST_COMMIT=$(grep -o '"last_commit": "[^"]*"' "$MEMORY_DIR/meta.json" | cut -d'"' -f4 2>/dev/null || echo "unknown")

if [ ! -d "$CWD/.git" ]; then
    if [ "$IS_ZH" = true ]; then
        echo "🧠 [repo-memory] 记忆已加载，未检测到 git，跳过版本检查。" >&2
    else
        echo "🧠 [repo-memory] Memory loaded. No git detected, skipping staleness check." >&2
    fi
    exit 0
fi

CURRENT_COMMIT=$(cd "$CWD" && git rev-parse HEAD 2>/dev/null || echo "unknown")

if [ "$LAST_COMMIT" = "$CURRENT_COMMIT" ]; then
    if [ "$IS_ZH" = true ]; then
        echo "🧠 [repo-memory] 记忆已是最新 (${CURRENT_COMMIT:0:8})" >&2
    else
        echo "🧠 [repo-memory] Memory is up to date. (${CURRENT_COMMIT:0:8})" >&2
    fi
    exit 0
fi

if ! cd "$CWD" && git cat-file -t "$LAST_COMMIT" >/dev/null 2>&1; then
    if [ "$IS_ZH" = true ]; then
        echo "🧠 [repo-memory] ⚠ 基准 commit 不在历史中（可能 rebase 了），建议重新建档。" >&2
    else
        echo "🧠 [repo-memory] ⚠ Base commit not found in history (rebase?). Recommend full rebuild." >&2
    fi
    cat <<ENDJSON
{
  "additionalContext": "[repo-memory] Memory base commit ($LAST_COMMIT) not found in current git history (possibly rebased/force pushed). Suggest re-running full init."
}
ENDJSON
    exit 0
fi

COMMIT_COUNT=$(cd "$CWD" && git rev-list --count "$LAST_COMMIT..$CURRENT_COMMIT" 2>/dev/null || echo "0")

if [ "$COMMIT_COUNT" = "0" ]; then
    if [ "$IS_ZH" = true ]; then
        echo "🧠 [repo-memory] 记忆已是最新。" >&2
    else
        echo "🧠 [repo-memory] Memory is up to date." >&2
    fi
    exit 0
fi

CHANGED_FILES=$(cd "$CWD" && git diff --name-only "$LAST_COMMIT" "$CURRENT_COMMIT" 2>/dev/null \
    | { grep -v -E "node_modules/|dist/|build/|\.next/|__pycache__/|vendor/|\.git/|openspec/" || true; } \
    | wc -l | tr -d ' ')

RECENT_COMMITS=$(cd "$CWD" && git log --oneline "$LAST_COMMIT..$CURRENT_COMMIT" 2>/dev/null | head -5)

if [ "$COMMIT_COUNT" -le 3 ]; then
    URGENCY="low"
    SUGGESTION="Memory slightly stale, update when working on changed areas"
    if [ "$IS_ZH" = true ]; then
        echo "🧠 [repo-memory] 记忆落后 ${COMMIT_COUNT} 个提交（${CHANGED_FILES} 个文件变更），紧急度：低" >&2
    else
        echo "🧠 [repo-memory] Memory is ${COMMIT_COUNT} commits behind (${CHANGED_FILES} files changed). Urgency: low." >&2
    fi
elif [ "$COMMIT_COUNT" -le 10 ]; then
    URGENCY="medium"
    SUGGESTION="Recommend updating soon to keep memory accurate"
    if [ "$IS_ZH" = true ]; then
        echo "🧠 [repo-memory] ⚠ 记忆落后 ${COMMIT_COUNT} 个提交（${CHANGED_FILES} 个文件变更），紧急度：中" >&2
    else
        echo "🧠 [repo-memory] ⚠ Memory is ${COMMIT_COUNT} commits behind (${CHANGED_FILES} files changed). Urgency: medium." >&2
    fi
else
    URGENCY="high"
    SUGGESTION="Memory severely stale, strongly recommend immediate incremental update"
    if [ "$IS_ZH" = true ]; then
        echo "🧠 [repo-memory] 🚨 记忆落后 ${COMMIT_COUNT} 个提交（${CHANGED_FILES} 个文件变更），紧急度：高！" >&2
    else
        echo "🧠 [repo-memory] 🚨 Memory is ${COMMIT_COUNT} commits behind (${CHANGED_FILES} files changed). Urgency: HIGH." >&2
    fi
fi

COMMITS_ESCAPED=$(echo "$RECENT_COMMITS" | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|/\\n/g')

cat <<ENDJSON
{
  "additionalContext": "[repo-memory] Memory needs updating.\\n- Behind: ${COMMIT_COUNT} commits (urgency: ${URGENCY})\\n- Changed files: ${CHANGED_FILES}\\n- Recent commits:\\n${COMMITS_ESCAPED}\\n- Suggestion: ${SUGGESTION}\\n\\nIf the user's current task involves code modification or understanding, run repo-memory skill update mode first. For HIGH urgency, proactively inform the user and run the update. For low/medium, briefly mention memory status and let the user decide."
}
ENDJSON
