# Go 1.25 Reference (August 2025)

> Go 1.25 预计于 2025 年 8 月发布。本文档基于 Go 1.25 Release Notes 整理，涵盖语言变更、工具链、运行时、编译器、标准库及平台支持等所有关键内容。

---

## 语言变更 (Language Changes)

Go 1.25 **没有引入任何语言层面的变更**。

唯一值得注意的是：**core types（核心类型）** 概念已从语言规范中移除。该概念最初在 Go 1.18 引入泛型时加入规范，但实践证明它并非必要的规范工具，因此被清理。这不影响任何现有代码的行为。

---

## 工具链变更 (Toolchain Changes)

### go build -asan：默认内存泄漏检测

使用 `-asan`（AddressSanitizer）构建的程序现在 **默认在退出时检测内存泄漏**。之前版本需要手动设置环境变量才能启用，现在是开箱即用的行为。

```bash
# 构建带 ASan 的程序，退出时自动报告内存泄漏
go build -asan -o myapp ./cmd/myapp
./myapp  # 退出时若有泄漏会自动报告
```

### 精简预编译工具二进制 (Reduced Precompiled Tool Binaries)

Go 工具链不再随发行版一起分发所有预编译的工具二进制文件（如 `vet`、`pprof` 等）。这些工具将在 **首次使用时按需构建**，显著减小了 Go 发行包的体积。

```bash
# 首次运行时会自动编译工具（之后有缓存）
go vet ./...
```

### go.mod `ignore` 指令

新增 `ignore` 指令，允许在模块中 **忽略指定目录**，使其不参与构建和模块图计算。这对于在仓库中包含示例代码、实验性项目或第三方代码副本的场景非常有用。

```go
// go.mod
module example.com/myproject

go 1.25

ignore (
    experiments/
    third_party/legacy/
    _examples/
)
```

### go doc -http 选项

`go doc` 命令新增 `-http` 选项，可以启动一个本地 HTTP 服务器来浏览文档，作为已废弃的 `godoc` 工具的替代方案。

```bash
# 启动本地文档服务器
go doc -http=:6060

# 在浏览器中访问 http://localhost:6060
```

### go version -m -json

`go version -m` 现在支持 `-json` 标志，以 JSON 格式输出二进制文件中嵌入的模块和构建信息。

```bash
go version -m -json ./myapp
```

输出示例：
```json
{
  "GoVersion": "go1.25",
  "Path": "example.com/myapp",
  "Main": {
    "Path": "example.com/myapp",
    "Version": "v1.2.3"
  },
  "Settings": [
    {"Key": "GOOS", "Value": "linux"},
    {"Key": "GOARCH", "Value": "amd64"}
  ]
}
```

### 仓库子目录支持模块根 (Repository Subdirectory Support)

现在支持将模块根目录放在仓库的子目录中，通过仓库 URL 的子路径进行引用。这简化了 monorepo 场景下的模块管理。

### 新增 `work` 包模式 (New `work` Package Pattern)

在工作区模式下，新增 `work` 包模式，用于匹配工作区中所有模块的包。

```bash
# 测试工作区中所有模块的所有包
go test work/...
```

### 不再自动添加 toolchain 行

`go` 命令不再自动向 `go.mod` 或 `go.work` 文件添加 `toolchain` 行。之前在某些操作中会自动插入，现在需要用户显式管理。

### Vet 新增分析器

#### waitgroup 分析器
检测 `sync.WaitGroup.Add` 在 goroutine 内部调用而不是在启动 goroutine 之前调用的错误模式。

```go
// vet 会警告以下代码：
var wg sync.WaitGroup
go func() {
    wg.Add(1)  // 错误！Add 应在 goroutine 外部调用
    defer wg.Done()
    // ...
}()
wg.Wait()

// 正确写法：
var wg sync.WaitGroup
wg.Add(1)
go func() {
    defer wg.Done()
    // ...
}()
wg.Wait()

// 或者使用 Go 1.25 新增的 wg.Go（见后文）
```

#### hostport 分析器
检测将 host 和 port 通过 `+` 或 `fmt.Sprintf` 拼接而非使用 `net.JoinHostPort` 的代码。手动拼接在 IPv6 地址场景下会出错。

