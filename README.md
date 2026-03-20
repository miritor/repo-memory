# repo-memory

**Give your AI coding assistant a persistent, structured memory of your entire codebase.**

**为你的 AI 编程助手构建持久化、结构化的代码仓库记忆。**

<p align="center">
  <a href="#english">English</a> | <a href="#%E4%B8%AD%E6%96%87%E8%AF%B4%E6%98%8E">中文</a>
</p>

---

<a id="english"></a>

## English

### The Problem

Every time you start a new conversation with Claude Code (or any AI coding assistant), it has to re-read your source files to understand the project. For a 30K+ line codebase, this wastes context window and time — and the AI still misses things.

### The Solution

**repo-memory** builds a multi-layer memory system for your codebase, like how a senior engineer understands a project:

```
L0  Project Overview  (1 file)        → "What does this project do?"
L1  Module Summary    (per module)    → "What is this module responsible for?"
L2  File Summary      (per file)      → "What's in this file?"
L3  Method Detail     (per method)    → "What does this method do, line by line?"
LF  Foundation Layer                  → DB schemas, IDL/Thrift, Protobuf, migrations
```

When the AI needs to understand your code, it loads **~200 lines of memory docs** instead of **thousands of lines of source code**. Layer by layer, on demand.

### Key Features

- **Multi-layer progressive memory** — 4 levels (L0→L1→L2→L3) + Foundation layer (LF), each query only loads what's needed
- **Incremental updates** — after the initial scan, only changed files are re-analyzed (via `git diff` + SHA256 hash comparison)
- **Auto-sync via Hooks** — SessionStart hook checks for staleness, Stop hook reminds to update memory after code changes
- **Development-aware** — not just for documentation; when you say "add a feature" or "fix this bug", it reads memory docs to understand the codebase instead of re-reading source files
- **Foundation layer for generated code** — DB models (gorm/gen, Prisma, etc.), IDL/Thrift definitions, Protobuf, and migrations are recorded as structured "data dictionaries", not skipped
- **OpenSpec compatible** — works alongside OpenSpec workflows; `openspec/` directories are excluded from memory

### Architecture

```
.repo-memory/
├── meta.json              # Metadata (last commit, tech stack, stats)
├── L0-project.md          # Project overview
├── LF/                    # Foundation layer
│   ├── db-schema.md       # DB entity-relationship overview
│   ├── tables/            # One doc per table
│   ├── idl/               # Thrift/Proto interface definitions
│   ├── proto/             # gRPC service definitions
│   └── migrations/        # Migration timeline
├── L1/                    # Module summaries
├── L2/                    # File summaries
└── L3/                    # Method-level details
```

### Three Modes

| Mode | Trigger | What it does |
|------|---------|-------------|
| **A: Init** | `.repo-memory/` doesn't exist | Full scan, build all layers L0→LF→L1→L2→L3 |
| **B: Update** | User says "update memory" or auto-detected by hook | Incremental update via `git diff`, only rebuild changed docs |
| **C: Query** | User says "implement X" / "fix bug" / "add API" | Read memory docs to understand codebase, assist development |

### Context Window Savings

| Approach | Context needed to locate a method's logic |
|----------|------------------------------------------|
| Read entire repo | Tens of thousands of lines → blows up |
| Two-layer (index + method doc) | ~500 lines |
| **repo-memory (4 layers)** | **~200 lines** |

Many questions can be answered at L0 or L1 without ever reaching L3.

### Installation

**Claude Code (recommended):**

```bash
# Project-level (this repo only)
cp -r repo-memory your-project/.claude/skills/repo-memory

# Global (all projects)
cp -r repo-memory ~/.claude/skills/repo-memory
```

**Claude.ai (web):**

1. Zip the `repo-memory` folder
2. Go to Settings → Customize → Skills → Upload ZIP
3. Enable "Code execution and file creation" in Settings → Capabilities

### Hook Setup (Auto-sync)

Merge the hooks config into your `.claude/settings.local.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [{
          "type": "command",
          "command": "bash .claude/skills/repo-memory/scripts/auto-check.sh",
          "timeout": 10000
        }]
      }
    ],
    "Stop": [
      {
        "hooks": [{
          "type": "command",
          "command": "bash .claude/skills/repo-memory/scripts/post-task-check.sh",
          "timeout": 5000
        }]
      }
    ]
  }
}
```

