---
name: repo-memory
description: >
  为代码仓库构建多层级记忆系统（L0项目全景 → L1模块概览 → L2文件摘要 → L3方法细节），
  支持首次全量建档和基于 git diff 的增量更新。当用户提到"仓库记忆"、"代码记忆"、
  "项目记忆"、"仓库索引"、"代码索引"、"代码文档化"、"仓库理解"、"项目理解"、
  "帮我记住这个项目"、"分析整个仓库"、"理解这个代码库"、"建立代码档案"、
  "代码知识库"、"增量更新记忆"、"刷新代码文档"时，使用此 skill。
  即使用户没有明确说"记忆"，只要意图是让 Claude 深度理解并持续跟踪一个代码仓库，
  也应该触发此 skill。

  【重要】本 skill 不仅用于建档和更新，也用于辅助开发。当用户要做新需求、改 bug、
  重构、代码审查等任何需要理解仓库代码的开发任务时，如果 .repo-memory 目录已存在，
  应优先阅读记忆文档来理解仓库，而不是重新阅读源码。触发词包括但不限于：
  "帮我实现"、"开发这个功能"、"改一下"、"加个接口"、"修这个 bug"、
  "重构"、"优化"、"review 代码"、"写个新模块"等开发类请求。
  只要用户的任务涉及一个已建档的仓库，就应该触发此 skill 进入查询辅助模式。
---

# Repo Memory — 仓库多层级记忆系统

## 核心理念

本 skill 为代码仓库构建 **四层递进式记忆 + 基础设施层**，模拟一个资深工程师对项目的认知结构：

```
L0 项目全景    （1份）      → "这个项目是做什么的"
L1 模块概览    （每模块1份） → "这个模块负责什么"
L2 文件摘要    （每文件1份） → "这个文件里有什么"
L3 方法细节    （每方法1份） → "这个方法逐行在干什么"

LF 基础设施层（Foundation）  → 数据库表结构、Protobuf 定义、API Schema 等
   这是所有业务逻辑的基石，独立于 L0-L3 层级，任何层级查询时都可能需要引用
```

查询时逐层下钻，每次只加载当前层 + 目标层的 md，上下文开销极小。
LF 层是"按需横切"的——当任何层级的分析涉及数据操作时，自动关联对应的 LF 文档。

## 三种运行模式

### 模式 A：首次全量建档（init）
扫描整个仓库，从 L0 到 L3 逐层生成所有记忆文档。

### 模式 B：增量更新（update）
基于 git diff 检测变化文件，只重建受影响的层级文档。

### 模式 C：查询辅助开发（query）
当 `.repo-memory/` 已存在且用户提出开发任务时进入此模式。
不重新阅读源码，而是通过记忆文档快速理解仓库，辅助完成开发任务。

**模式自动判断逻辑：**
1. `.repo-memory/` 不存在 → 模式 A（init）
2. `.repo-memory/` 存在 + 用户说"更新记忆/刷新文档" → 模式 B（update）
3. `.repo-memory/` 存在 + 用户说"实现功能/改bug/加接口..." → 模式 C（query）
4. `.repo-memory/` 存在 + 模式 C 中发现记忆过旧 → 先执行模式 B，再进入模式 C

### 自动更新机制（Hooks）

通过 Claude Code 的 Hook 系统，记忆更新是**全自动**的，不需要用户手动触发：

**SessionStart Hook（对话开始时）**：
- 自动运行 `scripts/auto-check.sh`
- 检查 `.repo-memory/meta.json` 中的 `last_commit` 与当前 HEAD 的差距
- 根据滞后程度分三级响应：
  - ≤ 3 commits（低）→ 提示记忆略有滞后，按需更新
  - 4-10 commits（中）→ 建议尽快更新
  - > 10 commits（高）→ 主动执行增量更新后再处理用户任务
- 如果记忆是最新的 → 完全静默，不打扰用户

**Stop Hook（对话结束时）**：
- 自动运行 `scripts/post-task-check.sh`
- 检测本次对话是否产生了代码变更（git diff）
- 如果有变更但记忆未同步 → 提醒 Claude 更新对应的 L2/L3/LF 文档

**安装方式**：将 `hooks-config.json` 中的内容合并到项目的 `.claude/settings.json` 中。

---

## 第一步：环境准备

1. 确认仓库路径（用户上传或指定路径）
2. 检查是否已存在 `.repo-memory/` 目录：
   - 存在 → 进入增量更新模式
   - 不存在 → 进入首次建档模式
3. 检测技术栈（通过 package.json / requirements.txt / pom.xml / go.mod / Cargo.toml 等）
4. **三分类识别代码**：

### 代码分类策略（关键！）