```go
// vet 会警告以下代码：
addr := host + ":" + port                         // 错误！IPv6 不安全
addr := fmt.Sprintf("%s:%s", host, port)           // 错误！IPv6 不安全

// 正确写法：
addr := net.JoinHostPort(host, port)               // 正确，IPv6 安全
```

---

## 运行时变更 (Runtime Changes) — 关键更新

### 容器感知的 GOMAXPROCS (Container-aware GOMAXPROCS)

这是 Go 1.25 最重要的运行时变更之一。Go 运行时现在能 **感知 Linux cgroup CPU 带宽限制**，自动调整 `GOMAXPROCS`。

#### Linux cgroup CPU 带宽感知

在容器环境中（如 Docker、Kubernetes），CPU 限制通常通过 cgroup 的 CPU 带宽控制（`cpu.cfs_quota_us` / `cpu.cfs_period_us`）实现。Go 1.25 之前，`GOMAXPROCS` 默认等于宿主机 CPU 核数，可能远大于容器实际可用的 CPU 资源，导致过度线程竞争和性能下降。

```go
// Go 1.25 之前在 8 核机器上，容器限制 2 核：
// GOMAXPROCS = 8（宿主机核数，不合理）

// Go 1.25 自动检测 cgroup 限制：
// GOMAXPROCS = 2（容器实际可用核数）
```

#### 周期性 GOMAXPROCS 更新

运行时会 **周期性检查** cgroup CPU 限制的变化，并自动更新 `GOMAXPROCS`。这对于支持动态资源调整的容器编排系统（如 Kubernetes VPA）尤为有用。

#### runtime.SetDefaultGOMAXPROCS

新增函数允许程序设置默认的 `GOMAXPROCS` 计算逻辑：

```go
import "runtime"

func init() {
    // 自定义默认 GOMAXPROCS 行为
    // 仅在用户未显式设置 GOMAXPROCS 环境变量时生效
    runtime.SetDefaultGOMAXPROCS(4)
}
```

#### GODEBUG 控制

```bash
# 禁用容器感知的 GOMAXPROCS（回退到旧行为，使用宿主机 CPU 数）
GODEBUG=containermaxprocs=0 ./myapp

# 禁用周期性 GOMAXPROCS 更新
GODEBUG=updatemaxprocs=0 ./myapp
```

---

### GreenTea GC（实验性垃圾回收器）

Go 1.25 引入了一个名为 **GreenTea** 的实验性垃圾回收器，旨在显著降低 GC 开销。

#### 启用方式

```bash
# 通过 GOEXPERIMENT 环境变量启用
GOEXPERIMENT=greenteagc go build -o myapp ./cmd/myapp
./myapp
```

#### 预期收益

- **GC 开销降低 10-40%**：具体取决于工作负载特征
- **改进的内存局部性**：通过更智能的对象布局减少缓存未命中
- **更好的 CPU 可扩展性**：在高核心数机器上表现更好

```go
// GreenTea GC 对应用代码透明，无需修改任何代码
// 仅在构建时通过 GOEXPERIMENT 启用

// 可通过 runtime/metrics 监控 GC 行为差异
import "runtime/metrics"

func printGCMetrics() {
    samples := []metrics.Sample{
        {Name: "/gc/cycles/total:gc-cycles"},
        {Name: "/gc/heap/allocs:bytes"},
        {Name: "/gc/pauses:seconds"},
    }
    metrics.Read(samples)
    for _, s := range samples {
        fmt.Printf("%s: %v\n", s.Name, s.Value)
    }
}
```

> 注意：GreenTea GC 是实验性的，不建议在生产环境中使用，除非经过充分测试。

---

### Flight Recorder（飞行记录器）

新增 `runtime/trace.FlightRecorder` 类型，提供 **低开销的环形缓冲区追踪** 功能，类似于飞机的黑匣子。

#### 核心概念

Flight Recorder 持续在后台以极低开销记录运行时追踪数据到一个固定大小的环形缓冲区。当出现问题时（如异常、性能抖动），可以将缓冲区中最近的追踪数据快照导出进行分析。

