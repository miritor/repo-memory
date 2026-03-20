#!/usr/bin/env bash
# repo-memory init: 首次全量建档的辅助脚本
# 用法: bash init.sh <repo_path>
#
# 此脚本负责：
# 1. 创建 .repo-memory 目录结构
# 2. 检测技术栈
# 3. 列出所有手写代码文件（排除生成代码）
# 4. 生成 meta.json 初始版本
# 5. 输出文件清单供 Claude 逐批处理

set -euo pipefail

REPO_PATH="${1:-.}"
MEMORY_DIR="$REPO_PATH/.repo-memory"

# ─── 颜色输出 ───
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN}  Repo Memory — 首次全量建档${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"

# ─── 1. 创建目录结构 ───
echo -e "\n${GREEN}[1/6] 创建 .repo-memory 目录结构${NC}"
mkdir -p "$MEMORY_DIR"/{LF/tables,LF/proto,LF/migrations,LF/api-contracts,L1,L2,L3}
echo "  ✓ 已创建 $MEMORY_DIR/{LF,L1,L2,L3}"

# ─── 2. 检测技术栈 ───
echo -e "\n${GREEN}[2/5] 检测技术栈${NC}"
TECH_STACK=()

detect_stack() {
    local file="$1" stack="$2"
    if [ -f "$REPO_PATH/$file" ]; then
        TECH_STACK+=("$stack")
        echo "  ✓ 检测到 $stack ($file)"
    fi
}

detect_stack "package.json" "Node.js/JavaScript"
detect_stack "tsconfig.json" "TypeScript"
detect_stack "requirements.txt" "Python"
detect_stack "Pipfile" "Python"
detect_stack "pyproject.toml" "Python"
detect_stack "pom.xml" "Java/Maven"
detect_stack "build.gradle" "Java/Gradle"
detect_stack "build.gradle.kts" "Kotlin/Gradle"
detect_stack "go.mod" "Go"
detect_stack "Cargo.toml" "Rust"
detect_stack "composer.json" "PHP"
detect_stack "Gemfile" "Ruby"
detect_stack "pubspec.yaml" "Dart/Flutter"
detect_stack "next.config.js" "Next.js"
detect_stack "next.config.mjs" "Next.js"
detect_stack "next.config.ts" "Next.js"
detect_stack "nuxt.config.ts" "Nuxt.js"
detect_stack "vue.config.js" "Vue.js"
detect_stack "angular.json" "Angular"
detect_stack "docker-compose.yml" "Docker"
detect_stack "Dockerfile" "Docker"
detect_stack "prisma/schema.prisma" "Prisma"

if [ ${#TECH_STACK[@]} -eq 0 ]; then
    echo "  ⚠ 未检测到已知技术栈标识文件"
fi

# ─── 3. 定义排除目录（仅零价值生成代码） ───
EXCLUDE_DIRS=(
    "node_modules" ".pnpm" "dist" "build" ".next" "out" "coverage"
    "__pycache__" ".venv" "venv" "env" ".tox" ".mypy_cache"
    "target" "bin" "obj"
    ".idea" ".vscode" ".git" ".repo-memory"
    ".nuxt" ".output" ".cache" ".parcel-cache"
    ".turbo" ".vercel" ".netlify"
    "storybook-static"
    "openspec"
)

# 构造 find 的排除参数
FIND_EXCLUDES=""
for dir in "${EXCLUDE_DIRS[@]}"; do
    FIND_EXCLUDES="$FIND_EXCLUDES ! -path '*/$dir/*'"
done

# ─── 4. 扫描手写代码文件 ───
echo -e "\n${GREEN}[3/5] 扫描手写代码文件${NC}"

# 源代码文件扩展名
CODE_EXTENSIONS=(
    "ts" "tsx" "js" "jsx" "mjs" "cjs"
    "py" "pyw"
    "java" "kt" "kts"
    "go"
    "rs"
    "php"
    "rb"
    "dart"
    "vue" "svelte"
    "css" "scss" "less"
    "sql"
    "sh" "bash"
    "yaml" "yml"
    "json"
    "md"
    "html"
    "xml"
)

# 构造 find 的扩展名参数
EXT_PATTERN=""
for ext in "${CODE_EXTENSIONS[@]}"; do
    if [ -z "$EXT_PATTERN" ]; then
        EXT_PATTERN="-name '*.$ext'"
    else
        EXT_PATTERN="$EXT_PATTERN -o -name '*.$ext'"
    fi
done

# 执行扫描
FILE_LIST="$MEMORY_DIR/.file-list.txt"
eval "find '$REPO_PATH' -type f \( $EXT_PATTERN \) $FIND_EXCLUDES" | sort > "$FILE_LIST"

TOTAL_FILES=$(wc -l < "$FILE_LIST")
echo "  ✓ 找到 $TOTAL_FILES 个源文件"

# 统计行数
TOTAL_LINES=0
while IFS= read -r file; do
    lines=$(wc -l < "$file" 2>/dev/null || echo 0)
    TOTAL_LINES=$((TOTAL_LINES + lines))
done < "$FILE_LIST"
echo "  ✓ 总计 $TOTAL_LINES 行代码"

# 按目录分组统计
echo -e "\n${YELLOW}  目录分布:${NC}"
while IFS= read -r file; do
    # 获取相对于 repo 的路径的第一级目录
    rel_path="${file#$REPO_PATH/}"
    echo "$rel_path"
done < "$FILE_LIST" | cut -d'/' -f1 | sort | uniq -c | sort -rn | head -15 | while read count dir; do
    printf "    %-30s %s 个文件\n" "$dir" "$count"
done

# ─── 4. 扫描高价值生成代码（LF 基础设施层） ───
echo -e "\n${GREEN}[4/7] 扫描高价值生成代码（基础设施层）${NC}"
FOUNDATION_LIST="$MEMORY_DIR/.foundation-list.txt"
> "$FOUNDATION_LIST"
FOUNDATION_COUNT=0

echo -e "${YELLOW}  检测 DB Model/Query 文件:${NC}"

# gorm/gen (Go)
GORM_GEN_FILES=$(find "$REPO_PATH" -type f \( -name "*.gen.go" -o \( -path "*/model/*.go" -name "*.go" \) -o \( -path "*/query/*.go" -name "*.go" \) -o \( -path "*/dal/*.go" -name "*.go" \) \) ! -path "*/vendor/*" ! -path "*/.git/*" 2>/dev/null | sort)
if [ -n "$GORM_GEN_FILES" ]; then
    echo "$GORM_GEN_FILES" >> "$FOUNDATION_LIST"
    count=$(echo "$GORM_GEN_FILES" | wc -l)
    echo "    ✓ gorm/gen 相关: $count 个文件"
    FOUNDATION_COUNT=$((FOUNDATION_COUNT + count))
fi

# ent (Go)
ENT_FILES=$(find "$REPO_PATH" -type f -path "*/ent/*.go" ! -path "*/vendor/*" 2>/dev/null | sort)
if [ -n "$ENT_FILES" ]; then
    echo "$ENT_FILES" >> "$FOUNDATION_LIST"
    count=$(echo "$ENT_FILES" | wc -l)
    echo "    ✓ ent 生成: $count 个文件"
    FOUNDATION_COUNT=$((FOUNDATION_COUNT + count))
fi

# Prisma
PRISMA_FILES=$(find "$REPO_PATH" -type f \( -name "schema.prisma" -o -path "*/prisma/*" \) ! -path "*/node_modules/*" 2>/dev/null | sort)
if [ -n "$PRISMA_FILES" ]; then
    echo "$PRISMA_FILES" >> "$FOUNDATION_LIST"
    count=$(echo "$PRISMA_FILES" | wc -l)
    echo "    ✓ Prisma schema: $count 个文件"
    FOUNDATION_COUNT=$((FOUNDATION_COUNT + count))
fi

# Protobuf
echo -e "${YELLOW}  检测 Proto/gRPC 文件:${NC}"
PROTO_FILES=$(find "$REPO_PATH" -type f \( -name "*.proto" -o -name "*.pb.go" -o -name "*_grpc.pb.go" -o -name "*_pb2.py" -o -name "*.pb.ts" \) ! -path "*/vendor/*" ! -path "*/node_modules/*" 2>/dev/null | sort)
if [ -n "$PROTO_FILES" ]; then
    echo "$PROTO_FILES" >> "$FOUNDATION_LIST"
    count=$(echo "$PROTO_FILES" | wc -l)
    echo "    ✓ Proto/gRPC: $count 个文件"
    FOUNDATION_COUNT=$((FOUNDATION_COUNT + count))
fi

# Migration files
echo -e "${YELLOW}  检测 Migration 文件:${NC}"
MIGRATION_FILES=$(find "$REPO_PATH" -type f \( -name "*.sql" -o -name "*.up.sql" -o -name "*.down.sql" \) \( -path "*/migration*" -o -path "*/migrate*" \) 2>/dev/null | sort)
if [ -n "$MIGRATION_FILES" ]; then
    echo "$MIGRATION_FILES" >> "$FOUNDATION_LIST"
    count=$(echo "$MIGRATION_FILES" | wc -l)
    echo "    ✓ Migration SQL: $count 个文件"
    FOUNDATION_COUNT=$((FOUNDATION_COUNT + count))
fi

# GraphQL schema
GRAPHQL_FILES=$(find "$REPO_PATH" -type f \( -name "*.graphql" -o -name "*.gql" -o -name "schema.graphqls" \) ! -path "*/node_modules/*" 2>/dev/null | sort)
if [ -n "$GRAPHQL_FILES" ]; then
    echo "$GRAPHQL_FILES" >> "$FOUNDATION_LIST"
    count=$(echo "$GRAPHQL_FILES" | wc -l)
    echo "    ✓ GraphQL schema: $count 个文件"
    FOUNDATION_COUNT=$((FOUNDATION_COUNT + count))
fi

# OpenAPI / Swagger
OPENAPI_FILES=$(find "$REPO_PATH" -type f \( -name "swagger.*" -o -name "openapi.*" -o -name "api-spec.*" \) \( -name "*.json" -o -name "*.yaml" -o -name "*.yml" \) 2>/dev/null | sort)
if [ -n "$OPENAPI_FILES" ]; then
    echo "$OPENAPI_FILES" >> "$FOUNDATION_LIST"
    count=$(echo "$OPENAPI_FILES" | wc -l)
    echo "    ✓ OpenAPI/Swagger: $count 个文件"
    FOUNDATION_COUNT=$((FOUNDATION_COUNT + count))
fi

# 去重
sort -u "$FOUNDATION_LIST" -o "$FOUNDATION_LIST"
FOUNDATION_COUNT=$(wc -l < "$FOUNDATION_LIST")
echo -e "\n  ✓ 基础设施层总计: $FOUNDATION_COUNT 个文件"

# ─── 5. 获取 git 信息 ───
echo -e "\n${GREEN}[5/7] 获取 Git 信息${NC}"
CURRENT_COMMIT="unknown"
COMMIT_DATE="unknown"
if [ -d "$REPO_PATH/.git" ]; then
    CURRENT_COMMIT=$(cd "$REPO_PATH" && git rev-parse HEAD 2>/dev/null || echo "unknown")
    COMMIT_DATE=$(cd "$REPO_PATH" && git log -1 --format="%ci" 2>/dev/null || echo "unknown")
    BRANCH=$(cd "$REPO_PATH" && git branch --show-current 2>/dev/null || echo "unknown")
    echo "  ✓ 当前分支: $BRANCH"
    echo "  ✓ 最新 commit: ${CURRENT_COMMIT:0:8} ($COMMIT_DATE)"
else
    echo "  ⚠ 未检测到 .git 目录"
fi

# ─── 6. 生成文件哈希 ───
echo -e "\n${GREEN}[6/7] 生成文件哈希${NC}"
HASH_FILE="$MEMORY_DIR/.file-hashes.json"
echo "{" > "$HASH_FILE"
FIRST=true
while IFS= read -r file; do
    rel_path="${file#$REPO_PATH/}"
    hash=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo "," >> "$HASH_FILE"
    fi
    printf '  "%s": "%s"' "$rel_path" "$hash" >> "$HASH_FILE"
done < "$FILE_LIST"
echo -e "\n}" >> "$HASH_FILE"
echo "  ✓ 已为 $TOTAL_FILES 个文件生成哈希"

# ─── 7. 生成 meta.json ───
TECH_JSON=$(printf '"%s",' "${TECH_STACK[@]}" | sed 's/,$//')
EXCLUDE_JSON=$(printf '"%s",' "${EXCLUDE_DIRS[@]}" | sed 's/,$//')

cat > "$MEMORY_DIR/meta.json" << EOF
{
  "version": "1.0.0",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "last_updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "last_commit": "$CURRENT_COMMIT",
  "commit_date": "$COMMIT_DATE",
  "tech_stack": [$TECH_JSON],
  "stats": {
    "total_files": $TOTAL_FILES,
    "total_lines": $TOTAL_LINES,
    "foundation_files": $FOUNDATION_COUNT,
    "l0_files": 0,
    "lf_files": 0,
    "l1_files": 0,
    "l2_files": 0,
    "l3_files": 0
  },
  "excluded_dirs": [$EXCLUDE_JSON]
}
EOF
echo -e "\n  ✓ meta.json 已生成"

# ─── 输出摘要 ───
echo -e "\n${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN}  初始化完成！${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""
echo "  目录结构:   $MEMORY_DIR/{LF,L1,L2,L3}"
echo "  技术栈:     ${TECH_STACK[*]:-未检测到}"
echo "  源文件:     $TOTAL_FILES 个"
echo "  代码行:     $TOTAL_LINES 行"
echo "  基础设施文件: $FOUNDATION_COUNT 个（DB model/proto/migration 等）"
echo "  Git:        ${CURRENT_COMMIT:0:8}"
echo ""
echo "  文件清单:     $MEMORY_DIR/.file-list.txt"
echo "  基础设施清单: $MEMORY_DIR/.foundation-list.txt"
echo "  文件哈希:     $MEMORY_DIR/.file-hashes.json"
echo ""
echo -e "${YELLOW}  接下来 Claude 将逐批读取文件，生成 L0 → LF → L1 → L2 → L3 记忆文档${NC}"