不是所有生成代码都应该跳过。按价值分为三类：

| 分类 | 处理方式 | 示例 |
|------|---------|------|
| **手写代码** | 全量建档 L0-L3 | src/ 下的业务代码 |
| **高价值生成代码** | 纳入 LF 基础设施层，用专用格式记录 | gorm/gen Model、protobuf、prisma schema、GraphQL schema、OpenAPI spec |
| **零价值生成代码** | 完全跳过 | node_modules、dist、build、.next |
| **非代码工程文件** | 跳过（属于需求管理，不是代码逻辑） | openspec/archive/、openspec/changes/、openspec/specs/ |

#### 高价值生成代码白名单（自动检测）

以下生成代码是业务逻辑的基石，**必须纳入 LF 层**：

**数据库模型类**（定义了表结构和查询能力）：
- Go: gorm/gen 生成的 `model/` 和 `query/` 目录、ent 生成的 `ent/` 目录、sqlc 生成的文件
- Python: SQLAlchemy 自动生成的 model、Django migration 文件
- Java: MyBatis Generator 生成的 entity/mapper、JPA metamodel
- TypeScript: Prisma Client (`prisma/client/`)、TypeORM entity、Drizzle schema
- Rust: diesel 生成的 schema.rs、sea-orm entity

**IDL 接口定义**（对外窗口，定义了服务暴露的所有接口）：
- Thrift IDL 源文件（`idl/*.thrift`）— **源文件本身就是高价值资产，不仅是生成产物**
- Protobuf 源文件（`proto/*.proto`）

**服务间通信契约**（IDL/Proto 的生成产物）：
- protobuf 生成的 .pb.go / .pb.ts / _pb2.py
- gRPC 生成的 _grpc.pb.go / _grpc.ts
- Thrift 生成的 model 代码（如 Hertz 框架的 `biz/gen/`）
- GraphQL 生成的类型定义
- OpenAPI/Swagger 生成的 client/server stubs

**配置即代码**（定义了基础架构）：
- 数据库 migration 文件（SQL 或框架格式）
- Terraform / Pulumi 生成的 state 相关代码

#### 检测方法

```bash
# 检查是否已有记忆
ls -la <repo_path>/.repo-memory/ 2>/dev/null

# 检测技术栈
ls <repo_path>/package.json <repo_path>/requirements.txt <repo_path>/pom.xml <repo_path>/go.mod <repo_path>/Cargo.toml 2>/dev/null

# 扫描手写代码
find <repo_path> -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" -o -name "*.java" -o -name "*.go" -o -name "*.rs" \) \
  ! -path "*/node_modules/*" ! -path "*/dist/*" ! -path "*/build/*" ! -path "*/.next/*" ! -path "*/__pycache__/*" \
  ! -path "*/openspec/*" \
  | head -20

# 扫描高价值生成代码（以 Go + gorm/gen 为例）
find <repo_path> -type f \( -name "*.gen.go" -o -path "*/model/*.go" -o -path "*/query/*.go" \) | head -20
find <repo_path> -type f -name "*.pb.go" | head -20
find <repo_path> -type f -name "*.sql" -path "*/migration*" | head -20

# 扫描 IDL 源文件（Thrift / Proto — 对外接口定义）
find <repo_path> -type f \( -name "*.thrift" -o -name "*.proto" \) | head -20
# 扫描 IDL 生成产物目录
ls -la <repo_path>/biz/gen/ 2>/dev/null
```

---

## 第二步：首次全量建档（init 模式）

按 L0 → L1 → L2 → L3 顺序逐层构建。

### 构建之前，先阅读参考文档

根据检测到的技术栈，阅读对应的解析参考：
- 通用规则：`references/parsing-guide.md`

### 目录结构

所有记忆文档存储在仓库根目录的 `.repo-memory/` 下：

```
.repo-memory/
├── meta.json                    # 元信息（版本、最后更新commit、技术栈等）
├── L0-project.md                # 项目全景
├── LF/                          # 基础设施层（Foundation）
│   ├── db-schema.md             # 数据库全局 ER 概览
│   ├── tables/                  # 每张表一份文档
│   │   ├── users.md
│   │   ├── orders.md
│   │   └── ...
│   ├── idl/                     # Thrift / Protobuf 接口定义（对外窗口）
│   │   ├── idl-overview.md      # IDL 全局索引
│   │   ├── biz-public.md        # 每个 IDL 文件一份文档
│   │   ├── biz-admin.md
│   │   └── ...
│   ├── proto/                   # Protobuf / gRPC 服务定义
│   │   ├── user-service.md
│   │   └── ...
│   ├── migrations/              # Migration 变更时间线
│   │   └── migration-timeline.md
│   └── api-contracts/           # OpenAPI / GraphQL schema
│       └── ...
├── L1/
│   ├── auth-module.md           # 模块概览
│   ├── api-module.md
│   └── ...
├── L2/
│   ├── src--services--UserService.ts.md    # 文件摘要（路径用--分隔）
│   ├── src--controllers--AuthController.ts.md
│   └── ...
└── L3/
    ├── src--services--UserService.ts--authenticate.md  # 方法细节
    ├── src--services--UserService.ts--register.md
    └── ...
```