```go
import "runtime/trace"

func main() {
    // 创建 Flight Recorder
    fr := trace.NewFlightRecorder()

    // 设置配置（可选）
    fr.SetPeriod(10 * time.Second)  // 保留最近 10 秒的数据

    // 启动记录
    if err := fr.Start(); err != nil {
        log.Fatal(err)
    }
    defer fr.Stop()

    // ... 应用正常运行 ...

    // 当检测到异常时，导出快照
    http.HandleFunc("/debug/snapshot", func(w http.ResponseWriter, r *http.Request) {
        // WriteTo 将当前缓冲区内容写入 io.Writer
        if _, err := fr.WriteTo(w); err != nil {
            http.Error(w, err.Error(), 500)
        }
    })

    http.ListenAndServe(":8080", nil)
}
```

#### 典型使用场景

```go
// 在错误处理中捕获追踪快照
func processRequest(fr *trace.FlightRecorder) error {
    err := doSomething()
    if err != nil {
        // 出错时保存追踪快照到文件
        f, _ := os.Create(fmt.Sprintf("trace-snapshot-%d.out", time.Now().Unix()))
        defer f.Close()
        fr.WriteTo(f)
        return err
    }
    return nil
}
```

导出的快照文件可用 `go tool trace` 分析：

```bash
go tool trace trace-snapshot-1690000000.out
```

---

### 其他运行时变更

#### Repanic 输出格式变更

当 `recover()` 捕获 panic 后又重新 panic 时，运行时输出的格式发生了变化，更清晰地区分原始 panic 和 repanic 的调用栈。

#### Linux VMA 命名

在 Linux 系统上，Go 运行时现在会为其内存映射区域（VMA）设置描述性名称，便于通过 `/proc/<pid>/maps` 诊断内存使用情况：

```bash
cat /proc/$(pidof myapp)/maps
# 现在可以看到类似以下的命名：
# 7f1234000000-7f1234100000 rw-p ... [anon: Go: heap]
# 7f1234100000-7f1234200000 rw-p ... [anon: Go: stack]
# 7f1234200000-7f1234300000 r-xp ... [anon: Go: text]
```

#### GODEBUG 控制

```bash
# 禁用 VMA 命名（回退到匿名映射）
GODEBUG=decoratemappings=0 ./myapp
```

---

## 编译器与链接器 (Compiler & Linker)

### nil 指针检查 Bug 修复 — 重要！

修复了一个存在于 **Go 1.21 至 Go 1.24** 版本的编译器 bug：在某些情况下，编译器错误地消除了必要的 nil 指针检查。用 Go 1.25 重新编译这些版本的程序后，之前被错误忽略的 nil 解引用 **现在会正确触发 panic**。

```go
// 以下代码在 Go 1.21-1.24 中可能未正确 panic
// Go 1.25 修复后会正确 panic
var p *MyStruct = nil
_ = p.Field  // Go 1.25: 正确 panic: runtime error: invalid memory address

// 这意味着升级到 Go 1.25 后，某些之前"侥幸运行"的程序可能会开始 panic
// 请在升级后充分测试！
```

> **升级警告**：如果您的程序在 Go 1.21-1.24 下运行正常，升级到 Go 1.25 后可能会出现新的 panic。这不是 Go 1.25 的 bug，而是之前版本的 bug 被修复。请确保代码中没有 nil 指针解引用。

### DWARF 5 支持

编译器和链接器现在默认生成 **DWARF 5** 格式的调试信息（之前是 DWARF 4）。DWARF 5 格式更紧凑，**调试信息体积更小**，且被现代调试器更好地支持。

```bash
# 使用 DWARF 5（默认）
go build -o myapp ./cmd/myapp

# 查看 DWARF 版本信息
readelf --debug-dump=info myapp | head -20
```

### 更多切片栈分配 (More Slice Stack Allocation)

编译器的逃逸分析更加智能，能将更多 **切片分配到栈上** 而非堆上，减少 GC 压力。

```go
func processData(data []byte) int {
    // 在 Go 1.25 中，如果编译器能证明 buf 不逃逸，
    // 即使是较大的切片也可能分配在栈上
    buf := make([]byte, 256)
    copy(buf, data)
    return len(buf)
}
```

### AMD64 FMA 指令 (GOAMD64=v3+)

当目标架构为 `GOAMD64=v3` 或更高时，编译器现在会生成 **FMA（Fused Multiply-Add）指令**，提升浮点运算密集型代码的性能。

```bash
# 使用 GOAMD64=v3 启用 FMA 等高级指令
GOAMD64=v3 go build -o myapp ./cmd/myapp
```

