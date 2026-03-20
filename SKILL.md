---
name: repo-memory
description: >
  Build a multi-layer memory system for code repositories (L0 Project Overview → L1 Module Summary
  → L2 File Summary → L3 Method Detail), with support for first-time full indexing and incremental
  updates via git diff. Trigger this skill when the user mentions "repo memory", "code memory",
  "project memory", "repo index", "code index", "code documentation", "repo understanding",
  "help me remember this project", "analyze the whole repo", "understand this codebase",
  "build code archive", "code knowledge base", "incremental update memory", or "refresh code docs".
  Even if the user doesn't explicitly say "memory", trigger this skill whenever the intent is to
  deeply understand and continuously track a code repository.

  [IMPORTANT] This skill is not only for archiving and updating — it also assists development.
  When the user wants to implement new features, fix bugs, refactor, review code, or perform any
  task that requires understanding the codebase, if the .repo-memory directory already exists,
  prefer reading memory docs over re-reading source code. Trigger words include but are not
  limited to: "help me implement", "develop this feature", "modify this", "add an API",
  "fix this bug", "refactor", "optimize", "review code", "write a new module", etc.
  Whenever the user's task involves a repo that has been indexed, trigger this skill in query mode.
---

# Repo Memory — Multi-Layer Codebase Memory System

## Core Concept

This skill builds a **four-layer progressive memory + foundation layer** for code repositories, simulating how a senior engineer understands a project:

```
L0  Project Overview   (1 file)        → "What does this project do?"
L1  Module Summary     (per module)    → "What is this module responsible for?"
L2  File Summary       (per file)      → "What's in this file?"
L3  Method Detail      (per method)    → "What does this method do, line by line?"

LF  Foundation Layer                   → DB table schemas, Protobuf definitions, IDL/Thrift, API schemas, etc.
    The bedrock of all business logic, independent of L0-L3 hierarchy, referenced on demand by any layer.
```

Queries drill down layer by layer, loading only the current layer + target layer's md files — minimal context overhead.
The LF layer is "cross-cutting on demand" — whenever analysis at any layer involves data operations, automatically reference the corresponding LF doc.

## Three Operating Modes

### Mode A: First-Time Full Indexing (init)
Scan the entire repository and generate all memory documents from L0 through L3.

### Mode B: Incremental Update (update)
Detect changed files via git diff and only rebuild affected layer documents.

### Mode C: Query & Development Assistance (query)
When `.repo-memory/` already exists and the user requests a development task, enter this mode.
Read memory docs to quickly understand the codebase instead of re-reading source files.

**Auto mode detection logic:**
1. `.repo-memory/` doesn't exist → Mode A (init)
2. `.repo-memory/` exists + user says "update memory" / "refresh docs" → Mode B (update)
3. `.repo-memory/` exists + user says "implement feature" / "fix bug" / "add API" → Mode C (query)
4. `.repo-memory/` exists + Mode C detects stale memory → run Mode B first, then enter Mode C

### Auto-Update Mechanism (Hooks)

Through Claude Code's Hook system, memory updates are **fully automatic** — no manual triggering needed:

**SessionStart Hook (when conversation starts):**
- Automatically runs `scripts/auto-check.sh`
- Checks the gap between `.repo-memory/meta.json`'s `last_commit` and current HEAD
- Three-tier response based on staleness:
    - ≤ 3 commits (low) → hint that memory is slightly stale, update on demand
    - 4-10 commits (medium) → recommend updating soon
    - > 10 commits (high) → proactively run incremental update before handling user's task
- If memory is up to date → completely silent, no interruption

**Stop Hook (when conversation ends):**
- Automatically runs `scripts/post-task-check.sh`
- Detects if the conversation produced code changes (git diff)
- If changes exist but memory not synced → remind Claude to update corresponding L2/L3/LF docs

**Installation:** Merge contents of `hooks-config.json` into the project's `.claude/settings.local.json`.

---

## Step 1: Environment Setup

1. Confirm repository path (user upload or specified path)
2. Check if `.repo-memory/` directory exists:
    - Exists → enter incremental update mode
    - Doesn't exist → enter first-time indexing mode
