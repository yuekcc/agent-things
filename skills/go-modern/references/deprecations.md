# Go 1.23–1.26 完整废弃列表

> 本文档列出 Go 1.23 至 1.26 中所有废弃（deprecated）的 API、行为和平台支持。
> 每项包含版本、替代方案、代码示例和 GODEBUG 回退（如有）。

---

## 1. 语言与运行时 (Language & Runtime)

### 1.1 `for` 循环变量重新声明（Go 1.22+ 起不再需要）

- **废弃版本**：Go 1.22 起语义变更，Go 1.24 起 `go vet` 标记为不必要
- **替代**：直接使用循环变量，无需在闭包中重新声明
- **GODEBUG**：`GODEBUG=loopvar=1`（恢复 Go 1.21 行为，仅当 `go.mod` 声明 < 1.22 时生效）

```go
// Before (Go 1.21 及之前 — 必须重新声明)
for _, v := range items {
    v := v // 必须：防止闭包捕获循环变量
    go func() {
        process(v)
    }()
}

// After (Go 1.22+ — 不再需要)
for _, v := range items {
    go func() {
        process(v) // 安全：每次迭代创建新变量
    }()
}
```

### 1.2 `runtime.SetFinalizer`（Go 1.24 废弃）

- **废弃版本**：Go 1.24
- **替代**：`runtime.AddCleanup`
- **原因**：`SetFinalizer` 存在对象复活问题，且阻止 GC 回收循环引用

```go
// Before — SetFinalizer
type Resource struct {
    handle uintptr
}

func NewResource() *Resource {
    r := &Resource{handle: acquireHandle()}
    runtime.SetFinalizer(r, func(r *Resource) {
        releaseHandle(r.handle) // 危险：r 在 finalizer 中被复活
    })
    return r
}

// After — AddCleanup (Go 1.24+)
func NewResource() *Resource {
    r := &Resource{handle: acquireHandle()}
    runtime.AddCleanup(r, func(handle uintptr) {
        releaseHandle(handle) // 安全：仅使用值副本，不引用原对象
    }, r.handle)
    return r
}
```

### 1.3 `math/rand.Seed` 和全局随机状态（Go 1.24 正式废弃）

- **废弃版本**：Go 1.20 开始自动种子，Go 1.24 `Seed()` 变为空操作
- **替代**：使用 `math/rand/v2` 或 `rand.New(rand.NewSource(seed))`
- **GODEBUG**：`GODEBUG=randseednop=0`（恢复 `Seed()` 功能）

```go
// Before
import "math/rand"

func init() {
    rand.Seed(time.Now().UnixNano()) // Go 1.24: 空操作
}
func roll() int {
    return rand.Intn(6) + 1
}

// After
import "math/rand/v2"

func roll() int {
    return rand.IntN(6) + 1 // 全局源自动安全种子
}

// 需要确定性种子时
func deterministicRoll(seed uint64) int {
    src := rand.NewPCG(seed, 0)
    rng := rand.New(src)
    return rng.IntN(6) + 1
}
```

### 1.4 `GOEXPERIMENT=rangefunc`（Go 1.23 移除实验标志）

- **废弃版本**：Go 1.23（正式化，不再需要实验标志）
- **替代**：直接使用，无需设置 `GOEXPERIMENT`

---

## 2. 密码学包 (Crypto Packages)

### 2.1 SHA-1 X.509 证书验证（Go 1.24 完全移除支持）

- **废弃版本**：Go 1.18 开始警告，Go 1.24 移除
- **替代**：使用 SHA-256 或更强的签名算法
- **GODEBUG**：`x509sha1=1` 在 Go 1.24 中 **已被移除**，无回退

```go
// 检查证书签名算法
func checkCert(cert *x509.Certificate) error {
    switch cert.SignatureAlgorithm {
    case x509.SHA1WithRSA, x509.ECDSAWithSHA1:
        return fmt.Errorf("SHA-1 签名证书不再支持（Go 1.24+），请升级证书")
    default:
        return nil
    }
}
```