```go
// FMA 指令将 a*b+c 合并为一条指令
// 提高精度（减少中间舍入）且提升性能
func fmaExample(a, b, c float64) float64 {
    return a*b + c  // GOAMD64=v3+ 时可能编译为 VFMADD 指令
}
```

### 链接器 -funcalign=N 选项

新增链接器选项 `-funcalign=N`，控制函数入口点的内存对齐方式。这对于性能敏感的场景有用，可以改善指令缓存行为。

```bash
# 将函数对齐到 32 字节边界
go build -ldflags="-funcalign=32" -o myapp ./cmd/myapp
```

---

## 新增/毕业包 (New/Graduated Packages)

### testing/synctest — 从实验性毕业

`testing/synctest` 包在 Go 1.24 中作为 `GOEXPERIMENT=synctest` 引入，现在在 Go 1.25 中 **正式毕业**，成为标准库的稳定部分。

该包提供了在测试中使用 **假时钟（fake clock）** 的能力，使得涉及时间的并发测试变得确定性和高效。

```go
import (
    "testing"
    "testing/synctest"
    "time"
)

func TestTimeout(t *testing.T) {
    // synctest.Test 创建一个使用假时钟的测试环境
    synctest.Test(t, func(t *testing.T) {
        done := make(chan struct{})

        go func() {
            // 这里的 time.Sleep 使用假时钟，不会真正等待
            time.Sleep(10 * time.Second)
            close(done)
        }()

        // synctest.Wait 等待所有 goroutine 到达稳定状态
        // （即所有 goroutine 都在等待某个条件）
        synctest.Wait()

        // 此时假时钟已经前进了 10 秒，done 已关闭
        select {
        case <-done:
            t.Log("成功：超时逻辑正确")
        default:
            t.Fatal("失败：goroutine 应已完成")
        }
    })
}
```

```go
// 测试带有定时器的复杂逻辑
func TestPeriodicTask(t *testing.T) {
    synctest.Test(t, func(t *testing.T) {
        var count int
        ctx, cancel := context.WithCancel(context.Background())
        defer cancel()

        go func() {
            ticker := time.NewTicker(1 * time.Second)
            defer ticker.Stop()
            for {
                select {
                case <-ticker.C:
                    count++
                case <-ctx.Done():
                    return
                }
            }
        }()

        // 假时钟前进，ticker 立即触发
        synctest.Wait()  // count == 1
        synctest.Wait()  // count == 2
        synctest.Wait()  // count == 3

        if count != 3 {
            t.Fatalf("期望 count=3，实际 count=%d", count)
        }
    })
}
```

### encoding/json/v2 — 实验性

Go 1.25 引入了 **实验性** 的 `encoding/json/v2` 包和 `encoding/json/jsontext` 包，提供更好的 JSON 处理能力。

#### 启用方式

```bash
GOEXPERIMENT=jsonv2 go build -o myapp ./cmd/myapp
```

#### 新包结构

- `encoding/json/jsontext`：底层 JSON 文本处理（tokenizer/encoder）
- `encoding/json/v2`：高层 JSON marshal/unmarshal API

```go
import (
    jsonv2 "encoding/json/v2"
    "encoding/json/jsontext"
)

type User struct {
    Name    string    `json:"name"`
    Email   string    `json:"email"`
    Created time.Time `json:"created"`
}

func example() {
    user := User{
        Name:    "张三",
        Email:   "zhangsan@example.com",
        Created: time.Now(),
    }

    // encoding/json/v2 提供更好的解码性能
    data, err := jsonv2.Marshal(&user)
    if err != nil {
        log.Fatal(err)
    }

    var decoded User
    err = jsonv2.Unmarshal(data, &decoded)
    if err != nil {
        log.Fatal(err)
    }

    // jsontext 包提供底层 token 级操作
    dec := jsontext.NewDecoder(bytes.NewReader(data))
    for {
        tok, err := dec.ReadToken()
        if err != nil {
            break
        }
        fmt.Println(tok.Kind(), tok.String())
    }
}
```

#### 性能改进

`encoding/json/v2` 在解码性能上有显著提升，尤其是对于大型 JSON 文档和复杂嵌套结构。

---

## 主要标准库变更 (Major Standard Library Changes)