3. Detect tech stack (via package.json / requirements.txt / pom.xml / go.mod / Cargo.toml, etc.)
4. **Classify code into three categories:**

### Code Classification Strategy (Critical!)

Not all generated code should be skipped. Classify by value into three categories:

| Category | Treatment | Examples |
|----------|----------|---------|
| **Handwritten code** | Full indexing L0-L3 | Business code under src/ |
| **High-value generated code** | Include in LF foundation layer with specialized format | gorm/gen models, protobuf, prisma schema, GraphQL schema, OpenAPI spec |
| **Zero-value generated code** | Skip entirely | node_modules, dist, build, .next |
| **Non-code project files** | Skip (requirement management, not code logic) | openspec/archive/, openspec/changes/, openspec/specs/ |

#### High-Value Generated Code Whitelist (Auto-detected)

The following generated code is the bedrock of business logic — **must be included in the LF layer:**

**Database model classes** (define table structures and query capabilities):
- Go: gorm/gen generated `model/` and `query/` directories, ent generated `ent/` directory, sqlc generated files
- Python: SQLAlchemy auto-generated models, Django migration files
- Java: MyBatis Generator entity/mapper, JPA metamodel
- TypeScript: Prisma Client (`prisma/client/`), TypeORM entities, Drizzle schema
- Rust: diesel generated schema.rs, sea-orm entities

**IDL interface definitions** (external-facing window, defines all exposed service interfaces):
- Thrift IDL source files (`idl/*.thrift`) — **source files themselves are high-value assets, not just generated artifacts**
- Protobuf source files (`proto/*.proto`)