### 2.2 `crypto/aes.NewCipher` 返回值的内部方法（Go 1.24 变更）

- **废弃版本**：Go 1.24
- **影响**：返回的 `cipher.Block` 不再实现 `crypto/aes` 包内部接口
- **替代**：使用标准 `cipher.Block` 接口方法

```go
// Before — 某些库通过类型断言访问内部方法
block, _ := aes.NewCipher(key)
// 旧版本某些实现会检查 block 是否实现特定内部接口
// Go 1.24+ 这些类型断言会失败

// After — 使用标准 cipher 接口
block, _ := aes.NewCipher(key)
gcm, err := cipher.NewGCM(block) // 使用标准接口
```

### 2.3 短 RSA 密钥（< 1024 位）（Go 1.24 拒绝）

- **废弃版本**：Go 1.24
- **替代**：使用 >= 2048 位 RSA 密钥
- **GODEBUG**：`GODEBUG=rsa1024min=0`

```go
// Before — 可能在测试中使用短密钥
key, _ := rsa.GenerateKey(rand.Reader, 512) // Go 1.24+: 仍能生成但签名/验签会报错

// After — 使用标准长度密钥
key, _ := rsa.GenerateKey(rand.Reader, 2048)

// 或使用更现代的算法
key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
```

### 2.4 TLS SHA-1 签名（Go 1.25 禁止）

- **废弃版本**：Go 1.25
- **替代**：使用 SHA-256 或更强签名
- **GODEBUG**：`GODEBUG=tlssha1=1`

```go
// Before — 可能默认允许 SHA-1
tlsConfig := &tls.Config{}

// After — 明确使用强签名（Go 1.25+ 已是默认行为）
tlsConfig := &tls.Config{
    MinVersion: tls.VersionTLS12,
    // SHA-1 签名套件已自动排除
}
```

### 2.5 TLS 3DES 密码套件（Go 1.23 禁止，Go 1.26 移除回退）

- **废弃版本**：Go 1.23 默认禁止
- **GODEBUG**：`GODEBUG=tls3des=1`（Go 1.23-1.25 可用，Go 1.26 **已移除**）
- **替代**：使用 AES-GCM 或 ChaCha20-Poly1305

### 2.6 `crypto/rand.Read` 自定义 Reader（Go 1.26 忽略）

- **废弃版本**：Go 1.26
- **影响**：传入的 `io.Reader` 参数被忽略，始终使用系统随机源

```go
// Before — 可以传入自定义随机源
customReader := myDeterministicReader()
_, err := io.ReadFull(customReader, buf) // 仍然有效

// After (Go 1.26) — rand.Read 忽略 Reader 字段
import "crypto/rand"
_, err := rand.Read(buf) // 始终使用系统随机源
// 需要自定义源的场景请使用 io.ReadFull(customReader, buf)
```

### 2.7 `crypto/elliptic` 直接曲线运算（Go 1.24 继续废弃）

- **废弃版本**：Go 1.20+（持续）
- **替代**：使用 `crypto/ecdsa`、`crypto/ecdh`

```go
// Before — 直接操作椭圆曲线点
x, y := elliptic.P256().ScalarBaseMult(scalar)

// After — 使用高层 API
privateKey, _ := ecdh.P256().GenerateKey(rand.Reader)
publicKey := privateKey.PublicKey()
```

---

## 3. Net/HTTP 包 (Net/HTTP Packages)

### 3.1 旧版 `ServeMux` 路由模式（Go 1.22+ 增强路由）

- **废弃版本**：Go 1.22 引入增强路由（方法+路径参数），旧路由模式不再推荐
- **GODEBUG**：`GODEBUG=httpmuxgo121=1`