### sync.WaitGroup.Go — 关键新模式

这是 Go 1.25 中最重要的 API 新增之一。`sync.WaitGroup` 新增 `Go` 方法，将 **Add/Done/go func** 三步合一。

```go
import "sync"

// Go 1.25 之前的典型模式：
func beforeGo125() {
    var wg sync.WaitGroup
    for i := 0; i < 10; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            doWork()
        }()
    }
    wg.Wait()
}

// Go 1.25 新模式 — 更简洁、更安全：
func afterGo125() {
    var wg sync.WaitGroup
    for i := 0; i < 10; i++ {
        wg.Go(func() {
            doWork()
        })
    }
    wg.Wait()
}
```

`wg.Go` 的优势：
1. **减少样板代码**：不再需要 `Add(1)` 和 `defer wg.Done()`
2. **消除常见错误**：无法忘记 `Done()`，也无法在 goroutine 内部误调 `Add()`
3. **更好的 vet 集成**：配合新的 `waitgroup` vet 分析器使用

```go
// 实际使用示例：并发获取多个 URL
func fetchAll(urls []string) map[string][]byte {
    var (
        wg sync.WaitGroup
        mu sync.Mutex
    )
    results := make(map[string][]byte)

    for _, url := range urls {
        wg.Go(func() {
            resp, err := http.Get(url)
            if err != nil {
                return
            }
            defer resp.Body.Close()
            body, _ := io.ReadAll(resp.Body)

            mu.Lock()
            results[url] = body
            mu.Unlock()
        })
    }
    wg.Wait()
    return results
}
```

---

### io/fs.ReadLinkFS 接口

新增 `ReadLinkFS` 接口，为文件系统抽象增加 **符号链接支持**。

```go
// io/fs 包中新增的接口
type ReadLinkFS interface {
    FS
    // ReadLink 返回符号链接指向的目标路径
    ReadLink(name string) (string, error)
}
```

```go
// 使用示例
func resolveLink(fsys fs.FS, path string) (string, error) {
    if rlfs, ok := fsys.(fs.ReadLinkFS); ok {
        return rlfs.ReadLink(path)
    }
    return "", fmt.Errorf("filesystem does not support symlinks")
}
```

---

### net/http.CrossOriginProtection

新增 `CrossOriginProtection` 中间件，基于 **Fetch Metadata** 请求头实现 CSRF 防护。

```go
import "net/http"

func main() {
    mux := http.NewServeMux()
    mux.HandleFunc("GET /api/data", handleGetData)
    mux.HandleFunc("POST /api/submit", handleSubmit)

    // 使用 CrossOriginProtection 包装 handler
    // 自动检查 Sec-Fetch-Site、Sec-Fetch-Mode 等 Fetch Metadata 头
    protected := http.CrossOriginProtection(mux)

    http.ListenAndServe(":8080", protected)
}
```

该中间件基于浏览器发送的 Fetch Metadata 请求头（`Sec-Fetch-Site`、`Sec-Fetch-Mode`、`Sec-Fetch-Dest`）判断请求是否为跨域请求，并拒绝可疑的跨站请求，是对传统 CSRF Token 方案的现代补充。

---

### hash.XOF 和 hash.Cloner 接口

#### hash.XOF

新增 `hash.XOF`（eXtendable Output Function）接口，支持可扩展输出的哈希函数（如 SHAKE128、SHAKE256）。

```go
// hash 包中新增的接口
type XOF interface {
    io.Writer     // Write 输入数据
    io.Reader     // Read 可变长度的哈希输出
    Reset()       // 重置状态
}
```

#### hash.Cloner

新增 `hash.Cloner` 接口，支持克隆哈希计算的中间状态。

```go
// hash 包中新增的接口
type Cloner interface {
    Hash
    Clone() (Hash, error)
}
```

```go
// 使用 Cloner 的场景：计算多个有共同前缀的哈希
func computeHashes(prefix []byte, suffixes [][]byte) [][]byte {
    h := sha256.New()
    h.Write(prefix)

    var results [][]byte
    if cloner, ok := h.(hash.Cloner); ok {
        for _, suffix := range suffixes {
            clone, _ := cloner.Clone()
            clone.Write(suffix)
            results = append(results, clone.Sum(nil))
        }
    }
    return results
}
```

---

### crypto 变更

