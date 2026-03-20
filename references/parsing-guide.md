# 代码解析参考指南

本文档指导如何从不同技术栈的代码中提取结构信息，用于生成各层级记忆文档。

---

## 通用解析原则

### 什么算"一个方法/函数"

以下都应该生成独立的 L3 文档：
- 类中的方法（含 constructor）
- 顶层函数/箭头函数（含 export 的）
- React 组件函数（含 hooks 中的自定义 hook）
- 中间件函数
- 路由处理函数
- 回调函数（如果有独立的业务逻辑，超过 10 行）

以下**不需要**独立 L3：
- getter / setter（除非包含复杂逻辑）
- 纯类型定义 / interface / enum（记录在 L2 即可）
- 常量定义（记录在 L2 即可）
- 1-3 行的简单工具函数（在 L2 中一句话说明即可）

### 模块识别策略

模块划分优先级：
1. **显式目录结构**：src/modules/、src/features/、packages/ 等清晰的分模块目录
2. **领域分组**：src/services/ + src/controllers/ + src/repositories/ 中的同名文件归为一个模块
3. **功能聚类**：没有明确目录时，按功能相关性聚类（如所有 auth 相关文件为一个模块）

### 生成代码三分类（关键！）

**不是所有生成代码都该跳过。** 按业务价值分为三类：

#### 零价值生成代码（完全跳过，不建任何层级）
```
# 依赖
node_modules/  .pnpm/  

# 构建产物
dist/  build/  .next/  out/  coverage/  .output/  .nuxt/

# 运行时缓存
__pycache__/  .venv/  venv/  env/  .tox/  .mypy_cache/
target/  bin/  obj/

# 第三方源码
vendor/  (Go/PHP, 除非是项目 fork 的定制版本)

# IDE / 工具
.idea/  .vscode/  .git/

# 需求管理文档（OpenSpec 等）
openspec/  (proposal/spec/tasks 是需求文档，不是代码逻辑)

# 锁文件
package-lock.json  yarn.lock  pnpm-lock.yaml
Pipfile.lock  poetry.lock  Cargo.lock  go.sum
```

#### 高价值生成代码（纳入 LF 基础设施层，用结构化格式记录）

这些是业务逻辑的基石，虽然是工具生成的，但定义了数据结构和服务契约。
**不需要逐行记忆生成逻辑，而是提取结构化信息（表、字段、类型、关系、接口）。**

```
# 数据库模型（定义了"有哪些表，表里有哪些字段"）
Go:     gorm/gen → model/*.gen.go, query/*.gen.go
        ent → ent/schema/, ent/client.go, ent/*.go
        sqlc → db/*.sql.go
Python: SQLAlchemy → models/, alembic/versions/
        Django → */models.py, */migrations/
Java:   MyBatis Generator → entity/, mapper/
        JPA → entity/, metamodel/
TypeScript: Prisma → prisma/schema.prisma, @prisma/client/
            TypeORM → entity/
            Drizzle → schema/
Rust:   diesel → schema.rs
        sea-orm → entity/

# 服务间通信契约（定义了"服务之间怎么通信"）
protobuf:  *.pb.go, *.pb.ts, *_pb2.py, *.pb.h
gRPC:      *_grpc.pb.go, *_grpc.ts
Thrift:    gen-*/ 目录
GraphQL:   __generated__/graphql.ts, *.graphql.ts
OpenAPI:   generated client/server stubs

# 数据库变更历史（定义了"数据结构怎么演进的"）
migrations/  migrate/  alembic/versions/
*.up.sql  *.down.sql
```

#### 低价值生成代码（可选记录，在 L0 中标注存在即可）
```
# 类型声明（有一定参考价值但不是核心）
*.d.ts（自动生成的类型声明）
swagger-ui 静态文件

# 测试 fixture / mock 数据
testdata/generated/  fixtures/generated/
```

### 如何区分"高价值"和"零价值"的经验法则