### L0 项目全景（约 100-200 行）

扫描整个仓库，生成一份全景文档，包含：

```markdown
# 项目全景：[项目名]

## 基本信息
- 技术栈：[框架/语言/主要依赖]
- 手写代码量：[x] 行（[y] 个文件）
- 生成代码量：[x] 行（已标记跳过）
- 仓库最后提交：[commit hash + 日期]

## 目录结构概览
[只展示 src/ 等核心目录的前 2-3 层]

## 模块划分
| 模块名 | 路径 | 职责一句话 | 核心文件数 |
|--------|------|-----------|-----------|
| auth   | src/modules/auth | 用户认证与授权 | 8 |
| ...    | ...  | ...       | ...       |

## 核心数据流
[用文字描述主要的请求处理链路，例如：]
请求 → Router → Middleware(auth) → Controller → Service → Repository → DB

## 外部依赖
[列出关键的第三方服务/API/数据库]

## 部署与配置
[简述部署方式、环境变量分组]

## 基础设施层索引
| 类型 | 数量 | 文档位置 |
|------|------|---------|
| 数据库表 | [x] 张 | LF/tables/ |
| IDL 接口文件 | [x] 个 | LF/idl/ |
| Protobuf 服务 | [x] 个 | LF/proto/ |
| Migration | [x] 个 | LF/migrations/ |
```

### LF 基础设施层（Foundation）

**这是所有业务逻辑的基石**。LF 层独立于 L0-L3 的层级结构，任何层级在分析到数据操作时都可以横向引用 LF 文档。

构建顺序：**在 L0 之后、L1 之前构建 LF 层**，因为后续分析模块和方法时需要知道数据结构。

#### LF-0 数据库全局 ER 概览（1份，约 100-200 行）

```markdown
# 数据库全局概览

## 数据库信息
- 类型：[MySQL/PostgreSQL/MongoDB/...]
- ORM/生成工具：[gorm/gen / prisma / ent / ...]
- 生成代码位置：[dal/query/ 和 dal/model/]

## 表清单
| 表名 | 中文说明 | 核心字段数 | 关联表 |
|------|---------|-----------|--------|
| users | 用户表 | 12 | orders, profiles |
| orders | 订单表 | 18 | users, products, payments |
| ... | ... | ... | ... |

## ER 关系图（文字版）
users 1──N orders（一个用户多个订单）
orders N──1 products（多个订单对应一个商品）
orders 1──1 payments（一个订单一笔支付）
users 1──1 profiles（一对一用户档案）
...

## 核心业务实体关系
[用简洁的文字描述核心领域模型之间的关系]
```

#### LF-Table 每张表的详细文档（每份约 40-80 行）

```markdown
# 表结构：[table_name]

## 基本信息
- 表名：users
- 说明：用户主表，存储账户和认证信息
- 生成来源：dal/model/users.gen.go
- 对应 Query 对象：dal/query/users.gen.go

## 字段清单
| 字段名 | 类型 | 说明 | 约束 | 默认值 |
|--------|------|------|------|--------|
| id | bigint | 主键 | PK, AUTO_INCREMENT | - |
| email | varchar(255) | 邮箱 | UNIQUE, NOT NULL | - |
| password_hash | varchar(255) | 密码哈希 | NOT NULL | - |
| status | tinyint | 状态(0=禁用,1=正常,2=锁定) | NOT NULL | 1 |
| fail_count | int | 连续登录失败次数 | NOT NULL | 0 |
| created_at | datetime | 创建时间 | NOT NULL | CURRENT_TIMESTAMP |
| updated_at | datetime | 更新时间 | NOT NULL | CURRENT_TIMESTAMP |
| deleted_at | datetime | 软删除时间 | NULL | NULL |

## 索引
| 索引名 | 字段 | 类型 | 说明 |
|--------|------|------|------|
| PRIMARY | id | PRIMARY | - |
| idx_email | email | UNIQUE | 邮箱唯一索引 |
| idx_status | status | NORMAL | 按状态查询 |
| idx_deleted_at | deleted_at | NORMAL | 软删除过滤 |

## 关联关系
- users.id → orders.user_id（一对多：一个用户多个订单）
- users.id → profiles.user_id（一对一：用户档案）
- users.id → login_logs.user_id（一对多：登录日志）

## gorm/gen 生成的查询能力
[从 query 文件中提取关键的自定义查询方法]
| 方法名 | 说明 | 参数 |
|--------|------|------|
| FindByEmail | 按邮箱查用户 | email string |
| FindActiveUsers | 查所有活跃用户 | - |
| UpdateFailCount | 更新失败次数 | id int64, count int |
| ... | ... | ... |

## 被哪些 Service/Repository 使用
- UserService.authenticate() — 查询+更新 fail_count
- UserService.register() — 插入新记录
- AdminService.listUsers() — 查询列表
```