#### MessageSigner 接口和 SignMessage 函数

新增更通用的消息签名接口，统一了不同签名算法的 API：

```go
import "crypto"

// 新增接口：MessageSigner
// 直接对消息签名（而非哈希值），适用于 Ed25519 等算法
type MessageSigner interface {
    SignMessage(rand io.Reader, message []byte, opts SignerOpts) ([]byte, error)
}

// 新增顶层函数
func SignMessage(signer crypto.Signer, rand io.Reader, message []byte, opts crypto.SignerOpts) ([]byte, error)
```

#### FIPS 模式性能大幅提升

- **ECDSA / Ed25519 FIPS 模式**：性能提升约 **4 倍**
- **RSA 密钥生成**：速度提升约 **3 倍**

```go
// 在 FIPS 模式下，这些操作现在快得多
import "crypto/ecdsa"

key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
sig, _ := ecdsa.SignASN1(rand.Reader, key, hash[:])  // FIPS 模式下 ~4x 加速
```

#### SHA 哈希性能提升

- **SHA-1 on AMD64 (SHA-NI)**：使用硬件加速指令，性能提升约 **2 倍**
- **SHA-3 on Apple M 系列芯片**：性能提升约 **2 倍**

#### TLS SHA-1 签名被禁止

TLS 握手中不再接受使用 SHA-1 的签名。SHA-1 已被视为密码学上不安全。

```bash
# 如需临时恢复 SHA-1 签名支持（不推荐）
GODEBUG=tlssha1=1 ./myapp
```

#### x509 证书 SubjectKeyId 默认使用 SHA-256

```go
// 创建证书时，SubjectKeyId 现在默认使用 SHA-256 计算
// 之前使用 SHA-1
template := &x509.Certificate{
    // SubjectKeyId 如未设置，将自动使用 SHA-256(公钥) 计算
}
```

---

### reflect.TypeAssert — 无分配类型断言

新增 `reflect.TypeAssert` 泛型函数，提供 **零分配** 的反射类型断言。

```go
import "reflect"

// 传统反射类型断言（可能有分配）
func oldWay(v reflect.Value) (int, bool) {
    iface := v.Interface()   // 可能分配到堆上
    n, ok := iface.(int)
    return n, ok
}

// Go 1.25 新方式 — 零分配
func newWay(v reflect.Value) (int, bool) {
    return reflect.TypeAssert[int](v)
}
```

```go
// 在热路径中使用 reflect.TypeAssert 可避免不必要的内存分配
func processValue(v reflect.Value) {
    if s, ok := reflect.TypeAssert[string](v); ok {
        handleString(s)
    } else if n, ok := reflect.TypeAssert[int64](v); ok {
        handleInt(n)
    }
}
```

---

### os.Root 扩展方法

`os.Root`（Go 1.24 引入的安全文件系统根目录抽象）在 Go 1.25 中大幅扩展了方法集：

```go
import "os"

func example() {
    root, err := os.OpenRoot("/srv/data")
    if err != nil {
        log.Fatal(err)
    }
    defer root.Close()

    // Go 1.25 新增方法（所有操作都限定在 root 目录内，防止路径穿越）：
    root.Chmod("config.json", 0644)
    root.Chown("config.json", uid, gid)
    root.Chtimes("config.json", atime, mtime)
    root.Lchown("link", uid, gid)

    root.Link("old.txt", "new.txt")                       // 硬链接
    root.Symlink("target.txt", "link.txt")                 // 符号链接
    target, _ := root.Readlink("link.txt")                 // 读取符号链接

    root.MkdirAll("a/b/c", 0755)                           // 递归创建目录

    data, _ := root.ReadFile("config.json")                 // 读取文件
    root.WriteFile("output.txt", data, 0644)                // 写入文件

    root.Rename("old.txt", "new.txt")                       // 重命名
    root.RemoveAll("temp/")                                 // 递归删除
}
```

---

### testing 改进

#### T.Attr, B.Attr, F.Attr — 结构化测试属性

新增 `Attr` 方法，为测试事件添加结构化的键值对属性，便于测试结果的自动化处理和过滤。