问自己一个问题：**如果我不知道这份生成代码的内容，我能看懂上层业务代码吗？**
- "不知道 users 表有哪些字段" → 看不懂 UserService → **高价值，必须记**
- "不知道 node_modules 里 lodash 怎么实现的" → 不影响业务理解 → **零价值，跳过**

---

## TypeScript / JavaScript 解析

### 识别方法
```
// 类方法
class Foo {
  methodName(params): ReturnType { ... }
  async methodName(params): Promise<ReturnType> { ... }
  static methodName(params) { ... }
  private methodName(params) { ... }
  get propName() { ... }
  set propName(val) { ... }
}

// 顶层函数
export function funcName(params): ReturnType { ... }
export const funcName = (params): ReturnType => { ... }
export default function(params) { ... }

// React 组件
export function ComponentName(props: Props) { return <JSX> }
export const ComponentName: React.FC<Props> = (props) => { ... }

// 中间件
export const middlewareName = (req, res, next) => { ... }
app.use((req, res, next) => { ... })

// 路由
router.get('/path', handlerFn)
app.post('/path', (req, res) => { ... })
```

### 模块边界识别
- `src/modules/` 或 `src/features/` 下的每个子目录 = 一个模块
- NestJS：每个 `*.module.ts` 定义一个模块
- Next.js：`app/` 下的路由组，`lib/` 下的功能分组

### 依赖提取
```
import { X } from './relative/path'     → 内部依赖
import { X } from '@/path'              → 内部依赖（路径别名）
import { X } from 'package-name'        → 外部依赖
require('package-name')                  → 外部依赖
```

---

## Python 解析

### 识别方法
```python
# 类方法
class Foo:
    def method_name(self, params) -> ReturnType: ...
    async def method_name(self, params): ...
    @classmethod
    def method_name(cls, params): ...
    @staticmethod
    def method_name(params): ...
    @property
    def prop_name(self): ...

# 顶层函数
def func_name(params) -> ReturnType: ...
async def func_name(params): ...

# 装饰器路由（Flask/FastAPI）
@app.route('/path')
def handler(): ...

@router.get('/path')
async def handler(): ...
```

### 模块边界识别
- 包含 `__init__.py` 的目录 = 一个包/模块
- Django：每个 app 目录 = 一个模块
- FastAPI：`routers/` 下的每个文件或目录

### 依赖提取
```python
from .relative import X            → 内部依赖
from package_name import X         → 外部依赖
import package_name                → 外部依赖
```

---

## Java / Kotlin 解析

### 识别方法
```java
// 类方法
public class Foo {
    public ReturnType methodName(params) { ... }
    private void methodName(params) { ... }
    protected static ReturnType methodName(params) { ... }
    @Override public ReturnType methodName(params) { ... }
}

// Spring 注解
@GetMapping("/path")
public ResponseEntity<T> handler() { ... }

@Service / @Controller / @Repository
```

### 模块边界识别
- Maven/Gradle 多模块项目：每个子 module = 一个模块
- Spring Boot 单体：按 package 分组（com.xxx.auth, com.xxx.order 等）

---

## Go 解析

### 识别方法
```go
// 包级函数
func FuncName(params) (ReturnType, error) { ... }

// 方法（带 receiver）
func (s *Service) MethodName(params) error { ... }

// HTTP handler
func (h *Handler) HandleRequest(w http.ResponseWriter, r *http.Request) { ... }
```

### 模块边界识别
- 每个目录（package）= 一个模块
- `internal/` 下的每个包 = 内部模块
- `cmd/` 下的每个子目录 = 一个入口

---

## LF 基础设施层解析指南

LF 层的核心任务是**从生成代码中提取结构化信息**，不是逐行记忆生成代码的实现细节。

### gorm/gen（Go）解析

gorm/gen 通常生成两类文件：
- `model/*.gen.go`：struct 定义（对应表结构）
- `query/*.gen.go`：查询方法（对应可用的查询能力）