```go
// Before — 需要第三方路由库或手动解析
mux := http.NewServeMux()
mux.HandleFunc("/users/", func(w http.ResponseWriter, r *http.Request) {
    // 手动解析路径获取 ID
    id := strings.TrimPrefix(r.URL.Path, "/users/")
    if r.Method != "GET" {
        http.Error(w, "method not allowed", 405)
        return
    }
    // ...
})

// After (Go 1.22+)
mux := http.NewServeMux()
mux.HandleFunc("GET /users/{id}", func(w http.ResponseWriter, r *http.Request) {
    id := r.PathValue("id")
    // ...
})
```

### 3.2 `ServeMux` 301 尾部斜杠重定向（Go 1.26 改为 307）

- **废弃版本**：Go 1.26 变更默认行为
- **GODEBUG**：`GODEBUG=servemuxstatus301=1`

```go
// Go 1.25 及之前：
// POST /api/users 注册了 /api/users/
// → 301 Moved Permanently（POST 变 GET，丢失请求体）

// Go 1.26：
// POST /api/users 注册了 /api/users/
// → 307 Temporary Redirect（保持 POST 方法和请求体）
```

### 3.3 `http.ListenAndServeTLS` 不推荐直接使用

- **替代**：使用 `http.Server` 结构体以获得更好的超时和关闭控制

```go
// Before
http.ListenAndServeTLS(":443", "cert.pem", "key.pem", handler)

// After
srv := &http.Server{
    Addr:         ":443",
    Handler:      handler,
    ReadTimeout:  15 * time.Second,
    WriteTimeout: 15 * time.Second,
    IdleTimeout:  60 * time.Second,
}
srv.ListenAndServeTLS("cert.pem", "key.pem")
```

---

## 4. 测试与工具 (Testing & Tools)

### 4.1 `for i := 0; i < b.N; i++` 基准测试循环（Go 1.24 废弃）

- **废弃版本**：Go 1.24
- **替代**：`b.Loop()`
- **优势**：`b.Loop()` 自动排除 setup 时间，防止编译器错误优化

```go
// Before
func BenchmarkOld(b *testing.B) {
    setup() // 被计入基准时间！
    for i := 0; i < b.N; i++ {
        result = expensiveOperation()
    }
}

// After (Go 1.24+)
func BenchmarkNew(b *testing.B) {
    setup() // 不被计入基准时间
    for b.Loop() {
        result = expensiveOperation() // 编译器不会优化掉
    }
}
```

### 4.2 测试中手动创建临时目录（Go 1.24 起有更好方式）

- **替代**：`t.Chdir()` 和 `t.TempDir()` 的组合

```go
// Before
func TestOld(t *testing.T) {
    dir, err := os.MkdirTemp("", "test")
    if err != nil {
        t.Fatal(err)
    }
    defer os.RemoveAll(dir)
    oldDir, _ := os.Getwd()
    os.Chdir(dir)
    defer os.Chdir(oldDir)
    // ...
}

// After (Go 1.24+)
func TestNew(t *testing.T) {
    t.Chdir(t.TempDir()) // 自动清理、自动恢复工作目录
    // ...
}
```

### 4.3 手动管理测试上下文（Go 1.24 起有 `T.Context()`）

- **废弃版本**：Go 1.24（不再需要手动创建 context）
- **替代**：`t.Context()`

```go
// Before
func TestOld(t *testing.T) {
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()
    result, err := fetchData(ctx)
    // ...
}

// After (Go 1.24+)
func TestNew(t *testing.T) {
    result, err := fetchData(t.Context()) // 测试结束自动取消
    // ...
}
```

### 4.4 `go tool` 前缀运行工具（Go 1.24 变更）

- **变更版本**：Go 1.24（`go.mod` 中新增 `tool` 指令）
- **替代**：通过 `go.mod` 声明项目工具依赖

```bash
# Before — 全局安装工具
go install golang.org/x/tools/cmd/stringer@latest
stringer -type=Color

# After (Go 1.24+) — 在 go.mod 中声明
go get -tool golang.org/x/tools/cmd/stringer
# go.mod 会添加：
# tool golang.org/x/tools/cmd/stringer
go tool stringer -type=Color
```