```go
func TestUserCreation(t *testing.T) {
    // 为测试添加结构化属性
    t.Attr("component", "user-service")
    t.Attr("priority", "high")
    t.Attr("ticket", "PROJ-1234")

    user, err := CreateUser("zhangsan", "zhangsan@example.com")
    if err != nil {
        t.Fatal(err)
    }
    if user.Name != "zhangsan" {
        t.Errorf("期望 Name=%q，实际=%q", "zhangsan", user.Name)
    }
}

func BenchmarkSort(b *testing.B) {
    b.Attr("algorithm", "quicksort")
    b.Attr("dataset", "random-10k")

    data := generateRandomData(10000)
    b.ResetTimer()
    for b.Loop() {
        sort.Ints(data)
    }
}
```

#### Output() io.Writer

新增 `Output()` 方法，返回一个 `io.Writer`，可以直接将输出流式写入测试日志。

```go
func TestWithOutput(t *testing.T) {
    // 获取测试输出的 io.Writer
    w := t.Output()

    // 可以将 Writer 传递给需要 io.Writer 的函数
    cmd := exec.Command("go", "version")
    cmd.Stdout = w
    cmd.Stderr = w
    cmd.Run()

    // 也可以用于日志记录
    logger := log.New(w, "TEST: ", log.LstdFlags)
    logger.Println("测试日志消息")
}
```

#### AllocsPerRun 在并行测试中 panic

`testing.AllocsPerRun` 现在如果在 `t.Parallel()` 标记的并行测试中调用会 **panic**，因为并行测试中的分配计数不准确。

```go
func TestAllocations(t *testing.T) {
    // 正确：非并行测试中使用 AllocsPerRun
    allocs := testing.AllocsPerRun(100, func() {
        _ = make([]byte, 1024)
    })
    t.Logf("分配次数: %.0f", allocs)
}

func TestAllocsParallel(t *testing.T) {
    t.Parallel()
    // 错误！Go 1.25 中以下代码会 panic
    // testing.AllocsPerRun(100, func() { ... })
}
```

---

### 其他标准库变更

#### archive/tar: AddFS 中的符号链接支持

`tar.Writer.AddFS` 现在能正确处理文件系统中的符号链接：

```go
import "archive/tar"

func createTarWithSymlinks(w io.Writer, fsys fs.FS) error {
    tw := tar.NewWriter(w)
    defer tw.Close()
    // AddFS 现在会正确包含符号链接
    return tw.AddFS(fsys)
}
```

#### log/slog: GroupAttrs 和 Record.Source

```go
import "log/slog"

// GroupAttrs: 创建分组属性
attrs := slog.GroupAttrs("request",
    slog.String("method", "GET"),
    slog.String("path", "/api/users"),
    slog.Int("status", 200),
)
slog.Info("请求完成", attrs...)

// Record.Source: 在自定义 Handler 中获取调用源位置
type MyHandler struct{}

func (h *MyHandler) Handle(ctx context.Context, r slog.Record) error {
    src := r.Source()
    fmt.Printf("[%s:%d] %s\n", src.File, src.Line, r.Message)
    return nil
}
```

#### go/ast: PreorderStack 和废弃标注

```go
import "go/ast"

// 新增 PreorderStack：带栈信息的前序遍历
// 遍历时可以访问当前节点到根节点的完整路径
ast.PreorderStack(file, nil, func(n ast.Node, stack []ast.Node) bool {
    if ident, ok := n.(*ast.Ident); ok {
        fmt.Printf("标识符 %s，深度 %d\n", ident.Name, len(stack))
    }
    return true  // 继续遍历子节点
})
```

#### unique 包: 更积极的回收

`unique` 包（Go 1.23 引入）现在使用更积极的回收策略。当 `unique.Handle[T]` 引用的值不再被使用时，内部去重表会更快地释放对应条目，降低内存占用。

```go
import "unique"

// unique.Make 对值进行去重
h1 := unique.Make("hello")
h2 := unique.Make("hello")
// h1 == h2 为 true（指向相同的底层值）

// Go 1.25: 当没有 Handle 引用某个值时，该值会更快被 GC 回收
```

---

## 废弃项 (Deprecations)

### go/ast 废弃函数

以下函数已被标记为废弃，建议迁移到更精确的替代方案：

```go
// 已废弃
ast.FilterPackage(pkg, filter)      // 使用 ast.FilterFile 逐文件过滤
ast.PackageExports(pkg)             // 使用 ast.FileExports 逐文件处理
ast.MergePackageFiles(pkg, mode)    // 使用独立的文件处理逻辑
```