**从 model 文件提取：**
```go
// model/users.gen.go
type User struct {
    ID           int64          `gorm:"column:id;primaryKey;autoIncrement"`
    Email        string         `gorm:"column:email;not null;uniqueIndex"`
    PasswordHash string         `gorm:"column:password_hash;not null"`
    Status       int8           `gorm:"column:status;not null;default:1"`
    // ...
}
```
→ 提取：表名、每个字段的名称、Go 类型、DB 列名、约束（从 gorm tag 中解析）

**从 query 文件提取：**
```go
// query/users.gen.go
type userDo struct { ... }
func (u userDo) FindByEmail(email string) (*model.User, error)
func (u userDo) FindActiveUsers() ([]*model.User, error)
```
→ 提取：可用的自定义查询方法签名和说明

**提取要点：**
- gorm tag 中的 `column:` 是真实列名
- `primaryKey` / `uniqueIndex` / `not null` / `default:` 是约束
- 表名通过 `TableName()` 方法或 struct 名推断
- 关联关系通过 `foreignKey` tag 或 `BelongsTo` / `HasMany` 等方法判断

### Prisma（TypeScript/JavaScript）解析

从 `prisma/schema.prisma` 提取：
```prisma
model User {
  id        Int      @id @default(autoincrement())
  email     String   @unique
  orders    Order[]
  profile   Profile?
}
```
→ 直接提取：model 名、字段、类型、约束、关系

### SQLAlchemy（Python）解析

```python
class User(Base):
    __tablename__ = 'users'
    id = Column(Integer, primary_key=True)
    email = Column(String(255), unique=True, nullable=False)
    orders = relationship("Order", back_populates="user")
```
→ 提取：表名、字段定义、relationship

### Django（Python）解析

```python
class User(models.Model):
    email = models.EmailField(unique=True)
    status = models.IntegerField(default=1)
    class Meta:
        db_table = 'users'
```
→ 提取：model 名、字段、Meta 配置

### MyBatis/JPA（Java）解析

```java
@Entity
@Table(name = "users")
public class User {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Column(unique = true, nullable = false)
    private String email;
}
```
→ 提取：注解中的表名、列约束、关联注解（@OneToMany 等）

### Migration 文件解析

Migration 文件记录了数据结构的演进历史。提取要点：
- 操作类型：CREATE TABLE / ALTER TABLE / DROP TABLE
- 具体变更：ADD COLUMN / DROP COLUMN / MODIFY COLUMN / ADD INDEX
- 时间或版本号
- 向上和向下（回滚）操作

**只需记录"做了什么"，不需要记录完整 SQL。**

### Protobuf 解析

```protobuf
service UserService {
    rpc GetUser(GetUserRequest) returns (GetUserResponse);
}

message GetUserRequest {
    int64 user_id = 1;
}
```
→ 提取：service 名、RPC 方法列表、message 字段定义

### Thrift IDL 解析

Thrift IDL 文件是项目对外的接口窗口，定义了所有 API 的请求/响应结构和路由。

```thrift
// idl/biz_public.thrift

namespace go bizPublic

struct LoginReq {
    1: required string phone        (api.query="phone")
    2: required string code         (api.query="code")
    3: optional string device_id    (api.query="device_id")
}

struct LoginResp {
    1: required string token
    2: required UserInfo user_info
    3: required bool is_new
}

struct UserInfo {
    1: required i64 user_id
    2: required string nickname
    3: optional string avatar
    4: optional i32 vip_level
}

service BizPublicService {
    LoginResp Login(1: LoginReq req) (api.post="/api/v1/user/login")
    UserInfo GetUserInfo(1: UserInfoReq req) (api.get="/api/v1/user/info")
}
```

**提取要点：**