> Adjust the path if your skill is installed elsewhere. Use absolute paths if relative paths don't work.

### Usage

```bash
claude  # Start Claude Code in your project

# First time → builds memory
> Build repo memory for this project

# Normal development → reads memory, not source code
> Add a user VIP level feature

# After many commits → auto-detected, or manually trigger
> Update repo memory
```

### Supported Tech Stacks

Works with any language. Has specialized parsing guides for:

- **Go** (gorm/gen, Hertz, Thrift IDL)
- **TypeScript/JavaScript** (Prisma, React, Next.js, NestJS)
- **Python** (SQLAlchemy, Django, FastAPI)
- **Java/Kotlin** (MyBatis, JPA, Spring Boot)
- **Rust** (diesel, sea-orm)
- Protobuf / gRPC / GraphQL / OpenAPI

### File Structure

```
repo-memory/
├── SKILL.md                  # Core instructions for Claude
├── hooks-config.json         # Hook configuration template
├── references/
│   └── parsing-guide.md      # Language-specific parsing rules
└── scripts/
    ├── init.sh               # First-time full scan helper
    ├── update.sh             # Incremental update helper
    ├── auto-check.sh         # SessionStart hook (auto staleness check)
    └── post-task-check.sh    # Stop hook (remind to sync memory)
```

### Works With OpenSpec

repo-memory and OpenSpec are complementary:

| | OpenSpec | repo-memory |
|---|---------|-------------|
| Focus | What to change (requirements) | What the code looks like (knowledge) |
| Output | proposal / spec / tasks | L0 / L1 / L2 / L3 / LF |
| Lifecycle | Per-feature (short-term) | Persistent (long-term) |

Typical workflow: OpenSpec defines the task → repo-memory provides codebase understanding → you write code faster.

### License

MIT

---

<a id="中文说明"></a>

## 中文说明

### 问题

每次和 Claude Code 开新对话，它都要重新阅读源码来理解项目。3 万多行的代码库，浪费上下文窗口和时间，AI 还容易遗漏细节。

### 解决方案

**repo-memory** 为代码仓库构建多层级记忆系统，模拟资深工程师对项目的认知结构：

```
L0  项目全景    （1份）        → "这个项目是做什么的"
L1  模块概览    （每模块1份）   → "这个模块负责什么"
L2  文件摘要    （每文件1份）   → "这个文件里有什么"
L3  方法细节    （每方法1份）   → "这个方法逐行在干什么"
LF  基础设施层                 → 数据库表结构、IDL/Thrift、Protobuf、Migration
```

查询时 AI 只需要加载 **约 200 行记忆文档**，而不是 **几万行源码**。逐层下钻，按需加载。

### 核心特性

- **多层递进式记忆** — L0→L1→L2→L3 + LF 基础设施层，每次查询只加载需要的层级
- **增量更新** — 首次全量扫描后，后续只更新变化的文件（基于 `git diff` + SHA256 哈希）
- **Hook 自动同步** — 开始对话自动检查记忆是否过旧，结束对话提醒同步记忆
- **辅助开发** — 不只是建档工具；说"加个功能"或"修 bug"时，自动读记忆文档来理解仓库
- **高价值生成代码不遗漏** — gorm/gen、Prisma、Thrift IDL、Protobuf、Migration 等纳入 LF 层
- **兼容 OpenSpec** — 与 OpenSpec 工作流无缝配合，`openspec/` 目录自动排除

### 三种模式

| 模式 | 触发条件 | 行为 |
|------|---------|------|
| **A: 首次建档** | `.repo-memory/` 不存在 | 全量扫描，构建 L0→LF→L1→L2→L3 |
| **B: 增量更新** | 用户说"更新记忆"或 Hook 自动检测 | 基于 git diff 只更新变化部分 |
| **C: 查询辅助** | 用户说"实现功能/修 bug/加接口" | 读记忆文档理解仓库，辅助开发 |

### 安装

```bash
# 项目级安装
cp -r repo-memory your-project/.claude/skills/repo-memory

# 全局安装
cp -r repo-memory ~/.claude/skills/repo-memory
```

### 使用

```bash
claude  # 在项目目录启动 Claude Code

# 首次建档
> 帮我建立仓库记忆

# 正常开发（自动读记忆而不是重新读源码）
> 帮我加一个用户VIP等级功能

# 手动更新记忆
> 更新仓库记忆
```

### 协议

MIT