#### LF-Proto Protobuf/gRPC 服务定义（如果项目使用）

```markdown
# Proto 服务：[service_name]

## 文件来源
- .proto 源文件：proto/user_service.proto
- 生成代码：pb/user_service.pb.go, pb/user_service_grpc.pb.go

## 服务定义
| RPC 方法 | 请求类型 | 响应类型 | 说明 |
|---------|---------|---------|------|
| GetUser | GetUserRequest | GetUserResponse | 获取用户信息 |
| ListUsers | ListUsersRequest | ListUsersResponse | 用户列表 |
| ... | ... | ... | ... |

## 核心 Message 定义
### GetUserRequest
| 字段 | 类型 | 编号 | 说明 |
|------|------|------|------|
| user_id | int64 | 1 | 用户ID |

### GetUserResponse
| 字段 | 类型 | 编号 | 说明 |
|------|------|------|------|
| user | User | 1 | 用户信息 |
| ... | ... | ... | ... |
```

#### LF-IDL Thrift/IDL 接口定义（对外窗口）

IDL 文件定义了服务对外暴露的所有接口，是前后端、服务间通信的契约。**IDL 变了意味着接口变了**，影响面极大，必须纳入 LF 层。

##### LF-IDL-0 IDL 全局索引（1份，约 50-100 行）

```markdown
# IDL 全局索引

## IDL 文件清单
| IDL 文件 | 职责 | 接口数 | 生成产物位置 |
|---------|------|--------|------------|
| idl/biz_public.thrift | 面向 C 端的公开接口 | 35 | biz/gen/hertz/model/bizPublic/ |
| idl/biz_admin.thrift | 管理后台接口 | 22 | biz/gen/hertz/model/bizAdmin/ |
| idl/biz_internal.thrift | 内部服务间调用 | 10 | biz/gen/hertz/model/bizInternal/ |
| ... | ... | ... | ... |

## 接口分组概览
| 分组 | 接口数 | 说明 |
|------|--------|------|
| 用户相关 | 12 | 注册、登录、信息查询 |
| 订单相关 | 8 | 下单、支付、退款 |
| 合伙人相关 | 6 | 推荐、佣金、提现 |
| ... | ... | ... |
```

##### LF-IDL-N 每个 IDL 文件的详细文档（每份约 60-120 行）

```markdown
# IDL 接口：[idl_file_name]

## 基本信息
- 文件：idl/biz_public.thrift
- 职责：面向 C 端用户的公开 API 接口定义
- 生成工具：Hertz (hz)
- 生成产物：biz/gen/hertz/model/bizPublic/

## Struct 定义
| Struct 名 | 用途 | 核心字段 |
|-----------|------|---------|
| LoginReq | 登录请求 | phone, code, device_id |
| LoginResp | 登录响应 | token, user_info, is_new |
| UserInfo | 用户信息 | user_id, nickname, avatar, vip_level |
| OrderListReq | 订单列表请求 | page, page_size, status |
| ... | ... | ... |

## 接口清单
| 接口路径 | 方法 | 请求 Struct | 响应 Struct | 说明 |
|---------|------|-----------|-----------|------|
| /api/v1/user/login | POST | LoginReq | LoginResp | 手机验证码登录 |
| /api/v1/user/info | GET | UserInfoReq | UserInfo | 获取用户信息 |
| /api/v1/order/list | GET | OrderListReq | OrderListResp | 订单列表 |
| ... | ... | ... | ... | ... |

## Enum / Const 定义
| 名称 | 类型 | 值 | 说明 |
|------|------|---|------|
| OrderStatus | enum | 0=待支付, 1=已支付, 2=已取消 | 订单状态 |
| VipLevel | enum | 0=普通, 1=月卡, 2=年卡 | VIP 等级 |
| ... | ... | ... | ... |

## 被谁实现
| 接口 | Handler 文件 | Service 方法 |
|------|-------------|-------------|
| /api/v1/user/login | biz/handler/user.go | UserService.Login() |
| /api/v1/order/list | biz/handler/order.go | OrderService.ListOrders() |
| ... | ... | ... |

## 最近变更
[从 git log 中提取此 IDL 文件最近 3-5 次变更摘要]
```