1. **Struct 定义** → 每个 struct 提取：名称、所有字段（序号、类型、必选/可选、api annotation）
2. **Service 定义** → 每个方法提取：方法名、请求 struct、响应 struct、HTTP 方法和路径（从 api.post/api.get 注解）
3. **Enum / Const** → 提取枚举值和说明
4. **Include** → 提取 include 了哪些其他 IDL 文件（模块间依赖）
5. **Namespace** → 确定生成代码的包路径

**Hertz 框架特殊处理：**
- `api.post`/`api.get`/`api.put`/`api.delete` 注解 → 提取 HTTP 路由
- `api.query`/`api.body`/`api.path` 注解 → 提取参数绑定方式
- `api.header`/`api.cookie` 注解 → 提取 header/cookie 绑定
- 生成产物在 `biz/gen/hertz/model/<namespace>/` 和 `biz/gen/hertz/router/`
- Handler 骨架在 `biz/handler/` — 这是**手写代码**，需要建档到 L2/L3

**IDL 变更的影响面分析：**
- 新增 struct → 可能是新接口的请求/响应体
- 修改 struct 字段 → 影响所有使用该 struct 的接口和 handler
- 新增 service 方法 → 需要新的 handler 实现
- 修改路由注解 → 影响路由注册
- 修改字段 required/optional → 影响参数校验逻辑

---

## L3 方法逻辑描述规范

当描述方法的逐行逻辑时，遵循以下规范：

### 粒度标准
- 每个有意义的操作占一步（不是真的每一行代码都要描述）
- 条件分支用缩进或子列表表示
- 循环用"遍历 xxx，对每个元素..."的方式描述
- try-catch 标注异常处理范围

### 描述风格
- 用**动词开头**：校验、查询、构造、返回、抛出、调用、遍历、计算
- 标注**行号范围**：方便日后精准定位
- 标注**调用的其他方法**：用 `→ MethodName()` 表示
- 标注**副作用**：写数据库、发消息、写日志、修改全局状态

### 示例

```markdown
## 逻辑流程
1. [L47-48] 校验 email 格式 → validateEmail()，失败抛 InvalidEmailError
2. [L50-52] 查数据库找用户 → UserRepo.findByEmail()
3. [L53-54] 未找到 → 抛 UserNotFoundError
4. [L55-58] 比对密码哈希 → bcrypt.compare()
   - 失败 → 递增 failCount（副作用：写 DB）
   - failCount >= 5 → 锁定账户，抛 AccountLockedError
5. [L60-65] 验证通过：
   - 重置 failCount 为 0（副作用：写 DB）
   - 生成 JWT → TokenService.sign()
6. [L67-68] 写登录审计日志（副作用：→ AuditLog.record()）
7. [L70] 返回 { token, user, expiresAt }
```

---

## 增量更新时的解析策略

当 git diff 显示文件变化时：

### 判断影响范围
1. 读取 diff 的具体变更行
2. 判断变更是否影响了方法签名（影响 L2）
3. 判断变更是否影响了方法内部逻辑（影响 L3）
4. 判断变更是否新增/删除了方法或导出（影响 L2 + L1）
5. 判断变更是否影响了模块间依赖（影响 L1 + 可能影响 L0）
6. 判断变更是否涉及 IDL 文件（影响 LF/idl/ + 可能影响 L2/L3 的接口实现）

### 最小化重建
- 只修改了方法内部逻辑 → 只重建那一个 L3
- 新增了方法 → 新建 L3 + 更新 L2
- 删除了方法 → 删除 L3 + 更新 L2
- 修改了 import → 更新 L2 的依赖部分 + 检查 L1 是否受影响
- 新增了文件 → 新建 L2 + 所有 L3 + 更新 L1
- IDL 新增 struct → 更新 LF/idl 对应文档
- IDL 新增 service 方法 → 更新 LF/idl + 检查是否有新 handler 需要建档
- IDL 修改字段 → 更新 LF/idl + 检查"被谁实现"中的 L3 是否受影响
