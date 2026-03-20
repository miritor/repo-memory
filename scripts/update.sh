#!/usr/bin/env bash
# repo-memory update: 增量更新辅助脚本
# 用法: bash update.sh <repo_path>
#
# 此脚本负责：
# 1. 检测上次建档 commit 与当前 HEAD 之间的差异
# 2. 分类变更文件（修改/新增/删除/重命名）
# 3. 通过哈希比对确认实际变化
# 4. 确定受影响的记忆层级
# 5. 输出变更清单供 Claude 定向更新

set -euo pipefail

REPO_PATH="${1:-.}"
MEMORY_DIR="$REPO_PATH/.repo-memory"

# ─── 颜色输出 ───
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN}  Repo Memory — 增量更新${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"

# ─── 0. 前置检查 ───
if [ ! -d "$MEMORY_DIR" ]; then
    echo -e "${RED}  ✗ 未找到 .repo-memory 目录，请先执行 init${NC}"
    exit 1
fi

if [ ! -f "$MEMORY_DIR/meta.json" ]; then
    echo -e "${RED}  ✗ 未找到 meta.json，记忆数据不完整${NC}"
    exit 1
fi

if [ ! -d "$REPO_PATH/.git" ]; then
    echo -e "${RED}  ✗ 未找到 .git 目录，增量更新需要 git${NC}"
    exit 1
fi

# ─── 1. 读取上次记录 ───
echo -e "\n${GREEN}[1/5] 读取上次建档信息${NC}"
LAST_COMMIT=$(grep -o '"last_commit": "[^"]*"' "$MEMORY_DIR/meta.json" | cut -d'"' -f4)
LAST_DATE=$(grep -o '"commit_date": "[^"]*"' "$MEMORY_DIR/meta.json" | cut -d'"' -f4 || echo "unknown")
CURRENT_COMMIT=$(cd "$REPO_PATH" && git rev-parse HEAD)
CURRENT_DATE=$(cd "$REPO_PATH" && git log -1 --format="%ci")

echo "  上次 commit: ${LAST_COMMIT:0:8} ($LAST_DATE)"
echo "  当前 commit: ${CURRENT_COMMIT:0:8} ($CURRENT_DATE)"

if [ "$LAST_COMMIT" = "$CURRENT_COMMIT" ]; then
    echo -e "\n${GREEN}  ✓ 没有新的提交，记忆已是最新${NC}"
    exit 0
fi

# ─── 2. 获取版本跨度 ───
echo -e "\n${GREEN}[2/5] 分析版本跨度${NC}"
COMMIT_COUNT=$(cd "$REPO_PATH" && git rev-list --count "$LAST_COMMIT..$CURRENT_COMMIT" 2>/dev/null || echo "?")
echo "  跨越 $COMMIT_COUNT 个提交"

echo -e "\n${YELLOW}  提交历史:${NC}"
cd "$REPO_PATH" && git log --oneline "$LAST_COMMIT..$CURRENT_COMMIT" | head -20
if [ "$COMMIT_COUNT" -gt 20 ] 2>/dev/null; then
    echo "  ... 还有 $((COMMIT_COUNT - 20)) 个提交"
fi

# ─── 3. 获取变更文件 ───
echo -e "\n${GREEN}[3/5] 检测文件变更${NC}"

CHANGES_DIR="$MEMORY_DIR/.update-changes"
rm -rf "$CHANGES_DIR"
mkdir -p "$CHANGES_DIR"

# 获取详细的变更信息
cd "$REPO_PATH" && git diff --name-status "$LAST_COMMIT" "$CURRENT_COMMIT" > "$CHANGES_DIR/raw-diff.txt"

# 分类统计
MODIFIED=0
ADDED=0
DELETED=0
RENAMED=0

# 排除目录模式（与 init.sh 一致）
EXCLUDE_PATTERN="node_modules/|dist/|build/|\.next/|out/|coverage/|__pycache__/|\.venv/|venv/|vendor/|generated/|__generated__/|\.idea/|\.vscode/|\.git/|\.repo-memory/|\.nuxt/|\.output/|\.cache/|openspec/"

# 分类变更文件
> "$CHANGES_DIR/modified.txt"
> "$CHANGES_DIR/added.txt"
> "$CHANGES_DIR/deleted.txt"
> "$CHANGES_DIR/renamed.txt"

while IFS=$'\t' read -r status file rest; do
    # 跳过生成代码目录
    if echo "$file" | grep -qE "$EXCLUDE_PATTERN"; then
        continue
    fi
    # 重命名的情况，rest 包含新文件名
    if echo "$rest" | grep -qE "$EXCLUDE_PATTERN" 2>/dev/null; then
        continue
    fi

    case "$status" in
        M)
            echo "$file" >> "$CHANGES_DIR/modified.txt"
            MODIFIED=$((MODIFIED + 1))
            ;;
        A)
            echo "$file" >> "$CHANGES_DIR/added.txt"
            ADDED=$((ADDED + 1))
            ;;
        D)
            echo "$file" >> "$CHANGES_DIR/deleted.txt"
            DELETED=$((DELETED + 1))
            ;;
        R*)
            echo "$file	$rest" >> "$CHANGES_DIR/renamed.txt"
            RENAMED=$((RENAMED + 1))
            ;;
    esac
done < "$CHANGES_DIR/raw-diff.txt"

TOTAL_CHANGES=$((MODIFIED + ADDED + DELETED + RENAMED))
echo "  修改: $MODIFIED 个文件"
echo "  新增: $ADDED 个文件"
echo "  删除: $DELETED 个文件"
echo "  重命名: $RENAMED 个文件"
echo "  总计: $TOTAL_CHANGES 个文件变更（已排除生成代码目录）"