#### LF-Migration 变更时间线（1份，精简记录）

```markdown
# 数据库 Migration 时间线

| 序号 | 时间/版本 | 操作 | 说明 |
|------|----------|------|------|
| 001 | 2024-01-15 | CREATE TABLE users | 初始化用户表 |
| 002 | 2024-02-03 | ALTER TABLE users ADD fail_count | 增加登录失败计数 |
| 003 | 2024-03-10 | CREATE TABLE orders | 创建订单表 |
| ... | ... | ... | ... |

## 最近 5 次变更详情
[只对最近的 migration 做详细描述，历史的保留摘要即可]
```

### LF 层与 L0-L3 的关联方式

在 L2/L3 文档中，当方法涉及数据库操作或接口实现时，添加 LF 引用标记：

```markdown
## 数据操作 → LF 引用
- 读取 users 表 → 参见 LF/tables/users.md
- 写入 orders 表 → 参见 LF/tables/orders.md

## 接口实现 → LF 引用
- 实现 /api/v1/user/login → 参见 LF/idl/biz-public.md
```

在 L1 模块概览中，列出该模块操作的所有表和实现的接口：

```markdown
## 数据层依赖
| 表名 | 操作类型 | 关联 LF 文档 |
|------|---------|-------------|
| users | CRUD | LF/tables/users.md |
| login_logs | INSERT | LF/tables/login_logs.md |

## 接口实现
| IDL 文件 | 实现的接口数 | 关联 LF 文档 |
|---------|-----------|-------------|
| biz_public.thrift | 12 | LF/idl/biz-public.md |
```

### L1 模块概览（每份约 50-100 行）

为每个识别出的模块生成一份文档：

```markdown
# 模块概览：[模块名]

## 职责
[2-3 句话描述此模块做什么]

## 对外接口
[此模块暴露给其他模块的主要函数/类/API]

## 依赖关系
- 依赖：[列出此模块 import 的其他内部模块]
- 被依赖：[列出哪些模块 import 了此模块]

## 文件清单
| 文件 | 职责 | 导出项 |
|------|------|--------|
| UserService.ts | 用户增删改查 | UserService class |
| AuthMiddleware.ts | JWT 校验中间件 | authMiddleware fn |
| ... | ... | ... |

## 关键设计决策
[如果发现了有意思的设计模式或架构决策，记录在这里]
```

### L2 文件摘要（每份约 30-80 行）

为每个手写代码文件生成一份文档：

```markdown
# 文件摘要：[文件路径]

## 职责
[一句话说明]

## 导出项
- `UserService` (class) — 用户业务逻辑核心类
- `UserRole` (enum) — 用户角色枚举

## 方法/函数清单
| 名称 | 行号范围 | 一句话说明 | 关键参数 |
|------|---------|-----------|---------|
| authenticate | 45-89 | 密码登录验证 | email, password |
| register | 91-135 | 新用户注册 | userData |
| ... | ... | ... | ... |

## 文件内调用关系
[哪些方法调用了哪些方法，简要说明]

## 依赖
- 内部：[import 了本项目的哪些文件]
- 外部：[import 了哪些第三方包]
```

### L3 方法细节（每份约 20-60 行）

为每个方法/函数生成一份详细文档：

```markdown
# 方法细节：[文件路径]::[方法名]

## 签名
[完整函数签名，含参数类型和返回类型]

## 逻辑流程
1. [第 N 行] 做了什么
2. [第 N 行] 做了什么
3. 条件分支：如果 xxx → ...
4. ...

## 参数说明
| 参数 | 类型 | 说明 | 校验/默认值 |
|------|------|------|------------|
| email | string | 用户邮箱 | validateEmail() |

## 返回值
[说明返回什么，哪些情况返回什么]

## 异常/边界处理
- [什么情况] → 抛出 [什么异常]
- [什么情况] → 返回 null/空

## 调用链
- 调用了：[列出此方法内调用的其他方法]
- 被调用：[列出调用此方法的地方]
```

### 构建顺序和策略

1. **先构建 L0**：扫描目录结构、package.json 等，形成全局认知
2. **紧接着构建 LF**：解析 DB model/schema、proto 定义、migration 文件，建立数据基石
3. **再构建 L1**：基于 L0 中识别的模块划分，逐模块分析，关联 LF 中的表
4. **然后 L2**：逐文件读取，提取结构信息，标注数据操作的 LF 引用
5. **最后 L3**：逐方法深入分析逻辑流程，标注涉及的表和字段