### go/parser.ParseDir 废弃

```go
// 已废弃
pkgs, err := parser.ParseDir(fset, dir, filter, mode)

// 推荐替代：使用 os.ReadDir + parser.ParseFile
entries, _ := os.ReadDir(dir)
for _, e := range entries {
    if strings.HasSuffix(e.Name(), ".go") {
        f, err := parser.ParseFile(fset, filepath.Join(dir, e.Name()), nil, mode)
        // ...
    }
}
```

### crypto/elliptic 隐藏方法移除

`crypto/elliptic` 包中的未导出方法已被彻底移除。如果有代码通过反射或其他方式使用这些方法，将无法编译。

### GODEBUG runtimecontentionstacks 移除

`GODEBUG=runtimecontentionstacks=1` 设置已被移除。该功能在之前的版本中已被废弃。

---

## 平台变更 (Platform Changes)

### macOS 最低版本：12 Monterey

Go 1.25 要求 macOS 最低版本为 **macOS 12 Monterey**。macOS 11 Big Sur 及更早版本不再受支持。

### windows/arm: 最后一个版本

Go 1.25 是 **最后一个支持 `windows/arm`（32 位 ARM Windows）** 的版本。未来版本将移除该平台的支持。`windows/arm64` 不受影响。

### AMD64: GOAMD64=v3+ 的 FMA 支持

如前文编译器章节所述，`GOAMD64=v3` 及以上级别现在利用 FMA 指令。

```bash
# 检查 CPU 支持级别
# v1: 基线 (SSE2)
# v2: SSE4.2, POPCNT, etc.
# v3: AVX2, FMA, BMI, etc.
# v4: AVX-512
GOAMD64=v3 go build -o myapp ./cmd/myapp
```

### Loong64: race detector 和 cgo traceback

- `linux/loong64` 平台现在支持 **竞态检测器（race detector）**
- 支持 **cgo traceback**，可以在崩溃时输出包含 C 代码调用栈的完整追踪信息

```bash
# 在 loong64 上使用 race detector
GOOS=linux GOARCH=loong64 go test -race ./...
```

### RISC-V: plugin 构建模式和 rva23u64

- `linux/riscv64` 支持 **plugin 构建模式**
- 新增对 **rva23u64** 配置文件的支持（RISC-V Application Profile）

```bash
# RISC-V 上使用 plugin 模式
GOOS=linux GOARCH=riscv64 go build -buildmode=plugin -o myplugin.so ./plugin
```

---

## 快速迁移清单

升级到 Go 1.25 时，建议检查以下关键项：

| 检查项 | 重要程度 | 说明 |
|--------|---------|------|
| nil 指针解引用 | **高** | Go 1.21-1.24 的 bug 修复可能导致新 panic |
| TLS SHA-1 签名 | **高** | 默认禁止，需 `GODEBUG=tlssha1=1` 恢复 |
| GOMAXPROCS 行为 | **中** | 容器环境下自动调整，验证性能是否符合预期 |
| macOS 版本要求 | **中** | 最低 macOS 12 Monterey |
| windows/arm | **低** | 最后一个版本，需规划迁移 |
| go/ast 废弃 API | **低** | 迁移到文件级别的 API |
| `wg.Go` 新模式 | 建议 | 逐步替换 Add/Done 模式 |
| testing/synctest | 建议 | 用于时间相关测试 |
| Flight Recorder | 建议 | 用于生产环境诊断 |

---

## GODEBUG 设置速查表

| 设置 | 默认值 | 说明 |
|------|--------|------|
| `containermaxprocs` | 1 (启用) | 设为 0 禁用容器感知 GOMAXPROCS |
| `updatemaxprocs` | 1 (启用) | 设为 0 禁用周期性 GOMAXPROCS 更新 |
| `decoratemappings` | 1 (启用) | 设为 0 禁用 Linux VMA 命名 |
| `tlssha1` | 0 (禁止) | 设为 1 允许 TLS SHA-1 签名 |

---

> 本文档最后更新：2025 年 3 月。内容基于 Go 1.25 Release Notes 和相关提案整理。
> 请以 [Go 官方 Release Notes](https://go.dev/doc/go1.25) 为准。