# ─── 4. 确定影响层级 ───
echo -e "\n${GREEN}[4/5] 分析影响层级${NC}"

IMPACT_L0=false
IMPACT_L1_MODULES=()
IMPACT_L2_FILES=()

# 检查是否有包管理文件变化（影响 L0）
L0_TRIGGER_FILES="package.json|requirements.txt|pyproject.toml|pom.xml|build.gradle|go.mod|Cargo.toml|docker-compose.yml|Dockerfile|\.env"
if grep -qE "$L0_TRIGGER_FILES" "$CHANGES_DIR/raw-diff.txt" 2>/dev/null; then
    IMPACT_L0=true
    echo "  ⚡ L0（项目全景）需要更新：检测到配置/依赖变化"
fi

# 检查是否有目录级新增/删除（影响 L0 + L1）
if [ "$ADDED" -gt 0 ] || [ "$DELETED" -gt 0 ]; then
    # 检查是否有新的顶级目录出现
    NEW_DIRS=$(cat "$CHANGES_DIR/added.txt" 2>/dev/null | cut -d'/' -f1-2 | sort -u)
    DEL_DIRS=$(cat "$CHANGES_DIR/deleted.txt" 2>/dev/null | cut -d'/' -f1-2 | sort -u)
    if [ -n "$NEW_DIRS" ] || [ -n "$DEL_DIRS" ]; then
        IMPACT_L0=true
        echo "  ⚡ L0（项目全景）需要更新：目录结构变化"
    fi
fi

# 确定受影响的模块（用于 L1 更新）
ALL_CHANGED_FILES="$CHANGES_DIR/.all-changed.txt"
cat "$CHANGES_DIR/modified.txt" "$CHANGES_DIR/added.txt" "$CHANGES_DIR/deleted.txt" 2>/dev/null | sort -u > "$ALL_CHANGED_FILES"

# 从变更文件路径中提取模块名（取前两级目录）
if [ -s "$ALL_CHANGED_FILES" ]; then
    echo -e "\n${YELLOW}  受影响的目录:${NC}"
    cut -d'/' -f1-2 "$ALL_CHANGED_FILES" | sort | uniq -c | sort -rn | while read count dir; do
        printf "    %-40s %s 个文件\n" "$dir" "$count"
    done
fi

# ─── 5. 哈希比对（精确确认变化） ───
echo -e "\n${GREEN}[5/5] 哈希比对确认${NC}"

HASH_FILE="$MEMORY_DIR/.file-hashes.json"
ACTUALLY_CHANGED=0
CONFIRMED_FILES="$CHANGES_DIR/confirmed-changes.txt"
> "$CONFIRMED_FILES"

if [ -f "$HASH_FILE" ] && [ -s "$CHANGES_DIR/modified.txt" ]; then
    while IFS= read -r file; do
        full_path="$REPO_PATH/$file"
        if [ -f "$full_path" ]; then
            new_hash=$(sha256sum "$full_path" | cut -d' ' -f1)
            old_hash=$(grep -o "\"$file\": \"[^\"]*\"" "$HASH_FILE" 2>/dev/null | cut -d'"' -f4 || echo "none")
            if [ "$new_hash" != "$old_hash" ]; then
                echo "$file" >> "$CONFIRMED_FILES"
                ACTUALLY_CHANGED=$((ACTUALLY_CHANGED + 1))
            fi
        fi
    done < "$CHANGES_DIR/modified.txt"
    echo "  修改文件中，哈希确认变化: $ACTUALLY_CHANGED / $MODIFIED"
else
    # 没有哈希文件或没有修改文件，以 git diff 为准
    if [ -s "$CHANGES_DIR/modified.txt" ]; then
        cp "$CHANGES_DIR/modified.txt" "$CONFIRMED_FILES"
        ACTUALLY_CHANGED=$MODIFIED
    fi
fi

# 新增和删除的文件直接加入确认列表
cat "$CHANGES_DIR/added.txt" >> "$CONFIRMED_FILES" 2>/dev/null
cat "$CHANGES_DIR/deleted.txt" >> "$CONFIRMED_FILES" 2>/dev/null

# ─── 输出更新计划 ───
echo -e "\n${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN}  增量更新计划${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""
echo "  版本跨度: ${LAST_COMMIT:0:8} → ${CURRENT_COMMIT:0:8} ($COMMIT_COUNT commits)"
echo ""
echo "  需要更新的层级:"
if [ "$IMPACT_L0" = true ]; then
    echo "    ⚡ L0 项目全景 — 需刷新"
fi
echo "    ⚡ L1 模块概览 — 受影响的模块需刷新"
echo "    ⚡ L2 文件摘要 — $((ACTUALLY_CHANGED + ADDED)) 份需更新/新建，$DELETED 份需删除"
echo "    ⚡ L3 方法细节 — 对应 L2 变化的文件，其方法级文档需重建"
echo ""
echo "  变更文件清单: $CONFIRMED_FILES"
echo "  修改文件: $CHANGES_DIR/modified.txt"
echo "  新增文件: $CHANGES_DIR/added.txt"
echo "  删除文件: $CHANGES_DIR/deleted.txt"
echo "  重命名文件: $CHANGES_DIR/renamed.txt"
echo ""
echo -e "${YELLOW}  接下来 Claude 将按照变更清单，逐文件更新 L3 → L2 → L1 → L0${NC}"
