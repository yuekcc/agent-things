# Go 1.26 Reference (2026年2月发布)

> 本文档是 Go 1.26 版本的完整参考手册，涵盖语言变更、工具链改进、运行时优化、新标准库包以及重要的废弃项。

---

## 目录

1. [语言变更](#语言变更)
2. [工具链变更](#工具链变更)
3. [运行时变更](#运行时变更)
4. [编译器与链接器](#编译器与链接器)
5. [新增标准库包](#新增标准库包)
6. [标准库重大变更](#标准库重大变更)
7. [废弃项](#废弃项)
8. [GODEBUG 设置（将在 Go 1.27 中移除）](#godebug-设置将在-go-127-中移除)
9. [平台变更](#平台变更)

---

## 语言变更

### `new(expr)` — 表达式参数形式的 new

Go 1.26 对内建函数 `new` 进行了扩展：现在 `new()` 可以接受一个**表达式**作为参数，用于设置分配对象的初始值，并返回指向该值的指针。

此前，如果你需要一个指向某个值的指针（而非零值），必须先声明一个变量再取地址，代码非常冗长。这在 JSON 可选字段、Protobuf optional 字段等场景中极为常见。

**语法：**

```go
// 旧写法：需要临时变量
v := 42
p := &v

// Go 1.26 新写法：一行搞定
p := new(42)         // *int，值为 42
s := new("hello")    // *string，值为 "hello"
b := new(true)       // *bool，值为 true
```

**典型用例 — JSON 可选字段：**

```go
type Config struct {
    Timeout *int    `json:"timeout,omitempty"`
    Debug   *bool   `json:"debug,omitempty"`
    Name    *string `json:"name,omitempty"`
}

// 旧写法：极其冗长
timeout := 30
debug := true
name := "my-service"
cfg := Config{
    Timeout: &timeout,
    Debug:   &debug,
    Name:    &name,
}

// Go 1.26 新写法：简洁直观
cfg := Config{
    Timeout: new(30),
    Debug:   new(true),
    Name:    new("my-service"),
}
```

**与函数返回值配合使用：**

```go
func yearsSince(t time.Time) int {
    return int(time.Since(t).Hours() / 8760)
}

type Person struct {
    Born time.Time
    Age  *int
}

// new() 可以接受任意表达式，不仅仅是字面量
p := Person{
    Born: birthDate,
    Age:  new(yearsSince(birthDate)), // 返回 *int
}
```

**Protobuf optional 字段：**

```go
// protobuf 生成代码中经常出现 optional 字段为指针类型
req := &pb.CreateUserRequest{
    Name:     new("Alice"),
    Age:      new(int32(30)),
    Verified: new(true),
}
```

**要点总结：**
- `new(expr)` 返回 `*T`，其中 `T` 是 `expr` 的类型
- `new(T)` 旧语法（类型参数）仍然有效，返回指向零值的指针
- 编译器根据参数是类型还是表达式来区分两种用法
- 这是一个语法糖，不影响运行时性能

---

### 递归泛型类型约束 (Recursive Generic Type Constraints)

Go 1.26 放宽了泛型约束的限制：类型参数现在可以**引用其自身的约束类型**（即递归约束 / F-bounded polymorphism）。这使得许多原本无法表达的类型关系得以实现。

**基本语法：**

```go
// 类型参数 A 的约束 Adder[A] 中引用了 A 自身
type Adder[A Adder[A]] interface {
    Add(A) A
}
```

**数学类型示例：**

```go
// 定义递归约束接口
type Number[N Number[N]] interface {
    Add(N) N
    Mul(N) N
    Zero() N
}

// Vec2 实现 Number[Vec2]
type Vec2 struct{ X, Y float64 }

func (v Vec2) Add(other Vec2) Vec2 {
    return Vec2{v.X + other.X, v.Y + other.Y}
}

func (v Vec2) Mul(other Vec2) Vec2 {
    return Vec2{v.X * other.X, v.Y * other.Y}
}

func (v Vec2) Zero() Vec2 {
    return Vec2{}
}

// 泛型函数：由于递归约束，编译器知道 N 的方法返回的还是 N
func Sum[N Number[N]](values []N) N {
    var result N
    result = result.Zero()
    for _, v := range values {
        result = result.Add(v)
    }
    return result
}

func main() {
    vecs := []Vec2{{1, 2}, {3, 4}, {5, 6}}
    total := Sum(vecs) // Vec2{9, 12}
    fmt.Println(total)
}
```

**Builder 模式示例：**

```go
// 递归约束使得 Builder 链式调用可以保持具体类型
type Builder[B Builder[B]] interface {
    SetName(string) B
    SetAge(int) B
    Build() any
}

type UserBuilder struct {
    name string
    age  int
}

func (b UserBuilder) SetName(name string) UserBuilder {
    b.name = name
    return b
}

func (b UserBuilder) SetAge(age int) UserBuilder {
    b.age = age
    return b
}

func (b UserBuilder) Build() any {
    return User{Name: b.name, Age: b.age}
}

// 泛型函数中可以安全地链式调用
func Configure[B Builder[B]](b B, name string, age int) B {
    return b.SetName(name).SetAge(age) // 返回类型始终是 B
}
```

**Comparable/Orderable 模式：**

```go
type Comparable[T Comparable[T]] interface {
    CompareTo(T) int
}

type Orderable[T Orderable[T]] interface {
    Comparable[T]
    Less(T) bool
}

// 可以编写安全的排序泛型函数
func Sort[T Orderable[T]](slice []T) {
    slices.SortFunc(slice, func(a, b T) int {
        return a.CompareTo(b)
    })
}
```

**要点总结：**
- 解决了 Go 泛型长期缺失的 F-bounded polymorphism
- 编译器现在能理解 `T` 上的方法返回的仍是 `T`（而非接口类型）
- 适用场景：数学类型、Builder 模式、自比较类型、流畅接口
- 递归深度有限制（编译器会检测无限递归约束）

---

## 工具链变更

### `go fix rewrite` — 代码现代化工具

Go 1.26 引入了 `go fix` 的全新子命令 `rewrite`，这是一个基于 Go 分析框架（`golang.org/x/tools/go/analysis`）构建的**代码现代化工具**，可以自动将旧代码改写为最新的 Go 惯用写法。

**基本用法：**

```bash
# 对当前模块运行所有内置现代化改写
go fix rewrite ./...

# 查看可用的改写器列表
go fix rewrite -list

# 只运行特定改写器
go fix rewrite -fix=slices ./...

# 预览改动（不实际修改文件）
go fix rewrite -dry-run ./...

# 显示改动 diff
go fix rewrite -diff ./...
```

**内置现代化改写器（Modernizers）：**

| 改写器 | 功能 |
|--------|------|
| `slices` | 将 `sort.Slice` 等替换为 `slices.SortFunc` |
| `maps` | 使用 `maps.Keys`、`maps.Values` 等替换手写循环 |
| `errors` | 将 `errors.As` 替换为 `errors.AsType` |
| `fmtsprintf` | 简化不必要的 `fmt.Sprintf` 调用 |
| `rangeint` | 将 `for i := 0; i < n; i++` 替换为 `for i := range n` |
| `sortslice` | 将 `sort.Sort(sortType)` 替换为 `slices.SortFunc` |

**`//go:fix inline` 指令：**

库作者可以在函数上标注 `//go:fix inline`，让 `go fix rewrite` 自动将对该函数的调用内联展开：

```go
// 库代码（假设 v1 版本）
//go:fix inline
func OldHelper(s string) string {
    return strings.ToUpper(s)
}

// 用户代码（改写前）
result := pkg.OldHelper("hello")

// 运行 go fix rewrite 后自动变为
result := strings.ToUpper("hello")
```

**旧版 fixers 已移除：**

Go 1.26 移除了 `go fix` 中遗留的旧版 fixers（这些是为 Go 1.0 之前的代码迁移而设计的），包括 `buildtag`、`cftype`、`egltype`、`jnitype`、`netipv6zone` 等。如果仍需使用，请使用 Go 1.25 工具链。

---

### `go mod init` 默认版本

`go mod init` 现在会自动在 `go.mod` 文件中设置 Go 版本为 `go 1.(N-1).0`，其中 N 是当前工具链的主版本号。

```bash
# 使用 Go 1.26 工具链
$ go mod init example.com/myapp

# 生成的 go.mod 内容
module example.com/myapp

go 1.25.0
```

**设计意图：**
- 确保模块与上一个稳定版本兼容
- 避免无意间使用最新版特性导致兼容性问题
- 开发者可以手动修改为 `go 1.26.0` 以启用新特性

---

### `cmd/doc` 已移除

独立的 `cmd/doc` 命令已被移除。请使用 `go doc` 替代：

```bash
# 旧写法（不再可用）
$ doc fmt.Println

# 新写法
$ go doc fmt.Println
$ go doc -all fmt
$ go doc -src fmt.Println
```

---

### Pprof UI：火焰图为默认视图

`go tool pprof` 的 Web UI 现在默认展示**火焰图（flame graph）**，替代了之前的图形化调用关系图。火焰图更直观地展示了函数调用层级和 CPU 时间占比。

```bash
# 启动 pprof Web UI（现在默认显示火焰图）
go tool pprof -http=:8080 cpu.prof

# 如果需要旧版图形视图，可在 UI 中切换
```

---

### 编译引导（Bootstrap）要求 Go 1.24.6+

从 Go 1.26 开始，从源码编译 Go 工具链需要 Go 1.24.6 或更高版本作为引导编译器：

```bash
# 设置引导编译器路径
export GOROOT_BOOTSTRAP=/usr/local/go1.24.6

# 然后正常编译
cd $GOROOT/src
./all.bash
```

---

## 运行时变更

### Green Tea GC — 默认启用

Go 1.26 **默认启用了 Green Tea 垃圾回收器**。这是自 Go 1.5 并发 GC 以来最重大的 GC 改进。

**性能提升：**
- **10-40% GC 开销降低**（取决于工作负载）
- 在较新的 amd64 CPU 上（支持向量指令），**额外约 10% 的性能提升**
- 延迟更低更稳定，P99 尾延迟显著改善

**工作原理：**
- 重新设计了 GC 的标记和清扫阶段
- 利用现代 CPU 的 SIMD 向量指令加速对象扫描
- 优化了写屏障（write barrier）实现
- 改进了内存分配器与 GC 的协作

**禁用方式（仅用于调试/回归测试）：**

```bash
# 禁用 Green Tea GC
GOEXPERIMENT=nogreenteagc go build ./...

# 或在运行时禁用
GOEXPERIMENT=nogreenteagc ./myapp
```

> **警告：** `nogreenteagc` 实验标志将在 Go 1.27 中移除。如果遇到 GC 相关问题，请尽早在 Go issue tracker 上报告。

**基准测试对比：**

```go
// 以下是典型的 GC 压力测试，可以观察到显著改善
func BenchmarkGCPressure(b *testing.B) {
    for b.Loop() {
        data := make([][]byte, 10000)
        for i := range data {
            data[i] = make([]byte, 1024)
        }
        runtime.GC()
    }
}
```

---

### cgo 调用性能提升约 30%

Go 1.26 显著优化了 cgo 调用的开销，从 Go 调用 C 函数的性能提升约 30%。

```go
/*
#include <math.h>
*/
import "C"

// 此类 cgo 调用现在快了约 30%
func fastSqrt(x float64) float64 {
    return float64(C.sqrt(C.double(x)))
}
```

**优化方式：**
- 减少了 Go/C 栈切换的开销
- 优化了 cgo 调用的信号处理
- 改进了参数传递路径

---

### 堆基地址随机化 (Heap Base Address Randomization)

Go 1.26 在 64 位平台上引入了**堆基地址随机化**，作为安全增强措施。每次程序启动时，堆的起始地址都会随机化，使得攻击者更难利用内存布局的可预测性。

```bash
# 禁用堆基地址随机化（仅用于调试）
GOEXPERIMENT=norandomizedheapbase64 ./myapp
```

**影响：**
- 提升了对内存腐败漏洞的防御能力
- 对正常程序无可见性能影响
- 某些依赖固定内存布局的调试工具可能需要调整

---

### 实验性 Goroutine 泄漏检测

Go 1.26 引入了**实验性的 goroutine 泄漏检测**机制，利用 GC 可达性分析来识别"泄漏"的 goroutine（即不再被任何活跃代码引用但仍在运行的 goroutine）。

**启用方式：**

```bash
# 通过实验标志启用
GOEXPERIMENT=goroutineleakprofile ./myapp
```

**使用 pprof 端点：**

```go
import (
    "net/http"
    _ "net/http/pprof"
)

func main() {
    // 启动 pprof HTTP 服务
    go http.ListenAndServe(":6060", nil)

    // ... 应用代码 ...
}

// 访问 http://localhost:6060/debug/pprof/goroutineleak
// 即可查看疑似泄漏的 goroutine 信息
```

**特性：**
- **零运行时开销**（除非正在进行 profiling 采集）
- 利用 GC 的可达性分析，无需额外的 goroutine 追踪
- 提供泄漏 goroutine 的创建栈、当前阻塞位置等信息
- 计划在 Go 1.27 中**默认启用**

**在测试中使用：**

```go
func TestNoGoroutineLeak(t *testing.T) {
    // 记录测试开始时的 goroutine 数量
    before := runtime.NumGoroutine()

    // ... 运行被测代码 ...
    ctx, cancel := context.WithCancel(context.Background())
    go worker(ctx)
    cancel()
    time.Sleep(100 * time.Millisecond)

    after := runtime.NumGoroutine()
    if after > before {
        t.Errorf("possible goroutine leak: before=%d, after=%d", before, after)
    }
}
```

---

## 编译器与链接器

### 更多切片栈分配优化

Go 1.26 编译器扩展了逃逸分析的能力，**更多的切片现在可以分配在栈上**而非堆上。当编译器能证明切片的生命周期不超过当前函数时，会将其分配在栈上以避免 GC 压力。

```go
func process(data []byte) int {
    // 如果编译器能确定 buf 不逃逸，则分配在栈上
    buf := make([]byte, 256)
    copy(buf, data)
    return len(buf)
}

// 查看逃逸分析结果
// go build -gcflags='-m' ./...
```

### windows/arm64 内部链接支持 cgo

Windows ARM64 平台现在支持使用 cgo 时的**内部链接**（internal linking），不再强制要求外部链接器。这简化了 Windows ARM64 上的交叉编译和分发流程。

### ELF 二进制结构变更

Go 1.26 对 ELF（Linux/FreeBSD 等）二进制文件的结构进行了调整：

| 变更 | 说明 |
|------|------|
| 新增 `.go.module` section | 包含模块路径信息，便于工具识别 |
| 移除 `.gosymtab` section | 符号表信息已整合到其他 section |
| 优化 `.gopclntab` | 减小了 PC-line 表的体积 |

> **注意：** 依赖解析 Go ELF 二进制结构的第三方工具可能需要更新。

---

## 新增标准库包

### `crypto/hpke` — 混合公钥加密 (RFC 9180)

新增的 `crypto/hpke` 包实现了 **Hybrid Public Key Encryption（HPKE）**，这是 RFC 9180 定义的现代公钥加密标准，广泛用于 TLS ECH、MLS 消息传递协议等。

```go
package main

import (
    "crypto/hpke"
    "fmt"
    "log"
)

func main() {
    // 选择 HPKE 套件：KEM, KDF, AEAD
    suite := hpke.Suite{
        KEM:  hpke.KEM_X25519_HKDF_SHA256,
        KDF:  hpke.KDF_HKDF_SHA256,
        AEAD: hpke.AEAD_AES_128_GCM,
    }

    // 接收方生成密钥对
    publicKey, privateKey, err := suite.GenerateKeyPair()
    if err != nil {
        log.Fatal(err)
    }

    // 发送方：加密
    info := []byte("application context")
    sender, enc, err := suite.NewSender(publicKey, info)
    if err != nil {
        log.Fatal(err)
    }

    plaintext := []byte("Hello, HPKE!")
    aad := []byte("associated data")
    ciphertext, err := sender.Seal(plaintext, aad)
    if err != nil {
        log.Fatal(err)
    }

    // 接收方：解密
    receiver, err := suite.NewReceiver(privateKey, enc, info)
    if err != nil {
        log.Fatal(err)
    }

    decrypted, err := receiver.Open(ciphertext, aad)
    if err != nil {
        log.Fatal(err)
    }

    fmt.Println(string(decrypted)) // Hello, HPKE!
}
```

---

### `simd/archsimd`（实验性）— SIMD 向量操作

新增的 `simd/archsimd` 包提供了面向 amd64 架构的 **SIMD（单指令多数据）向量操作**。这是一个实验性包，API 可能在未来版本中变更。

```go
package main

import (
    "fmt"
    "simd/archsimd"
)

func main() {
    // 检查 CPU 是否支持 AVX2
    if !archsimd.HasAVX2() {
        fmt.Println("AVX2 not supported")
        return
    }

    // 使用 SIMD 进行批量浮点运算
    a := [8]float32{1, 2, 3, 4, 5, 6, 7, 8}
    b := [8]float32{8, 7, 6, 5, 4, 3, 2, 1}

    result := archsimd.AddFloat32x8(a, b)
    fmt.Println(result) // [9 9 9 9 9 9 9 9]

    // SIMD 字节搜索（用于高性能字符串/字节操作）
    data := []byte("Hello, World! Find the needle in the haystack.")
    idx := archsimd.IndexByte(data, 'n')
    fmt.Println(idx) // 找到 'n' 的位置
}
```

> **注意：** 该包当前仅支持 amd64 架构，其他架构将在后续版本中添加。

---

### `runtime/secret`（实验性）— 安全密钥擦除

新增的 `runtime/secret` 包提供了**安全擦除内存中加密数据**的能力，确保密钥等敏感数据在使用后被彻底清除，防止通过内存转储等方式泄漏。

```go
package main

import (
    "crypto/aes"
    "runtime/secret"
)

func encryptData(plaintext []byte) ([]byte, error) {
    // 创建安全密钥容器
    key := secret.New(make([]byte, 32))
    defer key.Destroy() // 函数返回时安全擦除密钥

    // 使用密钥（通过 Bytes() 访问原始数据）
    block, err := aes.NewCipher(key.Bytes())
    if err != nil {
        return nil, err
    }

    // ... 加密操作 ...
    _ = block
    return nil, nil
}
// key.Destroy() 被调用后，内存中的密钥数据被安全覆写为零
// 即使 GC 延迟回收，数据也已被擦除
```

**特性：**
- `Destroy()` 使用编译器/运行时保证的内存擦除（不会被优化掉）
- 即使发生 panic，通过 defer 也能确保擦除
- 支持与 `crypto/*` 包无缝集成

---

### `crypto/mlkem/mlkemtest` — ML-KEM 测试向量

新增的 `crypto/mlkem/mlkemtest` 包提供了 **ML-KEM（Module-Lattice Key Encapsulation Mechanism）** 的标准测试向量，用于验证 ML-KEM 实现的正确性。

```go
package mymlkem_test

import (
    "crypto/mlkem/mlkemtest"
    "testing"
)

func TestMLKEMVectors(t *testing.T) {
    // 使用标准测试向量验证 ML-KEM 768 实现
    vectors := mlkemtest.Vectors768()
    for _, v := range vectors {
        // 验证封装和解封装的正确性
        ct, ss, err := v.Encapsulate()
        if err != nil {
            t.Fatal(err)
        }
        ssDecap, err := v.Decapsulate(ct)
        if err != nil {
            t.Fatal(err)
        }
        if string(ss) != string(ssDecap) {
            t.Error("shared secret mismatch")
        }
    }
}
```

---

### `testing/cryptotest` — `SetGlobalRandom`

`testing/cryptotest` 包新增了 `SetGlobalRandom` 函数，允许在测试中替换全局随机数源：

```go
package mypkg_test

import (
    "testing"
    "testing/cryptotest"
)

func TestDeterministicRandom(t *testing.T) {
    // 设置确定性的全局随机数源用于测试
    cryptotest.SetGlobalRandom(t, deterministicReader)
    // 此后所有 crypto 包中的随机数调用将使用提供的 reader
    // 测试结束时自动恢复
}
```

---

## 标准库重大变更

### `errors.AsType[T]` — 关键新模式

这是 Go 1.26 中**最重要的标准库新增功能之一**。`errors.AsType[T]` 是 `errors.As` 的泛型、类型安全版本，更快且更符合人体工程学。

**旧写法 vs 新写法对比：**

```go
// ===== errors.As（旧写法）=====
// 需要先声明变量，类型写两遍，代码冗长
var appErr *AppError
if errors.As(err, &appErr) {
    fmt.Println(appErr.Code)
}

// ===== errors.AsType（Go 1.26 新写法）=====
// 泛型推断类型，返回值和 ok 模式，简洁安全
if appErr, ok := errors.AsType[*AppError](err); ok {
    fmt.Println(appErr.Code)
}
```

**完整示例：**

```go
package main

import (
    "errors"
    "fmt"
    "net"
    "os"
)

// 自定义错误类型
type ValidationError struct {
    Field   string
    Message string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation error: %s - %s", e.Field, e.Message)
}

type NotFoundError struct {
    Resource string
    ID       string
}

func (e *NotFoundError) Error() string {
    return fmt.Sprintf("%s not found: %s", e.Resource, e.ID)
}

func handleError(err error) {
    // 使用 errors.AsType — 类型安全，无需预声明变量
    if ve, ok := errors.AsType[*ValidationError](err); ok {
        fmt.Printf("字段 %s 验证失败: %s\n", ve.Field, ve.Message)
        return
    }

    if nfe, ok := errors.AsType[*NotFoundError](err); ok {
        fmt.Printf("资源 %s (ID: %s) 未找到\n", nfe.Resource, nfe.ID)
        return
    }

    // 也适用于标准库错误类型
    if netErr, ok := errors.AsType[*net.OpError](err); ok {
        fmt.Printf("网络操作 %s 失败: %v\n", netErr.Op, netErr.Err)
        return
    }

    if pathErr, ok := errors.AsType[*os.PathError](err); ok {
        fmt.Printf("路径 %s 操作失败: %v\n", pathErr.Path, pathErr.Err)
        return
    }

    fmt.Printf("未知错误: %v\n", err)
}

func main() {
    err := fmt.Errorf("wrapped: %w", &ValidationError{
        Field:   "email",
        Message: "格式不正确",
    })
    handleError(err) // 字段 email 验证失败: 格式不正确
}
```

**性能优势：**
- `errors.AsType[T]` 内部避免了 `reflect.New` 分配
- 在典型场景下比 `errors.As` 快约 20-40%
- 编译时类型检查，避免运行时类型错误

**`go fix rewrite` 自动迁移：**

```bash
# 自动将 errors.As 调用迁移为 errors.AsType
go fix rewrite -fix=errors ./...
```

---

### `bytes.Buffer.Peek` — 读取但不前进位置

`bytes.Buffer` 新增了 `Peek` 方法，允许查看缓冲区中的数据而不移动读取位置。

```go
package main

import (
    "bytes"
    "fmt"
)

func main() {
    buf := bytes.NewBufferString("Hello, World!")

    // Peek 查看前 5 个字节，不消耗数据
    peeked, err := buf.Peek(5)
    if err != nil {
        panic(err)
    }
    fmt.Println(string(peeked)) // "Hello"
    fmt.Println(buf.Len())      // 13（长度未变）

    // Read 消耗数据
    data := make([]byte, 5)
    buf.Read(data)
    fmt.Println(string(data)) // "Hello"
    fmt.Println(buf.Len())    // 8（长度减少）

    // Peek 现在看到的是剩余数据
    peeked, _ = buf.Peek(3)
    fmt.Println(string(peeked)) // ", W"
}
```

---

### `io.ReadAll` 优化 — 约 2 倍速度提升

`io.ReadAll` 经过重大优化，性能约提升 2 倍，内存分配减少约 50%。

```go
// 无需修改代码，直接获益
data, err := io.ReadAll(resp.Body)
// Go 1.26 中此操作显著更快，分配更少

// 底层优化：
// - 更智能的缓冲区增长策略
// - 减少了不必要的 copy 操作
// - 当 Reader 实现 Len() 时，直接预分配精确大小
```

---

### `fmt.Errorf` 优化 — 无格式化动词时更高效

当 `fmt.Errorf` 的格式字符串中**不包含任何格式化动词**（如 `%v`、`%w`）时，现在的内存分配与 `errors.New` 相当。

```go
// 旧版本：即使没有格式化动词，fmt.Errorf 也会做额外分配
err := fmt.Errorf("connection failed")

// Go 1.26：上述调用现在与下面的等价（分配量相同）
err := errors.New("connection failed")

// 仍然有格式化动词时，行为不变
err := fmt.Errorf("connection to %s failed: %w", host, cause)
```

---

### `reflect` 迭代器方法

`reflect` 包新增了多个迭代器方法，返回 Go 1.23+ 的 range-over-func 迭代器，便于遍历类型和值的各种元素。

```go
package main

import (
    "fmt"
    "reflect"
)

type MyStruct struct {
    Name    string `json:"name"`
    Age     int    `json:"age"`
    Email   string `json:"email"`
    private bool
}

func (m MyStruct) Hello() string { return "hello" }
func (m MyStruct) Greet() string { return "greet" }

func main() {
    t := reflect.TypeOf(MyStruct{})
    v := reflect.ValueOf(MyStruct{
        Name:  "Alice",
        Age:   30,
        Email: "alice@example.com",
    })

    // Type.Fields() — 遍历所有导出字段
    fmt.Println("=== Fields ===")
    for field := range t.Fields() {
        fmt.Printf("  %s: %v (tag: %s)\n",
            field.Name, field.Type, field.Tag.Get("json"))
    }

    // Type.Methods() — 遍历所有导出方法
    fmt.Println("=== Methods ===")
    for method := range t.Methods() {
        fmt.Printf("  %s: %v\n", method.Name, method.Type)
    }

    // Value.Fields() — 遍历字段值
    fmt.Println("=== Field Values ===")
    for field, value := range v.Fields() {
        fmt.Printf("  %s = %v\n", field.Name, value.Interface())
    }

    // Type.Ins() / Type.Outs() — 遍历函数参数和返回值类型
    funcType := reflect.TypeOf(func(a int, b string) (bool, error) {
        return true, nil
    })
    fmt.Println("=== Function Params ===")
    for param := range funcType.Ins() {
        fmt.Printf("  param: %v\n", param)
    }
    fmt.Println("=== Function Returns ===")
    for ret := range funcType.Outs() {
        fmt.Printf("  return: %v\n", ret)
    }
}
```

---

### `log/slog.NewMultiHandler` — 多处理器扇出

新增的 `slog.NewMultiHandler` 允许将日志事件**同时发送到多个 Handler**。

```go
package main

import (
    "log/slog"
    "os"
)

func main() {
    // 创建多个 Handler
    consoleHandler := slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
        Level: slog.LevelInfo,
    })
    fileHandler := slog.NewJSONHandler(logFile, &slog.HandlerOptions{
        Level: slog.LevelDebug,
    })

    // 使用 MultiHandler 同时输出到控制台和文件
    multiHandler := slog.NewMultiHandler(consoleHandler, fileHandler)
    logger := slog.New(multiHandler)

    // 日志会同时写入两个目标
    logger.Info("server started", "port", 8080)
    logger.Debug("debug info", "detail", "only in file")
    logger.Error("something failed", "err", err)
}
```

---

### `net` — 类型化拨号方法

`net.Dialer` 新增了带类型的拨号方法，返回具体的连接类型而非通用的 `net.Conn` 接口。所有方法都支持 `context.Context`。

```go
package main

import (
    "context"
    "fmt"
    "net"
    "time"
)

func main() {
    dialer := net.Dialer{
        Timeout: 5 * time.Second,
    }
    ctx := context.Background()

    // DialTCP — 返回 *net.TCPConn（而非 net.Conn）
    tcpConn, err := dialer.DialTCP(ctx, "tcp", nil, &net.TCPAddr{
        IP:   net.ParseIP("93.184.216.34"),
        Port: 80,
    })
    if err != nil {
        panic(err)
    }
    defer tcpConn.Close()
    // 可以直接调用 TCPConn 特有方法，无需类型断言
    tcpConn.SetNoDelay(true)
    tcpConn.SetKeepAlive(true)

    // DialUDP — 返回 *net.UDPConn
    udpConn, err := dialer.DialUDP(ctx, "udp", nil, &net.UDPAddr{
        IP:   net.ParseIP("8.8.8.8"),
        Port: 53,
    })
    if err != nil {
        panic(err)
    }
    defer udpConn.Close()
    udpConn.SetReadBuffer(1 << 20) // 直接调用 UDPConn 方法

    // DialIP — 返回 *net.IPConn
    // DialUnix — 返回 *net.UnixConn

    fmt.Println("连接成功")
}
```

---

### `net/http` 变更

#### `HTTP2Config.StrictMaxConcurrentRequests`

新增配置项，严格限制 HTTP/2 并发请求数：

```go
server := &http.Server{
    Addr: ":8443",
    HTTP2Config: &http.HTTP2Config{
        // 严格遵守 MaxConcurrentStreams 限制
        // 超过限制时返回 REFUSED_STREAM 而非排队
        StrictMaxConcurrentRequests: true,
        MaxConcurrentStreams:        100,
    },
}
```

#### `Transport.NewClientConn`

允许手动创建基于已有连接的 HTTP 客户端连接：

```go
// 从已有的 net.Conn 创建 HTTP 客户端连接
tlsConn, _ := tls.Dial("tcp", "example.com:443", tlsConfig)
clientConn := transport.NewClientConn(tlsConn)
resp, err := clientConn.RoundTrip(req)
```

#### `Client` 使用 `Request.Host` 确定 Cookie 作用域

`http.Client` 现在使用 `Request.Host` 字段（如果设置了的话）来确定 Cookie 的作用域，而非仅使用 URL 中的主机名。

```go
req, _ := http.NewRequest("GET", "http://backend:8080/api", nil)
req.Host = "api.example.com" // Cookie jar 将使用此值匹配 Cookie

client := &http.Client{Jar: jar}
resp, err := client.Do(req)
```

#### `ServeMux` 尾部斜杠重定向：307 vs 301

`ServeMux` 中尾部斜杠（trailing slash）的自动重定向行为更新：

```go
mux := http.NewServeMux()
mux.HandleFunc("/api/users/", handler) // 注册带尾部斜杠的路由

// GET /api/users → 301 Moved Permanently → /api/users/
// POST /api/users → 307 Temporary Redirect → /api/users/
// PUT /api/users  → 307 Temporary Redirect → /api/users/

// 307 保留原始请求方法，避免 POST 被重定向为 GET
```

#### `httptest.Server.Client()` 自动重定向到测试服务器

`httptest.Server.Client()` 返回的客户端现在自动将重定向目标限制在测试服务器范围内：

```go
func TestHandler(t *testing.T) {
    ts := httptest.NewServer(myHandler)
    defer ts.Close()

    // Client() 返回的客户端在跟随重定向时
    // 会自动将目标限制在测试服务器的地址范围内
    client := ts.Client()
    resp, err := client.Get(ts.URL + "/redirect")
    // 重定向只会指向 ts.URL，不会访问外部服务器
}
```

---

### `net/url.Parse` 更严格

`url.Parse` 现在会拒绝主机名中包含冒号（但不是端口号分隔符）的 URL：

```go
// Go 1.26 中以下解析会返回错误
_, err := url.Parse("http://host:name/path")
// err: invalid URL: colon in host

// 正常的端口号仍然可以
u, _ := url.Parse("http://host:8080/path") // 正常

// 如果需要恢复旧行为（不推荐）
// GODEBUG=urlstrictcolons=0 ./myapp
```

---

### `os.Process.WithHandle` — 访问内部进程句柄

新增的 `WithHandle` 方法允许访问操作系统的原生进程句柄：

```go
package main

import (
    "fmt"
    "os"
    "os/exec"
    "runtime"
)

func main() {
    cmd := exec.Command("sleep", "10")
    cmd.Start()

    process := cmd.Process

    // WithHandle 提供对底层 OS 句柄的访问
    process.WithHandle(func(handle uintptr) error {
        switch runtime.GOOS {
        case "linux":
            // handle 是 pidfd（Linux 5.3+）
            fmt.Printf("Linux pidfd: %d\n", handle)
            // 可以使用 pidfd 进行精确的进程操作
        case "windows":
            // handle 是 Windows HANDLE
            fmt.Printf("Windows Handle: %d\n", handle)
        }
        return nil
    })

    cmd.Process.Kill()
    cmd.Wait()
}
```

---

### `os/signal.NotifyContext` — 增强的取消上下文

`os/signal.NotifyContext` 现在使用 `context.CancelCauseFunc`，取消时携带信号信息：

```go
package main

import (
    "context"
    "fmt"
    "os"
    "os/signal"
    "syscall"
)

func main() {
    ctx, stop := signal.NotifyContext(
        context.Background(),
        syscall.SIGINT, syscall.SIGTERM,
    )
    defer stop()

    // 模拟等待信号
    <-ctx.Done()

    // 现在可以获取导致取消的具体信号
    cause := context.Cause(ctx)
    fmt.Printf("收到信号: %v\n", cause)
    // 输出类似: 收到信号: signal: interrupt

    // 可以根据信号类型做不同处理
    if sigErr, ok := cause.(*os.Signal); ok {
        switch (*sigErr) {
        case syscall.SIGINT:
            fmt.Println("用户中断，优雅退出...")
        case syscall.SIGTERM:
            fmt.Println("收到终止信号，立即退出...")
            os.Exit(1)
        }
    }
}
```

---

### `testing` 改进

#### `T.ArtifactDir` / `B.ArtifactDir` — 测试产物目录

新增 `-artifacts` 标志和 `ArtifactDir()` 方法，为测试提供标准化的产物输出目录：

```go
func TestGenerateReport(t *testing.T) {
    // ArtifactDir() 返回该测试专属的产物目录
    dir := t.ArtifactDir()

    // 将测试产物（截图、日志、报告等）写入该目录
    outputPath := filepath.Join(dir, "report.html")
    os.WriteFile(outputPath, reportHTML, 0644)

    // 将调试截图写入产物目录
    screenshotPath := filepath.Join(dir, "screenshot.png")
    saveScreenshot(screenshotPath)

    t.Logf("产物已保存到: %s", dir)
}

func BenchmarkWithArtifacts(b *testing.B) {
    dir := b.ArtifactDir()
    profilePath := filepath.Join(dir, "cpu.prof")
    // ... 保存 CPU profile 到产物目录
    _ = profilePath

    for b.Loop() {
        // ... 基准测试代码
    }
}
```

```bash
# 指定产物输出目录
go test -artifacts=/tmp/test-artifacts ./...

# 产物会按测试名分目录组织
# /tmp/test-artifacts/TestGenerateReport/report.html
# /tmp/test-artifacts/TestGenerateReport/screenshot.png
```

#### `B.Loop` 改进 — 不再阻止内联

`B.Loop` 在 Go 1.26 中进行了改进，不再阻止被测代码的内联优化，使得基准测试结果更准确：

```go
func BenchmarkInlined(b *testing.B) {
    // Go 1.24 引入的 b.Loop()
    // Go 1.26 中不再阻止 add 函数被内联
    for b.Loop() {
        result = add(1, 2) // add 现在可以被正常内联
    }
}

func add(a, b int) int {
    return a + b
}
```

---

### `image/jpeg` — 完全重写

`image/jpeg` 包经过**完全重写**，采用了更现代的算法：

```go
// 无需修改代码，直接获益
img, err := jpeg.Decode(reader)    // 更快的解码
err = jpeg.Encode(writer, img, opts) // 更快、更准确的编码
```

**改进：**
- 编码和解码速度显著提升
- DCT（离散余弦变换）精度更高
- 色彩空间转换更准确
- 更好的量化表处理

> **注意：** 由于算法改进，编码输出可能与旧版本**不完全一致**（bit-for-bit 不同）。如果测试依赖精确的 JPEG 输出字节，需要更新测试基准。

---

### 加密相关变更

#### 随机数参数被忽略

从 Go 1.26 开始，`crypto/*` 包中的 `random` / `rand` 参数**始终被忽略**，函数内部总是使用安全的 `crypto/rand.Reader`：

```go
// 以下两行在 Go 1.26 中完全等价
key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
key, err := ecdsa.GenerateKey(elliptic.P256(), nil) // rand 参数被忽略

// RSA 同理
privKey, err := rsa.GenerateKey(nil, 2048) // 始终使用安全随机源

// 如果确实需要自定义随机源（不推荐）
// GODEBUG=cryptocustomrand=1 ./myapp
```

#### TLS 后量子密钥交换默认启用

```go
// SecP256r1MLKEM768 和 SecP384r1MLKEM1024 现在默认启用
// 无需额外配置
tlsConfig := &tls.Config{
    // 默认 CurvePreferences 已包含 ML-KEM 混合密钥交换
    // 客户端和服务器都自动支持
}

// 如需显式控制
tlsConfig := &tls.Config{
    CurvePreferences: []tls.CurveID{
        tls.SecP256r1MLKEM768,    // 混合 ECDH + ML-KEM 768
        tls.SecP384r1MLKEM1024,   // 混合 ECDH + ML-KEM 1024
        tls.X25519,               // 经典密钥交换
    },
}
```

#### ML-KEM 封装性能提升约 18%

```go
// 使用 ML-KEM 进行密钥封装，现在快了约 18%
import "crypto/mlkem"

// ML-KEM 768
ek, dk, _ := mlkem.GenerateKey768()
ct, ss, _ := ek.Encapsulate() // 约 18% 更快
ssDecap, _ := dk.Decapsulate(ct)
```

#### SHA-3 零值可用

```go
import "crypto/sha3"

// Go 1.26 之前：必须调用 New 函数
h := sha3.New256()

// Go 1.26：零值即可使用
var h sha3.SHA3_256
h.Write([]byte("hello"))
sum := h.Sum(nil)
```

#### x509 `ExtKeyUsage` / `KeyUsage` String 方法

```go
import "crypto/x509"

// 现在可以直接打印可读的名称
eku := x509.ExtKeyUsageServerAuth
fmt.Println(eku.String()) // "ServerAuth"

ku := x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment
fmt.Println(ku.String()) // "DigitalSignature|KeyEncipherment"
```

---

### 其他标准库变更

#### `go/ast.ParseDirective` / `BasicLit.ValueEnd`

```go
import "go/ast"

// ParseDirective 解析 Go 指令注释
directive, err := ast.ParseDirective("//go:build linux && amd64")
// directive.Name == "build"
// directive.Text == "linux && amd64"

// BasicLit.ValueEnd 提供字面量值的结束位置
// 在代码分析和重写工具中非常有用
```

#### `net/netip.Prefix.Compare`

```go
import "net/netip"

p1 := netip.MustParsePrefix("10.0.0.0/8")
p2 := netip.MustParsePrefix("192.168.0.0/16")
p3 := netip.MustParsePrefix("10.0.0.0/16")

// Compare 提供稳定的排序
fmt.Println(p1.Compare(p2)) // -1（p1 < p2）
fmt.Println(p1.Compare(p3)) // -1（相同地址，/8 < /16）

// 可用于排序
prefixes := []netip.Prefix{p2, p3, p1}
slices.SortFunc(prefixes, netip.Prefix.Compare)
```

#### `runtime/metrics` — 调度器 goroutine 指标

```go
import "runtime/metrics"

// 新增的调度器相关指标
samples := []metrics.Sample{
    {Name: "/sched/goroutines/total:goroutines"},
    {Name: "/sched/goroutines/runnable:goroutines"},
    {Name: "/sched/goroutines/waiting:goroutines"},
}
metrics.Read(samples)

for _, s := range samples {
    fmt.Printf("%s: %v\n", s.Name, s.Value.Uint64())
}
```

#### `unicode.CategoryAliases`

```go
import "unicode"

// CategoryAliases 提供 Unicode 类别的别名映射
aliases := unicode.CategoryAliases
// 例如: "Letter" → "L", "Number" → "N" 等
for alias, category := range aliases {
    fmt.Printf("%s → %s\n", alias, category)
}
```

#### `unique` 包 — 更高效的回收

`unique` 包（Go 1.23 引入）在 Go 1.26 中进行了优化，对不再使用的唯一值的回收更加高效，减少了内存占用。

```go
import "unique"

// 用法不变，内部回收更高效
h1 := unique.Make("hello")
h2 := unique.Make("hello")
fmt.Println(h1 == h2) // true

// 当 h1 和 h2 都不可达时，底层字符串会被更及时地回收
```

---

## 废弃项

### `crypto/ecdsa` — `PublicKey` / `PrivateKey` 的 `big.Int` 字段

`crypto/ecdsa.PublicKey` 和 `crypto/ecdsa.PrivateKey` 中的 `big.Int` 字段已被废弃。应使用新的 `Bytes()` / `SetBytes()` 方法：

```go
import (
    "crypto/ecdsa"
    "crypto/elliptic"
)

// 废弃的用法（仍可编译，但会有 go vet 警告）
// 直接访问 PublicKey.X, PublicKey.Y (*big.Int)
// 直接访问 PrivateKey.D (*big.Int)

// 推荐的新用法
privKey, _ := ecdsa.GenerateKey(elliptic.P256(), nil)
pubBytes := privKey.PublicKey.Bytes()
privBytes := privKey.Bytes()

// 从字节恢复
var restoredPub ecdsa.PublicKey
restoredPub.SetBytes(elliptic.P256(), pubBytes)
```

---

### `crypto/rsa` — PKCS#1 v1.5 加密

PKCS#1 v1.5 加密函数已被废弃（由于已知的安全问题）：

```go
// 以下函数已废弃：
// - rsa.EncryptPKCS1v15
// - rsa.DecryptPKCS1v15
// - rsa.DecryptPKCS1v15SessionKey

// 推荐使用 OAEP 替代
ciphertext, err := rsa.EncryptOAEP(sha256.New(), nil, &publicKey, plaintext, nil)
plaintext, err := rsa.DecryptOAEP(sha256.New(), nil, privateKey, ciphertext, nil)
```

> **注意：** PKCS#1 v1.5 **签名**（`SignPKCS1v15` / `VerifyPKCS1v15`）未被废弃。

---

### `httputil.ReverseProxy.Director` — 使用 `Rewrite` 替代

`httputil.ReverseProxy.Director` 字段已废弃，应使用 `Rewrite` 函数：

```go
import "net/http/httputil"

// 废弃的写法
proxy := &httputil.ReverseProxy{
    Director: func(req *http.Request) {
        req.URL.Scheme = "http"
        req.URL.Host = "backend:8080"
        req.Host = "backend:8080"
    },
}

// Go 1.26 推荐的写法
proxy := &httputil.ReverseProxy{
    Rewrite: func(r *httputil.ProxyRequest) {
        r.SetURL(backendURL)
        r.SetXForwarded()
        r.Out.Host = r.In.Host // 保留原始 Host 头
    },
}
```

---

### `windows/arm` 端口已移除

Go 1.26 **彻底移除了 `windows/arm`（32位 ARM Windows）端口**。Windows ARM 用户应迁移到 `windows/arm64`。

```bash
# 不再支持
GOOS=windows GOARCH=arm go build  # 编译错误

# 使用 arm64 替代
GOOS=windows GOARCH=arm64 go build  # 正常
```

---

## GODEBUG 设置（将在 Go 1.27 中移除）

以下 GODEBUG 设置在 Go 1.26 中仍然可用，但将在 Go 1.27 中**永久移除**。如果你的代码依赖这些设置，请尽快迁移。

| GODEBUG 设置 | 说明 | 迁移建议 |
|---|---|---|
| `tlsunsafeekm` | 允许不安全的 TLS EKM（Exported Keying Material） | 使用标准 TLS EKM API |
| `tlsrsakex` | 允许 RSA 密钥交换（无前向保密） | 使用 ECDHE 密钥交换 |
| `tls10server` | 允许 TLS 1.0 服务端 | 升级到 TLS 1.2+ |
| `tls3des` | 允许 3DES 加密套件 | 使用 AES-GCM 或 ChaCha20-Poly1305 |
| `x509keypairleaf` | 控制 X.509 密钥对的叶证书解析 | 使用默认行为 |
| `gotypesalias` | 控制 `go/types` 中的类型别名行为 | 使用新的类型别名语义 |
| `asynctimerchan` | 控制 Timer/Ticker channel 的异步行为 | 使用 Go 1.23+ 的同步 Timer 语义 |

```bash
# 查看当前生效的 GODEBUG 设置
GODEBUG=help ./myapp

# 临时使用（不推荐长期依赖）
GODEBUG=tlsrsakex=1 ./legacy-app

# 在 go.mod 中设置（模块级别）
//go:debug tlsrsakex=1
```

---

## 平台变更

### macOS

- **macOS 12 Monterey 是最后支持的版本**
- Go 1.27 将要求 macOS 13 Ventura 或更高版本
- 如果需要支持 macOS 12，请锁定 Go 1.26.x

### FreeBSD

- **FreeBSD riscv64 已知损坏**：该端口存在问题，不建议在生产环境使用
- FreeBSD amd64 和 arm64 正常

### Windows

- **`windows/arm`（32位）端口已彻底移除**
- `windows/arm64` 正常支持且新增 cgo 内部链接

### PowerPC

- Go 1.26 是**最后一个支持 ELFv1 ABI** 的版本
- Go 1.27 将仅支持 ELFv2
- 影响旧版 POWER7 及之前的系统

```bash
# 检查当前系统的 ELF 版本
readelf -h /bin/ls | grep "OS/ABI"
```

### RISC-V

- **新增竞争检测器（race detector）支持**

```bash
# RISC-V 上现在可以使用 race detector
GOOS=linux GOARCH=riscv64 go test -race ./...
```

### S390X

- **切换到基于寄存器的调用约定**
- 函数调用性能提升，与 amd64/arm64 一致
- 对用户代码透明，但使用 `unsafe` 操作函数帧的代码可能受影响

### WebAssembly

- `sign-ext` 和 `satconv` 指令现在**无条件使用**
- 不再需要通过 `GOWASMFEATURES` 标志启用
- 要求 WebAssembly 运行时支持这些扩展（主流运行时已支持）

```bash
# 构建 WASM
GOOS=js GOARCH=wasm go build -o main.wasm ./cmd/app

# 或使用 wasip1
GOOS=wasip1 GOARCH=wasm go build -o main.wasm ./cmd/app
```

---

## 快速迁移检查清单

升级到 Go 1.26 时，请检查以下项：

- [ ] 运行 `go fix rewrite ./...` 利用新的代码现代化工具
- [ ] 将 `errors.As` 迁移为 `errors.AsType[T]`
- [ ] 检查是否依赖 `httputil.ReverseProxy.Director`（改用 `Rewrite`）
- [ ] 检查是否使用 `crypto/rsa` PKCS#1 v1.5 加密（改用 OAEP）
- [ ] 检查是否使用 `crypto/ecdsa` 的 `big.Int` 字段（改用 `Bytes()`）
- [ ] 检查是否依赖 `image/jpeg` 的精确字节输出
- [ ] 检查 `net/url.Parse` 中可能存在的 host 冒号问题
- [ ] 如果使用即将移除的 GODEBUG 设置，制定迁移计划
- [ ] 如果目标平台是 `windows/arm`，迁移到 `windows/arm64`
- [ ] 如果目标平台是 PowerPC ELFv1，准备迁移到 ELFv2
- [ ] 验证 Green Tea GC 在你的工作负载下表现正常
- [ ] 尝试启用 `GOEXPERIMENT=goroutineleakprofile` 检查 goroutine 泄漏

---

> **参考资料：** 本文档基于 Go 1.26 官方 Release Notes 整理。完整内容请参阅 [https://go.dev/doc/go1.26](https://go.dev/doc/go1.26)
