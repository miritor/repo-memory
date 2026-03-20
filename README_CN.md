# repo-memory

**为你的 AI 编程助手构建持久化、结构化的代码仓库记忆。**

[English](./README.md)

---

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

### 架构

```
.repo-memory/
├── meta.json              # 元信息（最后 commit、技术栈、统计）
├── L0-project.md          # 项目全景
├── LF/                    # 基础设施层
│   ├── db-schema.md       # 数据库 ER 概览
│   ├── tables/            # 每张表一份文档
│   ├── idl/               # Thrift/Proto 接口定义
│   ├── proto/             # gRPC 服务定义
│   └── migrations/        # Migration 时间线
├── L1/                    # 模块概览
├── L2/                    # 文件摘要
└── L3/                    # 方法级细节
```

### 三种模式

| 模式 | 触发条件 | 行为 |
|------|---------|------|
| **A: 首次建档** | `.repo-memory/` 不存在 | 全量扫描，构建 L0→LF→L1→L2→L3 |
| **B: 增量更新** | 用户说"更新记忆"或 Hook 自动检测 | 基于 git diff 只更新变化部分 |
| **C: 查询辅助** | 用户说"实现功能/修 bug/加接口" | 读记忆文档理解仓库，辅助开发 |

### 上下文窗口节省

| 方式 | 定位一个方法逻辑需要的上下文 |
|------|--------------------------|
| 读整个仓库 | 几万行 → 爆掉 |
| 两层（索引 + 方法文档） | ~500 行 |
| **repo-memory（四层）** | **~200 行** |

很多问题在 L0 或 L1 就能回答，根本不需要下钻到 L3。

### 安装

**Claude Code（推荐）：**

```bash
# 项目级安装（只对当前仓库生效）
cp -r repo-memory your-project/.claude/skills/repo-memory

# 全局安装（所有项目可用）
cp -r repo-memory ~/.claude/skills/repo-memory
```

**Claude.ai（网页版）：**

1. 将 `repo-memory` 文件夹压缩为 ZIP
2. 打开设置 → 自定义 → Skills → 上传 ZIP
3. 确保设置 → 功能中开启了"代码执行和文件创建"

### Hook 配置（自动同步）

将以下配置合并到你的 `.claude/settings.local.json`：

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

> 如果 skill 安装在其他位置，请调整路径。相对路径不生效时改用绝对路径。

### 使用

```bash
claude  # 在项目目录启动 Claude Code

# 首次建档
> 帮我建立仓库记忆

# 正常开发（自动读记忆而不是重新读源码）
> 帮我加一个用户VIP等级功能

# 很多次提交后（自动检测或手动触发）
> 更新仓库记忆
```

### 支持的技术栈

支持任何语言，以下技术栈有专门的解析指南：

- **Go**（gorm/gen、Hertz、Thrift IDL）
- **TypeScript/JavaScript**（Prisma、React、Next.js、NestJS）
- **Python**（SQLAlchemy、Django、FastAPI）
- **Java/Kotlin**（MyBatis、JPA、Spring Boot）
- **Rust**（diesel、sea-orm）
- Protobuf / gRPC / GraphQL / OpenAPI

### 文件结构

```
repo-memory/
├── SKILL.md                  # 核心指令（Claude 读这个来执行）
├── hooks-config.json         # Hook 配置模板
├── references/
│   └── parsing-guide.md      # 各语言解析规则
└── scripts/
    ├── init.sh               # 首次全量扫描辅助
    ├── update.sh             # 增量更新辅助
    ├── auto-check.sh         # SessionStart Hook（自动检查过旧）
    └── post-task-check.sh    # Stop Hook（提醒同步记忆）
```

### 与 OpenSpec 的关系

repo-memory 和 OpenSpec 互补，不冲突：

| | OpenSpec | repo-memory |
|---|---------|-------------|
| 关注 | 当前需求要做什么（变更规划） | 整个仓库长什么样（代码认知） |
| 产出 | proposal / spec / tasks | L0 / L1 / L2 / L3 / LF |
| 生命周期 | 需求开始 → 完成 → 归档（短期） | 常驻，随仓库演进（长期） |

典型协作流程：OpenSpec 定义任务 → repo-memory 提供仓库理解 → 更快写出代码。

### 协议

MIT