### 4.5 `testing.B.ArtifactDir` 之前的临时文件管理（Go 1.25+）

- **废弃版本**：Go 1.25 引入 `T.ArtifactDir()` / `B.ArtifactDir()`
- **替代**：`t.ArtifactDir()` 提供可保留的测试输出目录

```go
// Before — 输出到临时目录，测试后需手动查找
func TestGenerateReport(t *testing.T) {
    f, _ := os.CreateTemp("", "report-*.html")
    defer f.Close()
    generateReport(f)
    t.Logf("report saved to %s", f.Name()) // 需要手动找到文件
}

// After (Go 1.25+)
func TestGenerateReport(t *testing.T) {
    dir := t.ArtifactDir() // go test -artifactdir=./outputs 可指定保存位置
    f, _ := os.Create(filepath.Join(dir, "report.html"))
    defer f.Close()
    generateReport(f)
}
```

---

## 5. 编码包 (Encoding Packages)

### 5.1 `encoding/json` `omitempty` 对零值结构体的行为（Go 1.24 引入 `omitzero`）

- **废弃版本**：`omitempty` 并未废弃，但对 `time.Time` 等类型行为不符合预期
- **替代**：`omitzero` 标签（Go 1.24+）

```go
// Before — omitempty 不会省略零值 time.Time（因为它不是"空"的）
type Event struct {
    Name      string    `json:"name"`
    StartTime time.Time `json:"start_time,omitempty"` // 零值仍会输出 "0001-01-01T..."
}

// After (Go 1.24+) — omitzero 按 IsZero() 判断
type Event struct {
    Name      string    `json:"name"`
    StartTime time.Time `json:"start_time,omitzero"` // 零值时省略该字段
}
```

### 5.2 `encoding.TextMarshaler` 性能（Go 1.24 引入 `TextAppender`）

- **废弃版本**：`TextMarshaler` 未废弃，但新代码推荐实现 `TextAppender`
- **替代**：`encoding.TextAppender`（减少分配）

```go
// Before — TextMarshaler 每次分配新 []byte
type IPAddr struct{ ip net.IP }

func (a IPAddr) MarshalText() ([]byte, error) {
    return []byte(a.ip.String()), nil // 每次调用分配
}

// After (Go 1.24+) — TextAppender 追加到已有 buffer
func (a IPAddr) AppendText(b []byte) ([]byte, error) {
    return append(b, a.ip.String()...), nil // 复用 buffer，减少 GC 压力
}
```

### 5.3 `image/jpeg` 旧实现（Go 1.26 全新重写）

- **变更版本**：Go 1.26
- **影响**：编码输出字节流可能不同（仍是合法 JPEG）
- **注意**：不应有代码依赖 JPEG 编码的精确字节输出

---

## 6. 平台/端口移除 (Platform/Port Removals)

### 6.1 macOS 版本支持

| Go 版本 | 最低 macOS 版本 | 移除的 macOS 版本 |
|--------|----------------|-----------------|
| Go 1.23 | macOS 11 (Big Sur) | macOS 10.15 (Catalina) 及以下 |
| Go 1.25 | macOS 12 (Monterey) | macOS 11 (Big Sur) |

### 6.2 Linux 内核版本支持

| Go 版本 | 最低 Linux 内核 | 说明 |
|--------|---------------|------|
| Go 1.24 | 3.2 | glibc >= 2.17 |
| Go 1.25 | 3.17 | 要求 `getrandom` 系统调用 |

### 6.3 Windows 版本支持

| Go 版本 | 变更 |
|--------|------|
| Go 1.24 | Windows 10 (1809) 最低要求；移除 Windows 7/8 支持 |

### 6.4 已废弃/移除的端口