对于 3.6 万行的项目，建议分批处理：
- 每批处理 5-10 个文件
- 每个文件的所有方法一起处理（L2 + L3 同步生成）
- 处理完一个模块后，回顾检查一致性

### 构建完成后

生成 `meta.json`：

```json
{
  "version": "1.0.0",
  "created_at": "2026-03-20T10:00:00Z",
  "last_updated_at": "2026-03-20T10:00:00Z",
  "last_commit": "abc1234",
  "tech_stack": ["TypeScript", "React", "Node.js"],
  "stats": {
    "handwritten_lines": 36000,
    "generated_lines": 310000,
    "foundation_tables": 25,
    "foundation_protos": 3,
    "l0_files": 1,
    "lf_files": 30,
    "l1_files": 8,
    "l2_files": 120,
    "l3_files": 450
  },
  "excluded_dirs": ["node_modules", "dist", "build", ".next"],
  "foundation_sources": {
    "db_models": "dal/model/",
    "db_queries": "dal/query/",
    "proto_files": "proto/",
    "migrations": "migrations/"
  },
  "file_hashes": {
    "src/services/UserService.ts": "sha256:abc123...",
    "src/controllers/AuthController.ts": "sha256:def456..."
  }
}
```

`file_hashes` 记录每个文件的哈希值，用于增量更新时判断文件是否变化。

---

## 第三步：增量更新（update 模式）

当仓库经历了版本更新后，不需要全量重建，只更新变化部分。

### 检测变化

```bash
# 获取上次记录的 commit
LAST_COMMIT=$(cat .repo-memory/meta.json | grep -o '"last_commit": "[^"]*"' | cut -d'"' -f4)

# 获取当前最新 commit
CURRENT_COMMIT=$(git rev-parse HEAD)

# 获取变化的文件列表
git diff --name-only $LAST_COMMIT $CURRENT_COMMIT

# 获取变化的详细信息（方便判断影响范围）
git diff --stat $LAST_COMMIT $CURRENT_COMMIT

# 如果跨越很多版本，也可以看 log
git log --oneline $LAST_COMMIT..$CURRENT_COMMIT
```

### 增量更新策略

根据变化文件的类型和范围，决定更新哪些层级：

| 变化类型 | 影响层级 | 操作 |
|---------|---------|------|
| 文件内容修改（某方法改了逻辑） | L3 + L2 | 重建该文件的 L3，刷新 L2 |
| 新增文件 | L3 + L2 + L1 | 新建 L3/L2，更新所属模块的 L1 |
| 删除文件 | L3 + L2 + L1 | 删除 L3/L2，更新所属模块的 L1 |
| 新增/删除目录（模块级变动） | L3 + L2 + L1 + L0 | 重建相关层，刷新 L0 模块列表 |
| 依赖变化（package.json 等） | L0 | 刷新 L0 的依赖和技术栈信息 |
| 配置变化（env / config） | L0 | 刷新 L0 的配置部分 |
| 重命名/移动文件 | L3 + L2 + L1 | 迁移文档，更新路径引用 |

### 更新流程

1. 获取 diff 文件列表
2. 对每个变化文件，比较 `file_hashes` 确认确实有改动
3. 读取变化文件的新内容
4. **自下而上更新**：先更新 L3（方法细节），再向上冒泡到 L2、L1、L0
5. **如果变化涉及 DB model/proto/migration** → 同步更新 LF 层
6. 更新 `meta.json` 中的 commit、时间戳和 file_hashes
7. 输出更新报告

### 增量更新中的 LF 层处理

| 变化类型 | LF 操作 |
|---------|---------|
| DB model 文件变化（如 gorm/gen 重新生成） | 对比新旧 model，更新 LF/tables/ 对应文档 |
| 新增 migration 文件 | 追加到 LF/migrations/migration-timeline.md |
| IDL 文件变化（.thrift / .proto 修改） | 更新 LF/idl/ 对应文档，检查接口新增/删除/字段变更 |
| IDL 新增接口 | 更新 LF/idl/ 对应文档 + idl-overview.md |
| Proto 文件变化 | 更新 LF/proto/ 对应的服务文档 |
| 新增表 | 新建 LF/tables/xxx.md，更新 LF/db-schema.md |
| 删除表 | 删除对应文档，更新 ER 概览 |

### 更新报告格式