**Inter-service communication contracts** (IDL/Proto generated artifacts):
- protobuf generated .pb.go / .pb.ts / _pb2.py
- gRPC generated _grpc.pb.go / _grpc.ts
- Thrift generated model code (e.g., Hertz framework's `biz/gen/`)
- GraphQL generated type definitions
- OpenAPI/Swagger generated client/server stubs

**Infrastructure as code** (defines infrastructure):
- Database migration files (SQL or framework format)
- Terraform / Pulumi generated state-related code

#### Detection Commands

```bash
# Check if memory already exists
ls -la <repo_path>/.repo-memory/ 2>/dev/null

# Detect tech stack
ls <repo_path>/package.json <repo_path>/requirements.txt <repo_path>/pom.xml <repo_path>/go.mod <repo_path>/Cargo.toml 2>/dev/null

# Scan handwritten code
find <repo_path> -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" -o -name "*.java" -o -name "*.go" -o -name "*.rs" \) \
  ! -path "*/node_modules/*" ! -path "*/dist/*" ! -path "*/build/*" ! -path "*/.next/*" ! -path "*/__pycache__/*" \
  ! -path "*/openspec/*" \
  | head -20

# Scan high-value generated code (Go + gorm/gen example)
find <repo_path> -type f \( -name "*.gen.go" -o -path "*/model/*.go" -o -path "*/query/*.go" \) | head -20
find <repo_path> -type f -name "*.pb.go" | head -20
find <repo_path> -type f -name "*.sql" -path "*/migration*" | head -20

# Scan IDL source files (Thrift / Proto — external interface definitions)
find <repo_path> -type f \( -name "*.thrift" -o -name "*.proto" \) | head -20
# Scan IDL generated artifact directories
ls -la <repo_path>/biz/gen/ 2>/dev/null
```

---

## Step 2: First-Time Full Indexing (init mode)

Build layers in order: L0 → LF → L1 → L2 → L3.

### Before building, read the reference docs

Based on detected tech stack, read the corresponding parsing reference:
- General rules: `references/parsing-guide.md`

### Directory Structure

All memory documents are stored under `.repo-memory/` in the repository root:

```
.repo-memory/
├── meta.json                    # Metadata (version, last updated commit, tech stack, etc.)
├── L0-project.md                # Project overview
├── LF/                          # Foundation layer
│   ├── db-schema.md             # DB global ER overview
│   ├── tables/                  # One doc per table
│   │   ├── users.md
│   │   ├── orders.md
│   │   └── ...
│   ├── idl/                     # Thrift / Protobuf interface definitions (external window)
│   │   ├── idl-overview.md      # IDL global index
│   │   ├── biz-public.md        # One doc per IDL file
│   │   ├── biz-admin.md
│   │   └── ...
│   ├── proto/                   # Protobuf / gRPC service definitions
│   │   ├── user-service.md
│   │   └── ...
│   ├── migrations/              # Migration change timeline
│   │   └── migration-timeline.md
│   └── api-contracts/           # OpenAPI / GraphQL schema
│       └── ...
├── L1/
│   ├── auth-module.md           # Module summary
│   ├── api-module.md
│   └── ...
├── L2/
│   ├── src--services--UserService.ts.md    # File summary (path separators replaced with --)
│   ├── src--controllers--AuthController.ts.md
│   └── ...
└── L3/
    ├── src--services--UserService.ts--authenticate.md  # Method detail
    ├── src--services--UserService.ts--register.md
    └── ...
```

### L0 Project Overview (~100-200 lines)

Scan the entire repository and generate one overview document containing:

```markdown
# Project Overview: [project_name]

## Basic Info
- Tech stack: [frameworks/languages/major dependencies]
- Handwritten code: [x] lines ([y] files)
- Generated code: [x] lines (marked as skipped)
- Last commit: [commit hash + date]

## Directory Structure Overview
[Show only top 2-3 levels of core directories like src/]

## Module Map
| Module | Path | One-line description | Core file count |
|--------|------|---------------------|----------------|
| auth   | src/modules/auth | User authentication & authorization | 8 |
| ...    | ...  | ...                 | ...            |

## Core Data Flow
[Describe main request processing chain, e.g.:]
Request → Router → Middleware(auth) → Controller → Service → Repository → DB

## External Dependencies
[List key third-party services/APIs/databases]

## Deployment & Configuration
[Brief deployment method, environment variable groups]

## Foundation Layer Index
| Type | Count | Doc Location |
|------|-------|-------------|
| DB tables | [x] | LF/tables/ |
| IDL interface files | [x] | LF/idl/ |
| Protobuf services | [x] | LF/proto/ |
| Migrations | [x] | LF/migrations/ |
```

### LF Foundation Layer

**This is the bedrock of all business logic.** The LF layer is independent of the L0-L3 hierarchy — any layer can cross-reference LF documents when analyzing data operations.

Build order: **Build LF after L0 but before L1**, because subsequent module and method analysis needs to know the data structures.

#### LF-0 DB Global ER Overview (1 file, ~100-200 lines)

```markdown
# Database Global Overview

## Database Info
- Type: [MySQL/PostgreSQL/MongoDB/...]
- ORM/generator: [gorm/gen / prisma / ent / ...]
- Generated code location: [dal/query/ and dal/model/]

## Table List
| Table | Description | Core field count | Related tables |
|-------|------------|-----------------|---------------|
| users | User table | 12 | orders, profiles |
| orders | Order table | 18 | users, products, payments |
| ... | ... | ... | ... |

## ER Relationship Diagram (text)
users 1──N orders (one user has many orders)
orders N──1 products (many orders reference one product)
orders 1──1 payments (one order has one payment)
users 1──1 profiles (one-to-one user profile)
...

## Core Business Entity Relationships
[Concise description of core domain model relationships]
```

#### LF-Table Per-Table Detail Doc (each ~40-80 lines)

```markdown
# Table Schema: [table_name]

## Basic Info
- Table: users
- Description: Main user table, stores account and auth info
- Generated from: dal/model/users.gen.go
- Corresponding query object: dal/query/users.gen.go

## Field List
| Field | Type | Description | Constraints | Default |
|-------|------|------------|-------------|---------|
| id | bigint | Primary key | PK, AUTO_INCREMENT | - |
| email | varchar(255) | Email | UNIQUE, NOT NULL | - |
| password_hash | varchar(255) | Password hash | NOT NULL | - |
| status | tinyint | Status (0=disabled, 1=active, 2=locked) | NOT NULL | 1 |
| fail_count | int | Consecutive login failure count | NOT NULL | 0 |
| created_at | datetime | Created time | NOT NULL | CURRENT_TIMESTAMP |
| updated_at | datetime | Updated time | NOT NULL | CURRENT_TIMESTAMP |
| deleted_at | datetime | Soft delete time | NULL | NULL |

## Indexes
| Index Name | Fields | Type | Description |
|-----------|--------|------|------------|
| PRIMARY | id | PRIMARY | - |
| idx_email | email | UNIQUE | Email unique index |
| idx_status | status | NORMAL | Query by status |
| idx_deleted_at | deleted_at | NORMAL | Soft delete filter |

## Relationships
- users.id → orders.user_id (one-to-many: one user, many orders)
- users.id → profiles.user_id (one-to-one: user profile)
- users.id → login_logs.user_id (one-to-many: login logs)

## gorm/gen Generated Query Capabilities
[Extract key custom query methods from query files]
| Method | Description | Parameters |
|--------|------------|-----------|
| FindByEmail | Find user by email | email string |
| FindActiveUsers | Find all active users | - |
| UpdateFailCount | Update failure count | id int64, count int |
| ... | ... | ... |

## Used By
- UserService.authenticate() — query + update fail_count
- UserService.register() — insert new record
- AdminService.listUsers() — query list
```

#### LF-Proto Protobuf/gRPC Service Definitions (if project uses them)

```markdown
# Proto Service: [service_name]

## Source Files
- .proto source: proto/user_service.proto
- Generated code: pb/user_service.pb.go, pb/user_service_grpc.pb.go

## Service Definition
| RPC Method | Request Type | Response Type | Description |
|-----------|-------------|--------------|------------|
| GetUser | GetUserRequest | GetUserResponse | Get user info |
| ListUsers | ListUsersRequest | ListUsersResponse | User list |
| ... | ... | ... | ... |

## Core Message Definitions
### GetUserRequest
| Field | Type | Number | Description |
|-------|------|--------|------------|
| user_id | int64 | 1 | User ID |

### GetUserResponse
| Field | Type | Number | Description |
|-------|------|--------|------------|
| user | User | 1 | User info |
| ... | ... | ... | ... |
```

#### LF-IDL Thrift/IDL Interface Definitions (External Window)

IDL files define all externally exposed service interfaces — the contract between frontend/backend and between services. **When IDL changes, interfaces change**, with massive impact. Must be included in the LF layer.

##### LF-IDL-0 IDL Global Index (1 file, ~50-100 lines)

```markdown
# IDL Global Index

## IDL File List
| IDL File | Responsibility | Endpoint Count | Generated Output Location |
|---------|---------------|---------------|--------------------------|
| idl/biz_public.thrift | Public C-facing interfaces | 35 | biz/gen/hertz/model/bizPublic/ |
| idl/biz_admin.thrift | Admin panel interfaces | 22 | biz/gen/hertz/model/bizAdmin/ |
| idl/biz_internal.thrift | Internal inter-service calls | 10 | biz/gen/hertz/model/bizInternal/ |
| ... | ... | ... | ... |

## Interface Group Overview
| Group | Count | Description |
|-------|-------|------------|
| User-related | 12 | Registration, login, info queries |
| Order-related | 8 | Ordering, payment, refund |
| Partner-related | 6 | Referral, commission, withdrawal |
| ... | ... | ... |
```

##### LF-IDL-N Per-IDL File Detail Doc (each ~60-120 lines)

```markdown
# IDL Interface: [idl_file_name]

## Basic Info
- File: idl/biz_public.thrift
- Responsibility: Public API interface definitions for C-facing users
- Generator: Hertz (hz)
- Generated output: biz/gen/hertz/model/bizPublic/

## Struct Definitions
| Struct Name | Purpose | Core Fields |
|------------|---------|------------|
| LoginReq | Login request | phone, code, device_id |
| LoginResp | Login response | token, user_info, is_new |
| UserInfo | User info | user_id, nickname, avatar, vip_level |
| OrderListReq | Order list request | page, page_size, status |
| ... | ... | ... |

## Endpoint List
| Path | Method | Request Struct | Response Struct | Description |
|------|--------|---------------|----------------|------------|
| /api/v1/user/login | POST | LoginReq | LoginResp | Phone verification code login |
| /api/v1/user/info | GET | UserInfoReq | UserInfo | Get user info |
| /api/v1/order/list | GET | OrderListReq | OrderListResp | Order list |
| ... | ... | ... | ... | ... |

## Enum / Const Definitions
| Name | Type | Values | Description |
|------|------|--------|------------|
| OrderStatus | enum | 0=pending, 1=paid, 2=cancelled | Order status |
| VipLevel | enum | 0=free, 1=monthly, 2=annual | VIP level |
| ... | ... | ... | ... |

## Implemented By
| Endpoint | Handler File | Service Method |
|----------|-------------|---------------|
| /api/v1/user/login | biz/handler/user.go | UserService.Login() |
| /api/v1/order/list | biz/handler/order.go | OrderService.ListOrders() |
| ... | ... | ... |

## Recent Changes
[Extract last 3-5 changes to this IDL file from git log]
```

#### LF-Migration Change Timeline (1 file, concise record)

```markdown
# Database Migration Timeline

| # | Date/Version | Operation | Description |
|---|-------------|-----------|------------|
| 001 | 2024-01-15 | CREATE TABLE users | Initialize user table |
| 002 | 2024-02-03 | ALTER TABLE users ADD fail_count | Add login failure counter |
| 003 | 2024-03-10 | CREATE TABLE orders | Create order table |
| ... | ... | ... | ... |

## Last 5 Changes Detail
[Only describe recent migrations in detail; keep historical ones as summaries]
```

### LF Layer Cross-References with L0-L3

In L2/L3 docs, when methods involve database operations or interface implementations, add LF reference markers:

```markdown
## Data Operations → LF Reference
- Read users table → see LF/tables/users.md
- Write orders table → see LF/tables/orders.md

## Interface Implementation → LF Reference
- Implements /api/v1/user/login → see LF/idl/biz-public.md
```

In L1 module summaries, list all tables and interfaces the module operates on:

```markdown
## Data Layer Dependencies
| Table | Operation Type | LF Doc |
|-------|---------------|--------|
| users | CRUD | LF/tables/users.md |
| login_logs | INSERT | LF/tables/login_logs.md |

## Interface Implementations
| IDL File | Endpoints Implemented | LF Doc |
|---------|---------------------|--------|
| biz_public.thrift | 12 | LF/idl/biz-public.md |
```

### L1 Module Summary (each ~50-100 lines)

Generate one document per identified module:

```markdown
# Module Summary: [module_name]

## Responsibility
[2-3 sentences describing what this module does]

## External Interface
[Main functions/classes/APIs this module exposes to other modules]

## Dependencies
- Depends on: [list internal modules this module imports]
- Depended by: [list modules that import this module]

## File List
| File | Responsibility | Exports |
|------|---------------|---------|
| UserService.ts | User CRUD | UserService class |
| AuthMiddleware.ts | JWT verification middleware | authMiddleware fn |
| ... | ... | ... |

## Key Design Decisions
[Record interesting design patterns or architectural decisions found here]
```

### L2 File Summary (each ~30-80 lines)

Generate one document per handwritten code file:

```markdown
# File Summary: [file_path]

## Responsibility
[One-line description]

## Exports
- `UserService` (class) — Core user business logic class
- `UserRole` (enum) — User role enumeration

## Method/Function List
| Name | Line Range | One-line Description | Key Parameters |
|------|-----------|---------------------|---------------|
| authenticate | 45-89 | Password login verification | email, password |
| register | 91-135 | New user registration | userData |
| ... | ... | ... | ... |

## Internal Call Relationships
[Which methods call which methods, brief description]

## Dependencies
- Internal: [which project files are imported]
- External: [which third-party packages are imported]
```

### L3 Method Detail (each ~20-60 lines)

Generate one detailed document per method/function:

```markdown
# Method Detail: [file_path]::[method_name]

## Signature
[Full function signature with parameter types and return type]

## Logic Flow
1. [Line N] Does what
2. [Line N] Does what
3. Conditional branch: if xxx → ...
4. ...

## Parameters
| Parameter | Type | Description | Validation/Default |
|-----------|------|------------|-------------------|
| email | string | User email | validateEmail() |

## Return Value
[Describe what is returned and under what conditions]

## Error/Edge Case Handling
- [condition] → throws [exception]
- [condition] → returns null/empty

## Call Chain
- Calls: [list methods called within this method]
- Called by: [list callers of this method]
```

### Build Order and Strategy

1. **Build L0 first**: scan directory structure, package.json, etc. to form global understanding
2. **Build LF next**: parse DB model/schema, IDL/proto definitions, migration files to establish data foundation
3. **Then build L1**: based on module divisions identified in L0, analyze per module, cross-reference LF tables
4. **Then L2**: read each file, extract structural info, annotate LF references for data operations
5. **Finally L3**: deep-dive into each method's logic flow, annotate involved tables and fields

For a ~36K-line project, recommend batch processing:
- Process 5-10 files per batch
- Process all methods of a file together (generate L2 + L3 simultaneously)
- After completing a module, review for consistency

### After Build Completes

Generate `meta.json`:

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

`file_hashes` records each file's hash for determining actual changes during incremental updates.

---

## Step 3: Incremental Update (update mode)

After the repository has undergone version updates, no full rebuild needed — only update changed parts.

### Detect Changes

```bash
# Get last recorded commit
LAST_COMMIT=$(cat .repo-memory/meta.json | grep -o '"last_commit": "[^"]*"' | cut -d'"' -f4)

# Get current latest commit
CURRENT_COMMIT=$(git rev-parse HEAD)

# Get changed file list
git diff --name-only $LAST_COMMIT $CURRENT_COMMIT

# Get detailed change info (for impact assessment)
git diff --stat $LAST_COMMIT $CURRENT_COMMIT

# If spanning many versions, check log
git log --oneline $LAST_COMMIT..$CURRENT_COMMIT
```

### Incremental Update Strategy

Based on the type and scope of changes, determine which layers to update:

| Change Type | Affected Layers | Action |
|------------|----------------|--------|
| File content modified (method logic changed) | L3 + L2 | Rebuild that file's L3, refresh L2 |
| New file added | L3 + L2 + L1 | Create L3/L2, update parent module's L1 |
| File deleted | L3 + L2 + L1 | Delete L3/L2, update parent module's L1 |
| Directory added/removed (module-level change) | L3 + L2 + L1 + L0 | Rebuild related layers, refresh L0 module list |
| Dependency change (package.json etc.) | L0 | Refresh L0 dependency and tech stack info |
| Config change (env / config) | L0 | Refresh L0 configuration section |
| File renamed/moved | L3 + L2 + L1 | Migrate docs, update path references |

### Update Flow

1. Get diff file list
2. For each changed file, compare `file_hashes` to confirm actual change
3. Read changed file's new content
4. **Update bottom-up**: update L3 (method details) first, then bubble up to L2, L1, L0
5. **If changes involve DB model/proto/migration/IDL** → also update LF layer
6. Update `meta.json` commit, timestamp, and file_hashes
7. Output update report

### LF Layer Handling During Incremental Updates

| Change Type | LF Action |
|------------|----------|
| DB model file changed (e.g., gorm/gen regenerated) | Compare old/new model, update LF/tables/ corresponding doc |
| New migration file added | Append to LF/migrations/migration-timeline.md |
| IDL file changed (.thrift / .proto modified) | Update LF/idl/ corresponding doc, check for added/removed/changed interfaces |
| New IDL endpoint added | Update LF/idl/ corresponding doc + idl-overview.md |
| Proto file changed | Update LF/proto/ corresponding service doc |
| New table added | Create LF/tables/xxx.md, update LF/db-schema.md |
| Table deleted | Delete corresponding doc, update ER overview |

### Update Report Format

```markdown
# Incremental Update Report

## Update Scope
- Last commit: abc1234 (2026-03-15)
- Current commit: def5678 (2026-03-20)
- Spanning: 12 commits

## Change Statistics
- Modified files: 15
- Added files: 3
- Deleted files: 1

## Document Updates
- LF (Foundation): Updated 2 table schemas [users, orders], added 1 migration
- L0 (Project Overview): Updated [dependency changes]
- L1 (Module Summaries): Updated 3 [auth, api, utils]
- L2 (File Summaries): Updated 15, added 3, deleted 1
- L3 (Method Details): Updated 28, added 12, deleted 4

## Key Change Summary
1. [auth module] Added OAuth2.0 support, new OAuthService
2. [api module] Refactored rate limiting middleware
3. [DB] users table added oauth_provider field
4. ...
```

---

## Step 4: Query & Development Assistance (Mode C)

When `.repo-memory/` exists and the user requests a development task or codebase question, enter this mode.
**Core principle: memory docs first, source code on demand.**

### Pre-Check on Entering Mode C

1. Read `meta.json` to get `last_commit`
2. Compare with current HEAD to check if memory is stale:
    - Gap ≤ 5 commits → use memory directly
    - Gap > 5 commits → suggest "memory is N versions behind, recommend updating first", can run Mode B then continue
    - Cannot determine (no .git) → use memory directly, note it may not be current

### Query Routing

| Question Type | Layers to Load | Example |
|--------------|---------------|---------|
| "What does this project do?" | L0 | Read L0 only |
| "What tables are in the database?" | LF/db-schema.md | Direct LF global overview |
| "What fields does the users table have?" | LF/tables/users.md | Direct LF table doc |
| "What external interfaces exist?" | LF/idl/idl-overview.md | IDL global index |
| "What are the login endpoint's request params?" | LF/idl/biz-public.md | Corresponding IDL file doc |
| "What does the user module depend on?" | L0 → L1 | Read L0 to locate module, read L1 to answer |
| "What methods are in UserService?" | L0 → L1 → L2 | Drill down to file level |
| "What's the logic of the authenticate method?" | L0 → L2 → L3 + LF/tables/users.md | Method logic + involved tables |
| "Why does failed login lock the account?" | L3 + LF/tables/users.md | Method detail + related fields |
| "What's the relationship between orders and users?" | LF/db-schema.md | ER relationships answer directly |
| "What was the last database change?" | LF/migrations/ | Migration timeline |
| "Where do I need to modify to add a new endpoint?" | LF/idl/ + L1 + L2 | IDL definition + module structure + handler file |

### Development Task Assistance Flow

When the user requests a development task (e.g., "add a user VIP level feature"), follow this flow using memory:

#### Step 1: Requirement Analysis (read L0 + LF)
- Read L0 for project overview, module map, core data flow
- Read LF/db-schema.md for existing data structures
- Determine which modules and tables the requirement involves

```
User says: "Add a VIP level feature"
→ Read L0 → know there's a user module, order module, payment module
→ Read LF/db-schema.md → users table has status field but no vip_level
→ Initial assessment: need to modify users table + user module + possibly order module
```

#### Step 2: Impact Assessment (read L1 + relevant LF/tables)
- Read involved modules' L1 to understand files and external interfaces
- Read involved tables' LF/tables docs for fields and relationships
- Determine which files need modification/creation

```
→ Read L1/user-module.md → know there's UserService, UserController, UserRepo
→ Read LF/tables/users.md → know field structure, indexes, which Services use it
→ Assessment: need to modify UserService (add VIP logic), UserController (add endpoint), users table (add field)
```

#### Step 3: Locate Specific Modification Points (read L2 + L3)
- Read relevant files' L2 to find methods to modify
- Read key methods' L3 to understand existing logic
- **Only start writing code after fully understanding existing logic**

```
→ Read L2/src--services--UserService.ts.md → see method list, find updateUser()
→ Read L3/...--updateUser.md → understand complete existing update logic flow
→ Now ready to code: know where to change, how to change, won't break existing logic
```

#### Step 4: Write Code + Sync Update Memory
- After development, **must sync update affected memory documents**
- Added a method → create L3, update L2
- Modified a method → update L3
- Modified table structure → update LF/tables
- Added a file → create L2 + L3, update L1
- Update meta.json's last_commit and file_hashes

This step is critical — not updating memory after development means stale info on next query.

### Common Development Scenario Quick Reference

| Development Task | Which Memory to Read | Which Memory to Update After Coding |
|-----------------|---------------------|-----------------------------------|
| Add new API endpoint | LF/idl (confirm IDL definition) → L1 (routing module) → L2 (Handler) → LF/tables (involved tables) | Update LF/idl, create L3, update L2, L1 |
| Modify endpoint params/response | LF/idl (current interface definition) → L2 (Handler) → L3 (implementation logic) | Update LF/idl, update L3 |
| Modify business logic | L2 (locate method) → L3 (understand logic) | Update L3, possibly update L2 |
| Add new DB table | LF/db-schema.md → related LF/tables/ | Create LF/tables/xxx.md, update db-schema.md |
| Modify table structure | LF/tables/xxx.md → search "Used By" | Update LF/tables, check related L3 |
| Add new module | L0 (understand existing module layout) | Create L1, create all L2/L3, update L0 |
| Refactor/move files | L1 (understand module structure) → L2 (understand file responsibility) | Migrate L2/L3 paths, update L1 |
| Fix bug | L0 → locate module → L2 → L3 (find problem method) | Update modified L3 |
| Performance optimization | L3 (understand hot method logic) → LF (query involved tables and indexes) | Update optimized L3 |

### Cross-Module Questions

When a question spans multiple modules (e.g., "what's the complete login flow?"):
1. Get data flow overview from L0
2. Load relevant L1 modules
3. Drill down to key L2/L3 nodes as needed
4. Load relevant LF/tables to understand data flow

### Fallback Strategy When Memory Is Insufficient

If memory docs cannot answer a question (e.g., L3 doesn't record a specific detail):
1. Use memory to locate the specific file and line number range
2. Then only read that small section of source code (not the entire file)
3. After reading, supplement the findings into the corresponding memory doc

Each "fallback read" makes the memory more complete over time.

---

## Important Notes

1. **Zero-value generated code is not indexed**: node_modules, dist, build, etc. are completely skipped
2. **High-value generated code goes into LF layer**: DB model/query (e.g., gorm/gen), protobuf, prisma schema, migrations, etc. are business bedrock — must be indexed into LF layer using specialized structured format (record table structures and fields, not line-by-line generated logic)
3. **LF layer is a cross-cutting concern**: not part of the L0-L3 hierarchy chain, but a "data dictionary" that any layer may reference
4. **Config files get special treatment**: .env, config files are recorded as key items in L0, no L3 generated
5. **Test files are optional**: test/ directory files can generate L2 (what's tested), L3 on demand
6. **Filename encoding**: L2/L3 filenames use `--` to replace path separator `/`, avoiding excessive directory nesting
7. **Large file splitting**: if a single file exceeds 500 lines, mark as "large file" in L2, generate L3 in batches
8. **Hash verification**: use SHA256 to verify file content during incremental updates, avoid unnecessary rebuilds
9. **LF incremental updates**: when ORM tools regenerate code (e.g., gorm/gen re-run after schema change), compare old and new generated files to update LF docs, don't blindly do a full rebuild
10. **OpenSpec directories are skipped**: the entire `openspec/` directory (including changes/, archive/, specs/) is not indexed. OpenSpec's proposal.md, spec.md, tasks.md are requirement management documents, not code logic — they don't belong in repo memory scope. However, in Mode C development assistance, if the user is using OpenSpec-driven development (openspec/changes/<change-id>/ exists), you may read the current change's spec.md and tasks.md to understand requirement context, then combine with memory docs to understand code state — both work together to complete development

### Collaboration with OpenSpec

repo-memory and OpenSpec are complementary, not conflicting:

| | OpenSpec | repo-memory |
|---|---------|-------------|
| Focus | What to change (change planning) | What the code looks like (code knowledge) |
| Output | proposal/spec/tasks (requirement-level) | L0/L1/L2/L3/LF (repository-level) |
| Lifecycle | Feature start → complete → archive (short-term) | Persistent, evolves with repository (long-term) |

Typical collaboration flow:
1. `/openspec-proposal` → generate requirement documents (OpenSpec's job)
2. `/openspec-apply` → when coding starts, repo-memory provides codebase understanding (skip re-reading source code)
3. Development complete → OpenSpec archives the requirement, repo-memory auto-updates affected memory documents