| 端口 | 状态 | 版本 | 说明 |
|-----|------|------|------|
| `darwin/arm64` (iOS) | 限制支持 | Go 1.23+ | 仅通过 Cgo 支持 |
| `js/wasm` | 继续支持 | - | `wasip1/wasm` 推荐用于非浏览器场景 |
| `wasip2/wasm` | 新增预览 | Go 1.24 | WASI Preview 2 支持 |
| `386` 端口 | 软废弃中 | Go 1.25+ | SSE2 最低要求 |
| `mips` (软浮点) | 计划移除 | Go 1.26+ | 使用 `mipsle` 硬浮点代替 |
| `freebsd/riscv64` | 新增 | Go 1.25 | - |

---

## 7. GODEBUG 设置计划移除时间表

以下 GODEBUG 设置已被移除或计划在指定版本移除：

### 已移除

| 设置 | 移除版本 | 原控制行为 | 替代方案 |
|-----|---------|-----------|---------|
| `x509sha1` | Go 1.24 | SHA-1 X.509 证书验证 | 升级为 SHA-256 证书 |
| `tls3des` | Go 1.26 | TLS 3DES 密码套件 | 使用 AES-GCM |
| `installgobin` | Go 1.24 | `go install` 二进制位置 | 默认行为 |
| `panicnil` | Go 1.25 | `panic(nil)` 是否可恢复 | 使用 `panic(errors.New(...))` |
| `httplaxcontentlength` | Go 1.25 | 宽松的 Content-Length 解析 | 修复发送方 |
| `multipathtcp` | Go 1.26 | 多路径 TCP | 默认启用 |

### 计划移除（Go 1.27+）

| 设置 | 引入版本 | 预计移除 | 控制行为 |
|-----|---------|---------|---------|
| `asynctimerchan` | Go 1.23 | Go 1.27 | Timer channel 缓冲 |
| `httpmuxgo121` | Go 1.22 | Go 1.27 | 旧版 ServeMux 路由 |
| `rsa1024min` | Go 1.24 | Go 1.27 | RSA 最小密钥长度 |
| `gomapmaxbucketcount` | Go 1.24 | Go 1.27 | 旧版 map 实现 |

### 计划移除（Go 1.28+）

| 设置 | 引入版本 | 预计移除 | 控制行为 |
|-----|---------|---------|---------|
| `containermaxprocs` | Go 1.25 | Go 1.28 | 容器 CPU 自动感知 |
| `tlssha1` | Go 1.25 | Go 1.28 | TLS SHA-1 签名 |
| `urlhostreject` | Go 1.26 | Go 1.28 | URL host 冒号检查 |
| `servemuxstatus301` | Go 1.26 | Go 1.28 | ServeMux 重定向状态码 |
| `randautoseed` | Go 1.26 | Go 1.28 | math/rand 自动种子 |

---

## 快速检查清单

升级前在代码库中运行以下检查：

```bash
# 1. 搜索所有已废弃 API 的使用
go vet ./...

# 2. 搜索 GODEBUG 设置
grep -rn 'GODEBUG\|go:debug' --include='*.go' --include='*.mod' --include='*.env' .

# 3. 搜索 //go:linkname
grep -rn '//go:linkname' --include='*.go' . vendor/

# 4. 搜索短 RSA 密钥
grep -rn 'GenerateKey.*\(512\|768\)' --include='*.go' .

# 5. 搜索 SHA-1 证书引用
grep -rn 'SHA1\|sha1' --include='*.go' --include='*.pem' .

# 6. 搜索 SetFinalizer 使用
grep -rn 'SetFinalizer' --include='*.go' .

# 7. 搜索旧版 benchmark 循环
grep -rn 'for.*:=.*0.*b\.N' --include='*_test.go' .

# 8. 搜索 rand.Seed 调用
grep -rn 'rand\.Seed' --include='*.go' .

# 9. 运行 go fix 预览（Go 1.26+）
go fix -fix all -diff ./...

# 10. 运行漏洞检查
govulncheck ./...
```