```markdown
# 增量更新报告

## 更新范围
- 上次 commit：abc1234 (2026-03-15)
- 当前 commit：def5678 (2026-03-20)
- 跨越版本：12 commits

## 变化统计
- 修改文件：15 个
- 新增文件：3 个
- 删除文件：1 个

## 文档更新
- LF（基础设施）：更新 2 张表结构 [users, orders]，新增 1 条 migration
- L0（项目全景）：已更新 [依赖变化]
- L1（模块概览）：更新 3 份 [auth, api, utils]
- L2（文件摘要）：更新 15 份，新增 3 份，删除 1 份
- L3（方法细节）：更新 28 份，新增 12 份，删除 4 份

## 关键变更摘要
1. [auth 模块] 新增 OAuth2.0 支持，增加了 OAuthService
2. [api 模块] 重构了 rate limiting 中间件
3. [DB] users 表新增 oauth_provider 字段
4. ...
```

---

## 第四步：查询与辅助开发（模式 C）

当 `.repo-memory/` 已存在，且用户提出开发任务或仓库相关问题时，进入此模式。
**核心原则：记忆文档优先，源码按需精读。**

### 进入模式 C 的前置检查

1. 读取 `meta.json` 获取 `last_commit`
2. 对比当前 HEAD，判断记忆是否过旧：
   - 差距 ≤ 5 commits → 直接使用记忆
   - 差距 > 5 commits → 提示用户"记忆有 N 个版本未同步，建议先更新"，可先跑模式 B 再继续
   - 无法判断（没有 .git）→ 直接使用记忆，提示可能不是最新

### 查询路由

| 问题类型 | 加载层级 | 示例 |
|---------|---------|------|
| "这个项目是干什么的" | L0 | 只读 L0 即可回答 |
| "数据库有哪些表" | LF/db-schema.md | 直接查 LF 全局概览 |
| "users 表有哪些字段" | LF/tables/users.md | 直接查 LF 表文档 |
| "有哪些对外接口" | LF/idl/idl-overview.md | 查 IDL 全局索引 |
| "登录接口的请求参数是什么" | LF/idl/biz-public.md | 查对应 IDL 文件文档 |
| "用户模块依赖了什么" | L0 → L1 | 读 L0 定位模块，读 L1 回答 |
| "UserService 里有什么方法" | L0 → L1 → L2 | 逐层下钻到文件级 |
| "authenticate 方法的逻辑是什么" | L0 → L2 → L3 + LF/tables/users.md | 方法逻辑 + 涉及的表 |
| "为什么登录失败会锁定账户" | L3 + LF/tables/users.md | 方法细节 + 相关字段 |
| "订单和用户是什么关系" | LF/db-schema.md | ER 关系直接回答 |
| "最近一次数据库变更是什么" | LF/migrations/ | 查 migration 时间线 |
| "新加一个接口需要改哪里" | LF/idl/ + L1 + L2 | IDL 定义 + 模块结构 + handler 文件 |

### 开发任务辅助流程

当用户提出开发需求时（如"帮我加一个用户VIP等级功能"），按以下流程使用记忆：

#### 第一步：需求分析（读 L0 + LF）
- 读 L0 了解项目全景、模块划分、核心数据流
- 读 LF/db-schema.md 了解现有数据结构
- 判断需求涉及哪些模块、哪些表

```
用户说："加一个VIP等级功能"
→ 读 L0 → 知道有 user 模块、order 模块、payment 模块
→ 读 LF/db-schema.md → 知道 users 表已有 status 字段，但没有 vip_level
→ 初步判断：需要改 users 表 + user 模块 + 可能关联 order 模块
```

#### 第二步：影响面评估（读 L1 + 相关 LF/tables）
- 读涉及模块的 L1，了解模块内文件和对外接口
- 读涉及表的 LF/tables 文档，了解字段和关联关系
- 判断需要修改/新增哪些文件

```
→ 读 L1/user-module.md → 知道有 UserService、UserController、UserRepo
→ 读 LF/tables/users.md → 知道字段结构、索引、被哪些 Service 使用
→ 判断：需改 UserService（加 VIP 逻辑）、UserController（加接口）、users 表（加字段）
```

#### 第三步：定位具体修改点（读 L2 + L3）
- 读相关文件的 L2，找到要修改的方法
- 读关键方法的 L3，理解现有逻辑
- 在**充分理解现有逻辑后**，才开始写代码

```
→ 读 L2/src--services--UserService.ts.md → 看到方法清单，找到 updateUser()
→ 读 L3/...--updateUser.md → 理解现有更新逻辑的完整流程
→ 现在可以写代码了：知道在哪改、怎么改、不会破坏现有逻辑
```

#### 第四步：写代码 + 同步更新记忆
- 完成开发后，**必须同步更新受影响的记忆文档**
- 新增了方法 → 新建 L3，更新 L2
- 修改了方法 → 更新 L3
- 修改了表结构 → 更新 LF/tables
- 新增了文件 → 新建 L2 + L3，更新 L1
- 更新 meta.json 的 last_commit 和 file_hashes

这一步至关重要——开发完不更新记忆，下次查询就会得到过时信息。

### 常见开发场景速查

| 开发任务 | 读哪些记忆 | 写代码后更新哪些记忆 |
|---------|-----------|-------------------|
| 新增 API 接口 | LF/idl（确认 IDL 定义）→ L1（路由模块）→ L2（Handler）→ LF/tables（涉及的表）| 更新 LF/idl，新建 L3，更新 L2、L1 |
| 修改接口参数/响应 | LF/idl（当前接口定义）→ L2（Handler）→ L3（实现逻辑）| 更新 LF/idl，更新 L3 |
| 修改业务逻辑 | L2（定位方法）→ L3（理解逻辑）| 更新 L3，可能更新 L2 |
| 新增数据库表 | LF/db-schema.md → 相关 LF/tables/ | 新建 LF/tables/xxx.md，更新 db-schema.md |
| 修改表结构 | LF/tables/xxx.md → 搜索"被谁使用" | 更新 LF/tables，检查相关 L3 |
| 新增模块 | L0（了解现有模块划分）| 新建 L1，新建所有 L2/L3，更新 L0 |
| 重构/移动文件 | L1（了解模块结构）→ L2（了解文件职责）| 迁移 L2/L3 路径，更新 L1 |
| 修 bug | L0 → 定位模块 → L2 → L3（找到问题方法）| 更新修改的 L3 |
| 性能优化 | L3（理解热点方法逻辑）→ LF（查询涉及的表和索引）| 更新优化后的 L3 |

### 跨模块问题

当问题涉及多个模块时（如"用户登录的完整链路是什么"），需要：
1. 从 L0 获取数据流概览
2. 加载相关的多个 L1
3. 必要时下钻到关键节点的 L2/L3
4. 加载涉及的 LF/tables 理解数据流转

### 记忆不足时的降级策略

如果记忆文档无法回答某个问题（比如 L3 中没有记录某个细节），可以：
1. 先基于记忆定位到具体文件和行号范围
2. 然后只精读那一小段源码（而不是从头阅读整个文件）
3. 读完后将新发现补充到对应的记忆文档中

这样每次"降级精读"都会让记忆变得更完善。

---

## 重要注意事项

1. **零价值生成代码不建档**：node_modules、dist、build 等目录下的代码完全跳过
2. **高价值生成代码纳入 LF 层**：DB model/query（如 gorm/gen）、protobuf、prisma schema、migration 等是业务基石，必须建档到 LF 层，但用专用的结构化格式（记表结构和字段，不记逐行生成逻辑）
3. **LF 层是横切关注点**：不属于 L0-L3 的层级链，而是任何层级都可能引用的"数据字典"
4. **配置文件特殊处理**：.env、config 文件在 L0 中记录关键项，不生成 L3
5. **测试文件可选**：test/ 目录下的文件可以生成 L2（测试覆盖了什么），L3 按需
6. **文件名编码**：L2/L3 的文件名用 `--` 替代路径分隔符 `/`，避免嵌套目录过深
7. **大文件拆分**：如果单个文件超过 500 行，L2 中标注为"大文件"，L3 分批生成
8. **哈希校验**：增量更新时用 SHA256 校验文件内容，避免无意义的重建
9. **LF 增量更新**：当 ORM 工具重新生成代码时（如表结构变更后 gorm/gen 重跑），需对比新旧生成文件来更新 LF 文档，而不是直接全量重建
10. **OpenSpec 目录跳过**：`openspec/` 整个目录（含 changes/、archive/、specs/）不建档。OpenSpec 的 proposal.md、spec.md、tasks.md 是需求管理文档，不是代码逻辑，不属于仓库记忆的范围。但在模式 C 辅助开发时，如果用户正在使用 OpenSpec 驱动开发（存在 openspec/changes/<change-id>/），可以读取当前 change 的 spec.md 和 tasks.md 来理解需求上下文，再结合记忆文档理解代码现状，两者配合完成开发

### 与 OpenSpec 的协作关系

repo-memory 和 OpenSpec 是互补的，不冲突：

| | OpenSpec | repo-memory |
|---|---------|-------------|
| 关注 | 当前需求要做什么（变更规划） | 整个仓库长什么样（代码认知） |
| 产出 | proposal/spec/tasks（需求级） | L0/L1/L2/L3/LF（仓库级） |
| 生命周期 | 需求开始 → 完成 → archive（短期） | 常驻，随仓库演进（长期） |

典型协作流程：
1. `/openspec-proposal` → 生成需求文档（OpenSpec 负责）
2. `/openspec-apply` → 开始写代码时，repo-memory 提供仓库理解（省去重新读源码）
3. 开发完成 → OpenSpec archive 归档需求，repo-memory 自动更新受影响的记忆文档
