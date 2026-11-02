# Go 1.24 Reference (February 2025)

Go 1.24 于 2025 年 2 月发布，是一个重要的版本更新，带来了泛型类型别名、Swiss Tables map 实现、多个新标准库包以及大量工具链改进。

---

## Language Changes

### 泛型类型别名（Generic Type Aliases）

Go 1.24 完全支持泛型类型别名，类型别名现在可以拥有自己的类型参数。这解决了自 Go 1.18 引入泛型以来的一个长期限制。

```go
// 泛型类型别名 — 现在完全支持
type Set[T comparable] = map[T]bool

// 使用泛型类型别名
func NewSet[T comparable](items ...T) Set[T] {
    s := make(Set[T])
    for _, item := range items {
        s[item] = true
    }
    return s
}

// 实际使用
names := NewSet("Alice", "Bob", "Charlie")
fmt.Println(names["Alice"]) // true
```

```go
// 更复杂的泛型别名示例
type Pair[A, B any] = struct {
    First  A
    Second B
}

type Result[T any] = struct {
    Value T
    Err   error
}

// 为现有泛型类型创建别名
type MySlice[T any] = []T
type MyMap[K comparable, V any] = map[K]V
type MyChannel[T any] = chan T

func process[T any]() Result[T] {
    var zero T
    return Result[T]{Value: zero, Err: nil}
}
```

**禁用方式：** 如果遇到兼容性问题，可以通过 `GOEXPERIMENT=noaliastypeparams` 禁用泛型类型别名。注意：此开关将在 Go 1.25 中移除，届时泛型类型别名将成为唯一行为。

---

## Toolchain Changes

### `tool` 指令（go.mod 中的工具管理）

Go 1.24 在 `go.mod` 中引入了 `tool` 指令，用于声明项目所依赖的可执行工具，彻底取代了传统的 `tools.go` 空白导入模式。

**旧模式（tools.go — 不再推荐）：**

```go
//go:build tools

package tools

import (
    _ "golang.org/x/tools/cmd/stringer"
    _ "github.com/golangci/golangci-lint/cmd/golangci-lint"
)
```

**新模式（go.mod tool 指令）：**

```
module example.com/myproject

go 1.24

tool (
    golang.org/x/tools/cmd/stringer
    github.com/golangci/golangci-lint/cmd/golangci-lint
    google.golang.org/protobuf/cmd/protoc-gen-go
)

require (
    golang.org/x/tools v0.28.0
    // ...
)
```

**工具管理命令：**

```bash
# 添加工具依赖到 go.mod 的 tool 指令
go get -tool golang.org/x/tools/cmd/stringer
go get -tool github.com/golangci/golangci-lint/cmd/golangci-lint@latest

# 运行已声明的工具（无需记忆完整路径）
go tool stringer -type=Color
go tool golangci-lint run ./...

# 更新工具版本
go get tool  # 更新所有 tool 指令中声明的工具

# 安装工具
go install tool  # 安装所有 tool 指令中声明的工具到 $GOBIN
```

### 可执行文件缓存

`go run` 和 `go tool` 执行的二进制文件现在会被缓存在构建缓存中。首次运行后，后续调用会直接使用缓存版本，显著加速重复执行。

```bash
# 首次运行：编译 + 执行（较慢）
go run golang.org/x/tools/cmd/stringer -type=Color

# 再次运行：直接从缓存执行（极快）
go run golang.org/x/tools/cmd/stringer -type=Color
```

### JSON 输出增强

`go build`、`go install`、`go test` 现在支持更完善的 `-json` 标志，输出结构化 JSON 数据。

```bash
# 构建时输出 JSON 格式的构建事件
go build -json ./...

# 安装时输出 JSON 格式
go install -json ./cmd/server

# 测试的 JSON 输出也进一步改进
go test -json ./...
```

JSON 输出示例结构：

```json
{
    "ImportPath": "example.com/mypackage",
    "Action": "build",
    "Output": "...",
    "Elapsed": 1.234
}
```

### GOAUTH 环境变量

新的 `GOAUTH` 环境变量用于配置私有模块的身份认证，替代了之前需要配置 `.netrc` 或 `git config` 的方式。

```bash
# 设置 GOAUTH 用于私有模块认证
# 格式: GOAUTH="方式 参数"

# 使用 netrc 文件认证
export GOAUTH="netrc /home/user/.netrc"

# 使用 git 凭据辅助工具
export GOAUTH="gitcredentials"

# 自定义命令认证
export GOAUTH="command /path/to/auth-helper"

# 多个认证源（按顺序尝试）
export GOAUTH="netrc; gitcredentials"

# 使用 GOAUTH 下载私有模块
GOAUTH="netrc" go get private.example.com/internal/pkg@latest
```

### VCS 版本嵌入

构建信息中现在嵌入了更详细的 VCS（版本控制系统）版本信息。

```go
package main

import (
    "fmt"
    "runtime/debug"
)

func main() {
    info, ok := debug.ReadBuildInfo()
    if !ok {
        return
    }
    for _, setting := range info.Settings {
        switch setting.Key {
        case "vcs":
            fmt.Println("VCS:", setting.Value)         // git
        case "vcs.revision":
            fmt.Println("Revision:", setting.Value)     // abc123def456...
        case "vcs.time":
            fmt.Println("Time:", setting.Value)         // 2025-01-15T10:30:00Z
        case "vcs.modified":
            fmt.Println("Modified:", setting.Value)     // true/false
        }
    }
}
```

### GODEBUG=toolchaintrace=1

新增的调试选项，用于追踪工具链选择过程，帮助诊断工具链版本问题。

```bash
# 开启工具链选择追踪
GODEBUG=toolchaintrace=1 go build ./...

# 输出会显示工具链选择的完整过程
# 包括 go.mod 中的 toolchain 指令如何被解析、选择哪个版本等
```

### Cgo 改进：noescape 和 nocallback 注解

新增 `#cgo noescape` 和 `#cgo nocallback` 指令，用于向编译器提供更精确的 Cgo 调用信息，从而实现更好的优化。

```go
package mylib

/*
#cgo noescape myFunc
#cgo nocallback myFunc

// noescape: 告诉编译器 myFunc 不会让传入的 Go 指针逃逸到 C 堆
// nocallback: 告诉编译器 myFunc 不会回调 Go 代码

void myFunc(void *data, int len);
*/
import "C"

import "unsafe"

func CallMyFunc(data []byte) {
    // 因为有 noescape 注解，编译器知道 data 不会逃逸
    // 因为有 nocallback 注解，编译器知道不需要准备 Go 回调栈
    // 这两个注解组合可以显著减少 Cgo 调用的开销
    C.myFunc(unsafe.Pointer(&data[0]), C.int(len(data)))
}
```

### Vet 分析器改进

```bash
# tests 分析器：检测测试函数签名错误
# 例如 TestFoo(t testing.T) 应该是 TestFoo(t *testing.T)

# printf 分析器更新：更准确地检测格式化字符串问题

# buildtag 分析器：改进 //go:build 标签的检查

# copylock 分析器：改进对含有 sync 类型的值拷贝检测
```

### GOCACHEPROG 稳定化

`GOCACHEPROG` 环境变量现在是稳定特性（不再是实验性的），允许使用外部程序替代默认的文件系统构建缓存。

```bash
# 使用自定义缓存程序
export GOCACHEPROG=/path/to/my-cache-prog

# 这对于分布式构建缓存、云端缓存等场景非常有用
# 缓存程序通过 stdin/stdout 与 go 工具通信，使用 JSON 协议
```

### 编译器：禁止 Cgo 类型上定义方法

Go 1.24 编译器不再允许在 Cgo 生成的类型上定义方法。如果之前的代码在 `C.SomeType` 上定义了方法，现在需要使用包装类型。

```go
// 旧代码（Go 1.24 不再允许）：
// func (c C.MyStruct) String() string { ... }

// 新代码：使用包装类型
type MyStruct C.MyStruct

func (m MyStruct) String() string {
    return fmt.Sprintf("MyStruct{field: %d}", m.field)
}
```

### 链接器：GNU Build ID / UUID 生成

链接器现在默认为 ELF 二进制文件生成 GNU build ID，为 macOS 二进制文件生成 UUID。这有助于调试工具（如 `perf`、`addr2line`）识别和关联二进制文件。

```bash
# 查看生成的 build ID
go build -o myapp ./cmd/myapp
readelf -n myapp | grep "Build ID"
# 输出: Build ID: 7f3a2b1c...

# macOS 上查看 UUID
go build -o myapp ./cmd/myapp
otool -l myapp | grep -A 3 LC_UUID
```

### Bootstrap 要求

Go 1.24 的编译（从源码构建 Go 本身）需要 Go 1.22.6 或更高版本作为 bootstrap 工具链。

```bash
# 从源码构建 Go 1.24 需要先安装 Go 1.22.6+
export GOROOT_BOOTSTRAP=/path/to/go1.22.6
cd /path/to/go1.24/src
./all.bash
```

---

## Runtime & Performance

### Swiss Tables Map 实现（关键性能改进）

Go 1.24 将内置 `map` 的底层实现从传统的链式哈希表切换为 **Swiss Tables**。这是一项重大性能改进：

- 大型 map 操作速度提升约 **30%**
- 内存占用减少约 **70%**（对于大型 map）
- 小型 map 也有显著改善

Swiss Tables 使用 SIMD 指令（在支持的架构上）和更紧凑的内存布局，通过控制字节（control bytes）和分组探测（group probing）来实现高效查找。

```go
package main

import (
    "fmt"
    "runtime"
    "testing"
)

// Swiss Tables 对所有 map 操作都有提升
func main() {
    // 大型 map 受益最大
    largeMap := make(map[int]string, 1_000_000)
    for i := 0; i < 1_000_000; i++ {
        largeMap[i] = fmt.Sprintf("value-%d", i)
    }

    // 查找操作 ~30% 更快
    _ = largeMap[500000]

    // 遍历操作也更快
    for k, v := range largeMap {
        _ = k
        _ = v
    }

    // 删除操作性能改善
    delete(largeMap, 100)

    // 内存占用可通过 runtime 统计查看
    var m runtime.MemStats
    runtime.ReadMemStats(&m)
    fmt.Printf("HeapAlloc: %d MB\n", m.HeapAlloc/1024/1024)
}

// 基准测试展示差异
func BenchmarkMapLookup(b *testing.B) {
    m := make(map[int]int, 10000)
    for i := 0; i < 10000; i++ {
        m[i] = i
    }

    b.ResetTimer()
    for b.Loop() {  // Go 1.24 新 benchmark 模式
        _ = m[5000]
    }
}
```

**禁用方式：** 如果遇到问题，可以通过 `GOEXPERIMENT=noswissmap` 回退到旧实现。

```bash
# 临时禁用 Swiss Tables
GOEXPERIMENT=noswissmap go build ./...
GOEXPERIMENT=noswissmap go test ./...
```

### sync.Map 哈希字典树重写

`sync.Map` 使用哈希字典树（hash-trie）重新实现，性能提升约 **49%**。新实现在高并发读写场景下表现更佳。

```go
package main

import (
    "fmt"
    "sync"
)

func main() {
    var m sync.Map

    // 并发安全的存储 — 底层现在使用 hash-trie
    // 读操作和写操作的性能都显著提升
    m.Store("key1", "value1")
    m.Store("key2", "value2")

    // 加载操作 ~49% 更快
    if v, ok := m.Load("key1"); ok {
        fmt.Println(v)
    }

    // Range 遍历也受益于新实现
    m.Range(func(key, value any) bool {
        fmt.Printf("%v: %v\n", key, value)
        return true
    })

    // LoadOrStore, LoadAndDelete, CompareAndSwap 等操作均有提升
    actual, loaded := m.LoadOrStore("key3", "value3")
    fmt.Println(actual, loaded)
}
```

**禁用方式：** `GOEXPERIMENT=nosynchashtriemap`

### 小对象分配优化

Go 1.24 运行时对小对象分配进行了优化，减少了分配器的内部碎片和开销。

```go
// 频繁分配小对象的场景受益最大
type SmallStruct struct {
    X, Y int
    Name string
}

func processItems(items []string) []*SmallStruct {
    result := make([]*SmallStruct, len(items))
    for i, item := range items {
        // 这类小对象分配在 Go 1.24 中更快
        result[i] = &SmallStruct{X: i, Y: i * 2, Name: item}
    }
    return result
}
```

### 新 Spinbit Mutex

运行时内部的互斥锁实现改用 spinbit mutex，在低竞争场景下减少了上下文切换开销。

### CPU 开销降低

综合以上所有优化，Go 1.24 程序平均 CPU 开销降低了 **2-3%**。这是一个全局性的改善，不需要任何代码修改即可获益。

---

## New Packages

### `weak` 包：弱引用

新增 `weak` 包提供弱引用（weak references）支持。弱引用指向的对象不会阻止垃圾回收器回收该对象。

```go
package main

import (
    "fmt"
    "runtime"
    "weak"
)

type ExpensiveResource struct {
    Data []byte
    Name string
}

func main() {
    // 创建一个大对象
    resource := &ExpensiveResource{
        Data: make([]byte, 1024*1024), // 1MB
        Name: "my-resource",
    }

    // 创建弱引用
    weakRef := weak.Make(resource)

    // 通过弱引用访问对象（对象仍然存活）
    if r := weakRef.Value(); r != nil {
        fmt.Println("Resource alive:", r.Name)
    }

    // 移除强引用
    resource = nil

    // 强制垃圾回收
    runtime.GC()

    // 对象可能已被回收
    if r := weakRef.Value(); r != nil {
        fmt.Println("Resource still alive:", r.Name)
    } else {
        fmt.Println("Resource has been collected")
    }
}
```

```go
// 实际应用：使用弱引用实现缓存
type WeakCache[K comparable, V any] struct {
    mu    sync.Mutex
    items map[K]weak.Pointer[V]
}

func NewWeakCache[K comparable, V any]() *WeakCache[K, V] {
    return &WeakCache[K, V]{
        items: make(map[K]weak.Pointer[V]),
    }
}

func (c *WeakCache[K, V]) Get(key K) (*V, bool) {
    c.mu.Lock()
    defer c.mu.Unlock()

    wp, exists := c.items[key]
    if !exists {
        return nil, false
    }

    val := wp.Value()
    if val == nil {
        // 对象已被回收，清理条目
        delete(c.items, key)
        return nil, false
    }

    return val, true
}

func (c *WeakCache[K, V]) Set(key K, val *V) {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.items[key] = weak.Make(val)
}
```

### `crypto/mlkem` 包：后量子密钥封装

新增 `crypto/mlkem` 包实现了 ML-KEM（Module-Lattice-Based Key-Encapsulation Mechanism），符合 FIPS 203 标准。这是一种抗量子计算攻击的密钥封装机制。

```go
package main

import (
    "crypto/mlkem"
    "fmt"
)

func main() {
    // ML-KEM-768：安全级别约等于 AES-192
    dk768, err := mlkem.GenerateKey768()
    if err != nil {
        panic(err)
    }

    // 封装：生成共享密钥和密文
    sharedKey768, ciphertext768, err := mlkem.Encapsulate768(dk768.EncapsulationKey())
    if err != nil {
        panic(err)
    }

    // 解封装：从密文恢复共享密钥
    decapsulated768, err := dk768.Decapsulate(ciphertext768)
    if err != nil {
        panic(err)
    }

    fmt.Printf("ML-KEM-768 shared keys match: %v\n",
        string(sharedKey768) == string(decapsulated768))
    fmt.Printf("Shared key length: %d bytes\n", len(sharedKey768))
    fmt.Printf("Ciphertext length: %d bytes\n", len(ciphertext768))

    // ML-KEM-1024：安全级别约等于 AES-256（更高安全性）
    dk1024, err := mlkem.GenerateKey1024()
    if err != nil {
        panic(err)
    }

    sharedKey1024, ciphertext1024, err := mlkem.Encapsulate1024(dk1024.EncapsulationKey())
    if err != nil {
        panic(err)
    }

    decapsulated1024, err := dk1024.Decapsulate(ciphertext1024)
    if err != nil {
        panic(err)
    }

    fmt.Printf("ML-KEM-1024 shared keys match: %v\n",
        string(sharedKey1024) == string(decapsulated1024))
    fmt.Printf("Shared key length: %d bytes\n", len(sharedKey1024))
    fmt.Printf("Ciphertext length: %d bytes\n", len(ciphertext1024))
}
```

### `crypto/hkdf` 包：HMAC 密钥派生

新增 `crypto/hkdf` 包实现了基于 HMAC 的密钥派生函数，符合 RFC 5869 标准。之前需要使用 `golang.org/x/crypto/hkdf`。

```go
package main

import (
    "crypto/hkdf"
    "crypto/sha256"
    "encoding/hex"
    "fmt"
)

func main() {
    // 输入密钥材料
    secret := []byte("my-secret-key-material")
    salt := []byte("my-salt")
    info := []byte("my-context-info")

    // 使用 HKDF 派生密钥
    // Extract: 从输入密钥材料提取伪随机密钥
    prk := hkdf.Extract(sha256.New, secret, salt)
    fmt.Printf("PRK: %s\n", hex.EncodeToString(prk))

    // Expand: 将伪随机密钥扩展为所需长度的密钥
    key := make([]byte, 32) // 256-bit key
    expandReader := hkdf.Expand(sha256.New, prk, info)
    if _, err := expandReader.Read(key); err != nil {
        panic(err)
    }
    fmt.Printf("Derived key: %s\n", hex.EncodeToString(key))

    // 一步完成提取和扩展（常用简便方式）
    key2 := make([]byte, 32)
    kdf := hkdf.New(sha256.New, secret, salt, info)
    if _, err := kdf.Read(key2); err != nil {
        panic(err)
    }
    fmt.Printf("Derived key (one-step): %s\n", hex.EncodeToString(key2))

    // 派生多个密钥（用于不同用途）
    encKey := make([]byte, 32)
    macKey := make([]byte, 32)
    kdf2 := hkdf.New(sha256.New, secret, salt, []byte("encryption"))
    kdf2.Read(encKey)
    kdf3 := hkdf.New(sha256.New, secret, salt, []byte("authentication"))
    kdf3.Read(macKey)
    fmt.Printf("Encryption key: %s\n", hex.EncodeToString(encKey))
    fmt.Printf("MAC key: %s\n", hex.EncodeToString(macKey))
}
```

### `crypto/pbkdf2` 包：密码密钥派生

新增 `crypto/pbkdf2` 包实现了基于密码的密钥派生函数，符合 RFC 8018 标准。之前需要使用 `golang.org/x/crypto/pbkdf2`。

```go
package main

import (
    "crypto/pbkdf2"
    "crypto/sha256"
    "crypto/rand"
    "encoding/hex"
    "fmt"
)

func main() {
    password := []byte("user-password-123")

    // 生成随机盐
    salt := make([]byte, 16)
    rand.Read(salt)

    // 使用 PBKDF2 派生密钥
    // 参数: 密码, 盐, 迭代次数, 密钥长度, 哈希函数
    key := pbkdf2.Key(sha256.New, password, salt, 600_000, 32)

    fmt.Printf("Salt: %s\n", hex.EncodeToString(salt))
    fmt.Printf("Derived key: %s\n", hex.EncodeToString(key))

    // 验证密码：使用相同的盐和参数重新派生
    verifyKey := pbkdf2.Key(sha256.New, password, salt, 600_000, 32)
    fmt.Printf("Keys match: %v\n", hex.EncodeToString(key) == hex.EncodeToString(verifyKey))
}
```

### `crypto/sha3` 包：SHA-3 / SHAKE / cSHAKE

新增 `crypto/sha3` 包实现了 SHA-3 哈希函数族，符合 FIPS 202 标准。之前需要使用 `golang.org/x/crypto/sha3`。

```go
package main

import (
    "crypto/sha3"
    "encoding/hex"
    "fmt"
)

func main() {
    data := []byte("Hello, Go 1.24!")

    // SHA-3 固定输出哈希
    hash256 := sha3.Sum256(data)
    hash384 := sha3.Sum384(data)
    hash512 := sha3.Sum512(data)
    fmt.Printf("SHA3-256: %s\n", hex.EncodeToString(hash256[:]))
    fmt.Printf("SHA3-384: %s\n", hex.EncodeToString(hash384[:]))
    fmt.Printf("SHA3-512: %s\n", hex.EncodeToString(hash512[:]))

    // 使用 hash.Hash 接口（流式处理）
    h := sha3.New256()
    h.Write([]byte("Hello, "))
    h.Write([]byte("Go 1.24!"))
    result := h.Sum(nil)
    fmt.Printf("SHA3-256 (streaming): %s\n", hex.EncodeToString(result))

    // SHAKE：可变长度输出的扩展输出函数（XOF）
    shake128 := sha3.NewSHAKE128()
    shake128.Write(data)
    output := make([]byte, 64) // 任意长度输出
    shake128.Read(output)
    fmt.Printf("SHAKE128 (64 bytes): %s\n", hex.EncodeToString(output))

    shake256 := sha3.NewSHAKE256()
    shake256.Write(data)
    output256 := make([]byte, 32)
    shake256.Read(output256)
    fmt.Printf("SHAKE256 (32 bytes): %s\n", hex.EncodeToString(output256))

    // cSHAKE：定制化 SHAKE，支持功能名称和定制字符串
    cshake := sha3.NewCSHAKE128([]byte("MyFunction"), []byte("MyCustomization"))
    cshake.Write(data)
    cshakeOutput := make([]byte, 32)
    cshake.Read(cshakeOutput)
    fmt.Printf("cSHAKE128: %s\n", hex.EncodeToString(cshakeOutput))
}
```

### `testing/synctest` 包（实验性）：伪时钟测试

新增实验性的 `testing/synctest` 包，提供伪时钟（fake clock）支持，用于测试依赖时间的代码，无需实际等待。

```go
package mypackage

import (
    "context"
    "testing"
    "testing/synctest"
    "time"
)

// 被测试的函数：带超时的重试逻辑
func RetryWithBackoff(ctx context.Context, fn func() error) error {
    backoff := time.Second
    for {
        if err := fn(); err == nil {
            return nil
        }
        select {
        case <-ctx.Done():
            return ctx.Err()
        case <-time.After(backoff):
            backoff *= 2
            if backoff > 30*time.Second {
                backoff = 30 * time.Second
            }
        }
    }
}

func TestRetryWithBackoff(t *testing.T) {
    // synctest.Run 创建一个使用伪时钟的 goroutine 组
    synctest.Run(func() {
        attempts := 0
        fn := func() error {
            attempts++
            if attempts < 3 {
                return fmt.Errorf("not yet")
            }
            return nil
        }

        ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
        defer cancel()

        err := RetryWithBackoff(ctx, fn)
        if err != nil {
            t.Fatalf("unexpected error: %v", err)
        }
        if attempts != 3 {
            t.Fatalf("expected 3 attempts, got %d", attempts)
        }
    })
    // synctest.Run 内部的 time.After、time.Sleep 等都使用伪时钟
    // 测试不需要实际等待秒级别的退避时间
}

func TestTimeout(t *testing.T) {
    synctest.Run(func() {
        ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
        defer cancel()

        select {
        case <-ctx.Done():
            // 在伪时钟环境中，这几乎立即发生
            t.Log("context timed out as expected")
        }
    })
}
```

> 注意：`testing/synctest` 是实验性包，需要通过 `GOEXPERIMENT=synctest` 启用。API 可能在未来版本中发生变化。

---

## Major Standard Library Changes

### os.Root — 目录范围文件访问

新增 `os.Root` 类型，提供了一种安全的、限定在特定目录内的文件操作方式。所有通过 `Root` 进行的文件操作都被限制在根目录内部，防止路径遍历攻击（如 `../../etc/passwd`）。

```go
package main

import (
    "fmt"
    "os"
)

func main() {
    // 打开一个受限的根目录
    root, err := os.OpenRoot("/var/data/uploads")
    if err != nil {
        panic(err)
    }
    defer root.Close()

    // 在根目录内创建文件 — 安全
    f, err := root.Create("user-file.txt")
    if err != nil {
        panic(err)
    }
    f.Write([]byte("safe content"))
    f.Close()

    // 打开根目录内的文件
    f2, err := root.Open("user-file.txt")
    if err != nil {
        panic(err)
    }
    defer f2.Close()
    // 读取文件...

    // 路径遍历尝试会被阻止！
    _, err = root.Open("../../etc/passwd")
    if err != nil {
        fmt.Println("Path traversal blocked:", err)
        // 输出: Path traversal blocked: openat ...
    }

    // 在根目录内创建子目录
    err = root.Mkdir("subdir", 0755)
    if err != nil {
        fmt.Println("Mkdir error:", err)
    }

    // 获取文件信息
    info, err := root.Stat("user-file.txt")
    if err == nil {
        fmt.Printf("File: %s, Size: %d\n", info.Name(), info.Size())
    }

    // 符号链接不会逃逸出根目录
    // 即使符号链接指向根目录外部，也会被阻止
    _, err = root.Open("symlink-to-outside")
    if err != nil {
        fmt.Println("Symlink escape blocked:", err)
    }

    // 打开子目录作为新的 Root
    subRoot, err := root.OpenRoot("subdir")
    if err != nil {
        panic(err)
    }
    defer subRoot.Close()

    // subRoot 的操作被限制在 /var/data/uploads/subdir/ 内
    subRoot.Create("nested-file.txt")
}

// 实际应用：安全的文件上传处理器
func handleUpload(uploadDir string, filename string, data []byte) error {
    root, err := os.OpenRoot(uploadDir)
    if err != nil {
        return fmt.Errorf("open root: %w", err)
    }
    defer root.Close()

    // 即使 filename 包含 "../" 等路径遍历尝试，也是安全的
    f, err := root.Create(filename)
    if err != nil {
        return fmt.Errorf("create file: %w", err)
    }
    defer f.Close()

    _, err = f.Write(data)
    return err
}
```

### runtime.AddCleanup — 改进的终结器

`runtime.AddCleanup` 是对 `runtime.SetFinalizer` 的改进替代，解决了旧 API 的多个痛点：

- **多个清理函数**：同一对象可以注册多个清理函数（SetFinalizer 只能设置一个）
- **内部指针支持**：清理函数可以附加到对象的内部指针
- **无循环泄漏**：不会因为循环引用导致内存泄漏
- **更简洁的 API**：清理函数接收一个关联值而非对象本身

```go
package main

import (
    "fmt"
    "os"
    "runtime"
)

type Resource struct {
    fd   *os.File
    name string
    conn net.Conn
}

func NewResource(path string) *Resource {
    f, err := os.Open(path)
    if err != nil {
        panic(err)
    }

    r := &Resource{
        fd:   f,
        name: path,
    }

    // 注册清理函数 — 当 r 被垃圾回收时自动调用
    // 清理函数接收的是 f（关联值），而非 r 本身
    // 这避免了 SetFinalizer 中的循环引用问题
    runtime.AddCleanup(r, func(f *os.File) {
        fmt.Printf("Auto-closing file: %s\n", f.Name())
        f.Close()
    }, f)

    return r
}

// 可以为同一对象注册多个清理函数
func NewManagedResource() *Resource {
    r := &Resource{name: "managed"}

    // 清理函数 1：关闭文件
    if r.fd != nil {
        runtime.AddCleanup(r, func(f *os.File) {
            f.Close()
        }, r.fd)
    }

    // 清理函数 2：关闭网络连接
    if r.conn != nil {
        runtime.AddCleanup(r, func(c net.Conn) {
            c.Close()
        }, r.conn)
    }

    // 清理函数 3：记录日志
    runtime.AddCleanup(r, func(name string) {
        fmt.Printf("Resource %s cleaned up\n", name)
    }, r.name)

    return r
}

// AddCleanup 返回一个 Cleanup 句柄，可以用于提前取消清理
func ExampleCancelCleanup() {
    r := &Resource{name: "cancelable"}

    cleanup := runtime.AddCleanup(r, func(name string) {
        fmt.Printf("Cleanup for %s\n", name)
    }, r.name)

    // 手动清理后，取消自动清理
    r.manualClose()
    cleanup.Stop() // 取消注册的清理函数
}
```

**与 SetFinalizer 的对比：**

```go
// 旧方式 — runtime.SetFinalizer（不推荐）
// 问题: 只能设一个、不支持内部指针、循环引用泄漏
type OldResource struct {
    data []byte
}

func newOld() *OldResource {
    r := &OldResource{data: make([]byte, 1024)}
    runtime.SetFinalizer(r, func(r *OldResource) {
        // 终结器接收对象本身，可能导致对象复活
        fmt.Println("finalizing")
    })
    return r
}

// 新方式 — runtime.AddCleanup（推荐）
type NewResource struct {
    data []byte
}

func newNew() *NewResource {
    r := &NewResource{data: make([]byte, 1024)}
    runtime.AddCleanup(r, func(size int) {
        // 清理函数不接收对象本身，不会导致对象复活
        fmt.Printf("cleaned up resource of size %d\n", size)
    }, len(r.data))
    return r
}
```

### testing.B.Loop — 新基准测试模式

`testing.B.Loop` 提供了一种更简洁、更不易出错的基准测试编写方式。

```go
package main

import (
    "fmt"
    "strings"
    "testing"
)

// 旧模式 — 容易出错，需要手动处理多个细节
func BenchmarkOld(b *testing.B) {
    // 需要 b.ResetTimer() 来排除 setup 时间
    data := prepareData()
    b.ResetTimer()

    // 需要使用 sink 变量防止编译器优化掉结果
    var result string
    for i := 0; i < b.N; i++ {
        result = processData(data)
    }
    _ = result // sink — 防止优化
}

// 新模式 — 简洁、安全
func BenchmarkNew(b *testing.B) {
    data := prepareData()
    // 无需 b.ResetTimer() — Loop 自动处理
    // setup 代码在 Loop 之前，自动被排除在计时之外

    for b.Loop() {
        // 无需 sink 变量 — Loop 自动防止结果被优化
        processData(data)
    }
}

// 更多示例
func BenchmarkStringConcat(b *testing.B) {
    for b.Loop() {
        var s string
        for i := 0; i < 100; i++ {
            s += "x"
        }
    }
}

func BenchmarkStringBuilder(b *testing.B) {
    for b.Loop() {
        var sb strings.Builder
        for i := 0; i < 100; i++ {
            sb.WriteString("x")
        }
        sb.String()
    }
}

func BenchmarkWithSubBenchmarks(b *testing.B) {
    sizes := []int{10, 100, 1000, 10000}
    for _, size := range sizes {
        b.Run(fmt.Sprintf("size=%d", size), func(b *testing.B) {
            data := make([]int, size)
            // 无需 ResetTimer
            for b.Loop() {
                processSlice(data)
            }
        })
    }
}

// 重要行为差异：-count 标志
// 使用 b.Loop() 时，函数体只执行一次（per -count），而非多次
// go test -bench=. -count=5
// 旧模式: BenchmarkOld 函数被调用多次以校准 b.N
// 新模式: BenchmarkNew 函数只调用一次（per count），Loop 内部处理迭代

func prepareData() []byte    { return []byte("test data") }
func processData([]byte) string { return "result" }
func processSlice([]int)     {}
```

### encoding 接口：TextAppender 和 BinaryAppender

新增 `encoding.TextAppender` 和 `encoding.BinaryAppender` 接口，允许类型直接将编码结果追加到现有字节切片，避免分配新内存。

```go
package main

import (
    "encoding"
    "fmt"
    "net/netip"
    "time"
)

// 新接口定义
// type TextAppender interface {
//     AppendText(b []byte) ([]byte, error)
// }
//
// type BinaryAppender interface {
//     AppendBinary(b []byte) ([]byte, error)
// }

func main() {
    // 许多标准库类型现在实现了这些接口
    // 可以直接追加到已有 buffer，避免额外分配

    buf := make([]byte, 0, 256)

    // time.Time 实现了 TextAppender
    t := time.Now()
    buf, _ = t.AppendText(buf)
    buf = append(buf, ' ')

    // netip.Addr 实现了 TextAppender
    addr := netip.MustParseAddr("192.168.1.1")
    buf, _ = addr.AppendText(buf)

    fmt.Println(string(buf))

    // 在循环中复用 buffer — 零分配
    var result []byte
    times := []time.Time{
        time.Date(2025, 1, 1, 0, 0, 0, 0, time.UTC),
        time.Date(2025, 6, 15, 12, 0, 0, 0, time.UTC),
        time.Date(2025, 12, 31, 23, 59, 59, 0, time.UTC),
    }

    for _, t := range times {
        result = result[:0] // 复用底层数组
        result, _ = t.AppendText(result)
        fmt.Println(string(result))
    }
}

// 自定义类型实现 TextAppender
type UserID struct {
    Prefix string
    ID     uint64
}

func (u UserID) AppendText(b []byte) ([]byte, error) {
    b = append(b, u.Prefix...)
    b = append(b, '-')
    b = fmt.Appendf(b, "%d", u.ID)
    return b, nil
}

// 同时满足旧接口
func (u UserID) MarshalText() ([]byte, error) {
    return u.AppendText(nil)
}

// 确保接口满足
var _ encoding.TextAppender = UserID{}
var _ encoding.TextMarshaler = UserID{}
```

### strings/bytes 迭代器函数

`strings` 和 `bytes` 包新增了基于迭代器（iterator）模式的函数，返回 `iter.Seq[string]` 或 `iter.Seq[[]byte]`，可以用于 `for range` 循环。

```go
package main

import (
    "bytes"
    "fmt"
    "strings"
)

func main() {
    text := "line 1\nline 2\nline 3\n"

    // Lines: 按行迭代（保留换行符）
    fmt.Println("=== Lines ===")
    for line := range strings.Lines(text) {
        fmt.Printf("Line: %q\n", line)
    }
    // 输出:
    // Line: "line 1\n"
    // Line: "line 2\n"
    // Line: "line 3\n"

    // SplitSeq: 按分隔符拆分的迭代器版本
    fmt.Println("\n=== SplitSeq ===")
    csv := "apple,banana,cherry,date"
    for part := range strings.SplitSeq(csv, ",") {
        fmt.Printf("Part: %s\n", part)
    }

    // SplitAfterSeq: 保留分隔符的拆分迭代器
    fmt.Println("\n=== SplitAfterSeq ===")
    for part := range strings.SplitAfterSeq(csv, ",") {
        fmt.Printf("Part: %q\n", part)
    }
    // 输出:
    // Part: "apple,"
    // Part: "banana,"
    // Part: "cherry,"
    // Part: "date"

    // FieldsSeq: 按空白字符拆分的迭代器
    fmt.Println("\n=== FieldsSeq ===")
    spaced := "  hello   world   go  1.24  "
    for field := range strings.FieldsSeq(spaced) {
        fmt.Printf("Field: %q\n", field)
    }

    // FieldsFuncSeq: 自定义分隔条件的迭代器
    fmt.Println("\n=== FieldsFuncSeq ===")
    mixed := "hello123world456go789"
    for field := range strings.FieldsFuncSeq(mixed, func(r rune) bool {
        return r >= '0' && r <= '9'
    }) {
        fmt.Printf("Field: %q\n", field)
    }

    // bytes 包也有相同的迭代器函数
    fmt.Println("\n=== bytes.Lines ===")
    data := []byte("line A\nline B\nline C\n")
    for line := range bytes.Lines(data) {
        fmt.Printf("Bytes line: %q\n", line)
    }

    // 迭代器可以组合使用
    fmt.Println("\n=== 组合使用 ===")
    logData := "INFO: started\nERROR: failed\nINFO: retrying\nERROR: timeout\n"
    for line := range strings.Lines(logData) {
        line = strings.TrimRight(line, "\n")
        for field := range strings.SplitSeq(line, ": ") {
            fmt.Printf("  %q", field)
        }
        fmt.Println()
    }
}
```

### encoding/json `omitzero` 标签

新增 `omitzero` 结构体标签选项，用于在 JSON 编码时省略零值字段。与 `omitempty` 不同，`omitzero` 正确处理了 `time.Time` 等类型的零值判断。

```go
package main

import (
    "encoding/json"
    "fmt"
    "time"
)

// omitempty 的问题：对 time.Time 不正确
type EventOld struct {
    Name      string    `json:"name"`
    StartTime time.Time `json:"start_time,omitempty"`
    EndTime   time.Time `json:"end_time,omitempty"`
}

// omitzero 正确处理零值
type EventNew struct {
    Name      string    `json:"name"`
    StartTime time.Time `json:"start_time,omitzero"`  // 零值 time.Time 会被省略
    EndTime   time.Time `json:"end_time,omitzero"`    // 零值 time.Time 会被省略
    Count     int       `json:"count,omitzero"`       // 0 会被省略
    Tags      []string  `json:"tags,omitzero"`        // nil/空切片 会被省略
    Active    bool      `json:"active,omitzero"`      // false 会被省略
}

func main() {
    // 使用 omitempty — time.Time 零值不会被省略（因为 struct 不是 "empty"）
    oldEvent := EventOld{Name: "test"}
    data, _ := json.Marshal(oldEvent)
    fmt.Println("omitempty:", string(data))
    // 输出: {"name":"test","start_time":"0001-01-01T00:00:00Z","end_time":"0001-01-01T00:00:00Z"}
    // 问题: 零值 time.Time 仍然出现在 JSON 中

    // 使用 omitzero — 正确省略零值
    newEvent := EventNew{Name: "test"}
    data, _ = json.Marshal(newEvent)
    fmt.Println("omitzero:", string(data))
    // 输出: {"name":"test"}
    // 完美: 所有零值字段都被省略

    // 设置了值的字段正常输出
    fullEvent := EventNew{
        Name:      "conference",
        StartTime: time.Now(),
        Count:     42,
        Tags:      []string{"go", "tech"},
        Active:    true,
    }
    data, _ = json.Marshal(fullEvent)
    fmt.Println("full:", string(data))
}

// omitzero 也支持自定义类型的零值检测
// 如果类型实现了 IsZero() bool 方法，omitzero 会使用该方法
type OptionalValue struct {
    Value   int
    present bool
}

func (o OptionalValue) IsZero() bool {
    return !o.present
}

type Config struct {
    Name     string        `json:"name"`
    Timeout  time.Duration `json:"timeout,omitzero"`
    MaxRetry OptionalValue `json:"max_retry,omitzero"` // 使用 IsZero()
}

// omitzero 和 omitempty 可以同时使用
type Mixed struct {
    A string `json:"a,omitempty"`  // 空字符串时省略
    B string `json:"b,omitzero"`   // 零值(空字符串)时省略 — 行为与 omitempty 相同
    C int    `json:"c,omitempty"`  // 0 时省略
    D int    `json:"d,omitzero"`   // 0 时省略 — 行为与 omitempty 相同
    E time.Time `json:"e,omitempty"` // 不会正确省略零值 time.Time
    F time.Time `json:"f,omitzero"`  // 会正确省略零值 time.Time
}
```

### crypto/tls 改进

#### ECH（Encrypted Client Hello）服务端支持

Go 1.24 为 TLS 添加了 ECH 服务端支持。ECH 可以加密 TLS 握手中的 SNI（Server Name Indication），保护用户的访问隐私。

```go
package main

import (
    "crypto/tls"
    "log"
    "net/http"
)

func main() {
    // ECH 服务端配置
    echKeys, err := tls.GenerateECHKeyPair("public-facing.example.com")
    if err != nil {
        log.Fatal(err)
    }

    tlsConfig := &tls.Config{
        // ECH 服务端密钥配置
        EncryptedClientHelloKeys: []tls.EncryptedClientHelloKey{echKeys},
        Certificates:             []tls.Certificate{cert},
    }

    server := &http.Server{
        Addr:      ":443",
        TLSConfig: tlsConfig,
    }
    server.ListenAndServeTLS("", "")
}
```

#### X25519MLKEM768 默认启用

TLS 1.3 默认启用了 X25519MLKEM768 混合密钥交换（替代了之前的 Kyber），提供后量子安全保护。

```go
package main

import (
    "crypto/tls"
    "fmt"
)

func main() {
    // X25519MLKEM768 默认在 TLS 1.3 中启用
    // 无需额外配置

    config := &tls.Config{
        MinVersion: tls.VersionTLS13,
        // X25519MLKEM768 自动包含在默认的 CurvePreferences 中
    }

    // 如果需要禁用后量子密钥交换
    configNoHybrid := &tls.Config{
        MinVersion: tls.VersionTLS13,
        CurvePreferences: []tls.CurveID{
            tls.X25519,
            tls.CurveP256,
        },
        // 明确不包含 X25519MLKEM768
    }

    _ = config
    _ = configNoHybrid
}
```

#### Server.Protocols 和 Transport.Protocols

新增 `Protocols` 字段，提供了更清晰的方式来控制 HTTP 协议版本。

```go
package main

import (
    "crypto/tls"
    "net/http"
)

func main() {
    // 服务端：控制支持的协议
    server := &http.Server{
        Addr: ":8443",
        // 新增 Protocols 字段
        Protocols: &http.Protocols{
            HTTP1: true,  // 支持 HTTP/1.1
            HTTP2: true,  // 支持 HTTP/2
        },
        TLSConfig: &tls.Config{},
    }

    // 客户端：控制使用的协议
    transport := &http.Transport{
        Protocols: &http.Protocols{
            HTTP2: true,  // 仅使用 HTTP/2
        },
    }

    client := &http.Client{
        Transport: transport,
    }

    // 支持非加密 HTTP/2 (h2c)
    serverH2C := &http.Server{
        Addr: ":8080",
        Protocols: &http.Protocols{
            UnencryptedHTTP2: true, // 支持非加密 HTTP/2
        },
    }

    _ = server
    _ = client
    _ = serverH2C
}
```

### Other Changes

#### maphash.Comparable 和 maphash.WriteComparable

新增函数用于计算任意可比较类型值的哈希值。

```go
package main

import (
    "fmt"
    "hash/maphash"
)

func main() {
    // 为任意可比较类型计算哈希
    var seed maphash.Seed = maphash.MakeSeed()

    // Comparable: 返回值的哈希
    h1 := maphash.Comparable(seed, "hello")
    h2 := maphash.Comparable(seed, "hello")
    h3 := maphash.Comparable(seed, "world")

    fmt.Printf("hash(hello) == hash(hello): %v\n", h1 == h2) // true
    fmt.Printf("hash(hello) == hash(world): %v\n", h1 == h3) // false

    // 支持任何可比较类型
    type Point struct{ X, Y int }
    h4 := maphash.Comparable(seed, Point{1, 2})
    h5 := maphash.Comparable(seed, Point{1, 2})
    h6 := maphash.Comparable(seed, Point{3, 4})

    fmt.Printf("hash(Point{1,2}) == hash(Point{1,2}): %v\n", h4 == h5) // true
    fmt.Printf("hash(Point{1,2}) == hash(Point{3,4}): %v\n", h4 == h6) // false

    // WriteComparable: 向 Hash 写入可比较类型值
    var h maphash.Hash
    h.SetSeed(seed)
    maphash.WriteComparable(&h, "hello")
    maphash.WriteComparable(&h, 42)
    result := h.Sum64()
    fmt.Printf("Combined hash: %d\n", result)
}

// 实际应用: 自定义哈希集合
type HashSet[T comparable] struct {
    seed  maphash.Seed
    items map[uint64][]T
}

func NewHashSet[T comparable]() *HashSet[T] {
    return &HashSet[T]{
        seed:  maphash.MakeSeed(),
        items: make(map[uint64][]T),
    }
}
```

#### crypto/rand.Text() — 密码学安全随机字符串

新增 `crypto/rand.Text()` 函数，生成密码学安全的随机字符串，适用于 token、API key 等场景。

```go
package main

import (
    "crypto/rand"
    "fmt"
)

func main() {
    // 生成密码学安全的随机文本
    // 默认返回 26 字符的随机字符串（使用 base32 编码，约 130 位熵）
    token := rand.Text()
    fmt.Println("Random token:", token)
    // 输出类似: "5ln7g4qdmc2kzh3ab6ysfert2e"

    // 适用于各种 token 场景
    apiKey := rand.Text()
    sessionID := rand.Text()
    resetToken := rand.Text()

    fmt.Println("API Key:", apiKey)
    fmt.Println("Session ID:", sessionID)
    fmt.Println("Reset Token:", resetToken)
}
```

#### crypto/rand.Read 不再返回错误

`crypto/rand.Read()` 现在保证不会返回错误（在所有支持的平台上）。如果系统熵源不可用，程序会直接 panic 而非返回错误。

```go
package main

import (
    "crypto/rand"
    "fmt"
)

func main() {
    // 旧模式 — 需要检查错误
    buf := make([]byte, 32)
    _, err := rand.Read(buf)
    if err != nil {
        // 在 Go 1.24 中这永远不会发生
        panic(err)
    }

    // 新模式 — 可以安全忽略错误
    key := make([]byte, 32)
    rand.Read(key) // 永远不会返回错误
    fmt.Printf("Random key: %x\n", key)
}
```

#### go/types 迭代器方法

`go/types` 包新增了多个返回迭代器的方法，简化了对类型信息的遍历。

```go
package main

import (
    "go/types"
    "fmt"
)

func inspectInterface(iface *types.Interface) {
    // 新迭代器方法 — 更简洁
    for m := range iface.Methods() {
        fmt.Printf("Method: %s\n", m.Name())
    }

    for t := range iface.EmbeddedTypes() {
        fmt.Printf("Embedded: %s\n", t)
    }
}

func inspectStruct(s *types.Struct) {
    for field := range s.Fields() {
        fmt.Printf("Field: %s %s\n", field.Name(), field.Type())
    }
}
```

#### text/template：支持 range-over-func 和 range-over-int

模板引擎现在支持对函数和整数进行 range 迭代。

```go
package main

import (
    "os"
    "text/template"
)

func main() {
    // range-over-int: 迭代整数
    tmpl1 := template.Must(template.New("int").Parse(
        `{{range $i := 5}}Item {{$i}}
{{end}}`))
    tmpl1.Execute(os.Stdout, nil)
    // 输出:
    // Item 0
    // Item 1
    // Item 2
    // Item 3
    // Item 4

    // range-over-func: 迭代函数返回的序列
    // 支持 func(yield func(V) bool) 形式的迭代器函数
    data := map[string]any{
        "Items": func(yield func(string) bool) {
            items := []string{"apple", "banana", "cherry"}
            for _, item := range items {
                if !yield(item) {
                    return
                }
            }
        },
    }

    tmpl2 := template.Must(template.New("func").Parse(
        `{{range $item := .Items}}Fruit: {{$item}}
{{end}}`))
    tmpl2.Execute(os.Stdout, data)
}
```

#### T.Context() 和 B.Context()

测试中新增 `Context()` 方法，返回一个在测试结束时自动取消的 context。

```go
package mypackage

import (
    "context"
    "testing"
    "time"
)

func TestWithContext(t *testing.T) {
    // T.Context() 返回一个 context，在测试结束时自动取消
    ctx := t.Context()

    // 用于需要 context 的函数
    result, err := fetchWithContext(ctx, "https://example.com")
    if err != nil {
        t.Fatal(err)
    }
    t.Log(result)

    // 也适用于子测试
    t.Run("subtest", func(t *testing.T) {
        subCtx := t.Context()
        // subCtx 在子测试结束时取消
        doWork(subCtx)
    })
}

func BenchmarkWithContext(b *testing.B) {
    // B.Context() 在基准测试中也可用
    ctx := b.Context()

    for b.Loop() {
        processWithContext(ctx)
    }
}

// 不再需要手动创建和取消 context
// 旧模式:
func TestOldPattern(t *testing.T) {
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel() // 需要手动取消

    doWork(ctx)
}

// 新模式:
func TestNewPattern(t *testing.T) {
    ctx := t.Context() // 自动在测试结束时取消
    doWork(ctx)
}

func fetchWithContext(ctx context.Context, url string) (string, error) { return "", nil }
func doWork(ctx context.Context) {}
func processWithContext(ctx context.Context) {}
```

#### T.Chdir 和 B.Chdir

新增方法用于在测试期间安全地切换工作目录，测试结束后自动恢复。

```go
package mypackage

import (
    "os"
    "testing"
)

func TestChdir(t *testing.T) {
    // 切换到临时目录，测试结束后自动恢复
    tmpDir := t.TempDir()
    t.Chdir(tmpDir)

    // 当前工作目录现在是 tmpDir
    cwd, _ := os.Getwd()
    t.Logf("Current dir: %s", cwd) // 输出 tmpDir 路径

    // 可以安全地创建文件等
    os.WriteFile("test.txt", []byte("hello"), 0644)

    // 测试结束后，工作目录自动恢复到原来的位置
}

func TestChdirNested(t *testing.T) {
    t.Chdir("/tmp/test1")
    t.Run("sub", func(t *testing.T) {
        t.Chdir("/tmp/test2")
        // 这里工作目录是 /tmp/test2
    })
    // 子测试结束后恢复到 /tmp/test1
}

func BenchmarkChdir(b *testing.B) {
    tmpDir := b.TempDir()
    b.Chdir(tmpDir)

    for b.Loop() {
        // 在临时目录中执行操作
        os.ReadDir(".")
    }
}
```

#### slog.DiscardHandler

新增 `slog.DiscardHandler`，用于丢弃所有日志消息。适用于测试或需要禁用日志的场景。

```go
package main

import (
    "log/slog"
)

func main() {
    // 使用 DiscardHandler 丢弃所有日志
    logger := slog.New(slog.DiscardHandler)
    logger.Info("this message is discarded")
    logger.Error("this error is also discarded")

    // 常见用途: 在测试中禁用日志输出
    // 或在不需要日志的场景中提供空日志器
}

// 在测试中使用
func NewService(logger *slog.Logger) *Service {
    if logger == nil {
        logger = slog.New(slog.DiscardHandler)
    }
    return &Service{logger: logger}
}

type Service struct {
    logger *slog.Logger
}
```

#### net: ListenConfig MPTCP 默认启用（Linux）

在 Linux 上，`net.ListenConfig` 默认启用 MPTCP（Multipath TCP），允许 TCP 连接使用多个网络路径。

```go
package main

import (
    "context"
    "net"
    "net/http"
)

func main() {
    // Linux 上 MPTCP 默认启用
    lc := net.ListenConfig{}

    // 此监听器将自动支持 MPTCP（如果内核支持）
    ln, err := lc.Listen(context.Background(), "tcp", ":8080")
    if err != nil {
        panic(err)
    }
    defer ln.Close()

    // 如果需要显式禁用 MPTCP
    lcNoMPTCP := net.ListenConfig{
        // 设置 Control 函数来禁用 MPTCP
    }
    _ = lcNoMPTCP

    // HTTP 服务器也自动受益
    server := &http.Server{Addr: ":8443"}
    server.ListenAndServeTLS("cert.pem", "key.pem")
}
```

#### crypto/ecdsa: RFC 6979 确定性签名

ECDSA 签名现在默认使用 RFC 6979 确定性方案，对相同的输入总是产生相同的签名。

```go
package main

import (
    "crypto/ecdsa"
    "crypto/elliptic"
    "crypto/rand"
    "crypto/sha256"
    "fmt"
)

func main() {
    // 生成密钥
    key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)

    // 对相同数据签名两次
    hash := sha256.Sum256([]byte("hello"))

    sig1, _ := ecdsa.SignASN1(rand.Reader, key, hash[:])
    sig2, _ := ecdsa.SignASN1(rand.Reader, key, hash[:])

    // Go 1.24: 使用 RFC 6979 确定性签名
    // 相同密钥 + 相同数据 = 相同签名
    fmt.Printf("Signatures equal: %v\n", string(sig1) == string(sig2))

    // 验证签名
    valid := ecdsa.VerifyASN1(&key.PublicKey, hash[:], sig1)
    fmt.Printf("Signature valid: %v\n", valid)
}
```

#### crypto/rsa: 最小 1024 位密钥

Go 1.24 要求 RSA 密钥最小为 1024 位。尝试使用更短的密钥会返回错误。

```go
package main

import (
    "crypto/rsa"
    "crypto/rand"
    "fmt"
)

func main() {
    // 1024 位以上 — 正常
    key1024, err := rsa.GenerateKey(rand.Reader, 1024)
    if err != nil {
        fmt.Println("1024-bit error:", err)
    } else {
        fmt.Println("1024-bit key generated successfully")
    }

    // 推荐使用 2048 位或更高
    key2048, err := rsa.GenerateKey(rand.Reader, 2048)
    if err != nil {
        fmt.Println("2048-bit error:", err)
    } else {
        fmt.Println("2048-bit key generated successfully")
    }

    // 512 位 — Go 1.24 中被拒绝
    // 使用过短密钥的签名/加密操作将返回错误
    _ = key1024
    _ = key2048
}
```

#### FIPS 140-3 合规支持

Go 1.24 增加了对 FIPS 140-3 合规性的支持，使得 Go 程序可以在需要 FIPS 认证的环境中运行。

```go
package main

import (
    "crypto/tls"
)

func main() {
    // Go 1.24 的加密库经过了 FIPS 140-3 验证
    // 使用标准库的加密包即自动符合 FIPS 要求

    // FIPS 合规的 TLS 配置示例
    tlsConfig := &tls.Config{
        MinVersion: tls.VersionTLS12,
        CipherSuites: []uint16{
            tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
            tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
            tls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
            tls.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
        },
    }

    _ = tlsConfig

    // FIPS 模式可以通过构建标签或环境变量启用
    // 具体配置取决于部署环境
}
```

---

## Deprecations

### crypto/cipher 废弃函数

以下函数已被正式废弃，不建议使用：

```go
package main

import (
    "crypto/aes"
    "crypto/cipher"
)

func main() {
    block, _ := aes.NewCipher(make([]byte, 32))

    // 已废弃 — 不要使用
    // cipher.NewOFB(block, iv)       // OFB 模式
    // cipher.NewCFBEncrypter(block, iv) // CFB 加密
    // cipher.NewCFBDecrypter(block, iv) // CFB 解密

    // 推荐替代方案：使用 AEAD 模式（如 GCM）
    aead, err := cipher.NewGCM(block)
    if err != nil {
        panic(err)
    }

    nonce := make([]byte, aead.NonceSize())
    plaintext := []byte("sensitive data")
    ciphertext := aead.Seal(nil, nonce, plaintext, nil)
    _ = ciphertext
}
```

### runtime.GOROOT() 废弃

`runtime.GOROOT()` 已被废弃。应该使用 `go env GOROOT` 命令获取 Go 安装路径。

```go
package main

import (
    "fmt"
    "os/exec"
    "runtime"
    "strings"
)

func main() {
    // 已废弃
    goroot := runtime.GOROOT()
    fmt.Println("Deprecated GOROOT():", goroot)

    // 推荐方式
    cmd := exec.Command("go", "env", "GOROOT")
    out, err := cmd.Output()
    if err == nil {
        fmt.Println("Recommended:", strings.TrimSpace(string(out)))
    }
}
```

### runtime.SetFinalizer 不再推荐

虽然没有正式废弃，但 `runtime.SetFinalizer` 已被明确标记为不推荐使用。应改用 `runtime.AddCleanup`。

```go
// 不推荐
runtime.SetFinalizer(obj, func(o *MyObj) {
    o.Close()
})

// 推荐
runtime.AddCleanup(obj, func(handle *os.File) {
    handle.Close()
}, obj.file)
```

### math/rand.Seed() 成为空操作

`math/rand.Seed()` 现在是完全的空操作（no-op），不会产生任何效果。Go 运行时自动为全局随机数生成器提供安全的种子。

```go
package main

import (
    "math/rand"
    "fmt"
)

func main() {
    // 这行代码不再有任何效果
    rand.Seed(42) // no-op，编译器可能会发出警告

    // Go 1.24 中，全局 rand 自动使用安全种子
    // 每次运行产生不同的随机数
    fmt.Println(rand.Intn(100))

    // 如果需要可重现的随机数序列，使用 rand.New
    rng := rand.New(rand.NewSource(42))
    fmt.Println(rng.Intn(100)) // 总是产生相同的结果
}
```

### x509sha1 GODEBUG 开关移除

`GODEBUG=x509sha1=1` 开关已被完全移除。使用 SHA-1 签名的 X.509 证书不再被信任（自签名证书除外）。

```go
// 以下方式不再有效
// GODEBUG=x509sha1=1 go run main.go

// 必须确保所有证书使用 SHA-256 或更强的哈希算法
// SHA-1 证书将导致验证失败
```

---

## Platform Changes

### Linux 最低内核版本 3.2

Go 1.24 要求 Linux 内核版本 3.2 或更高。低于此版本的内核不再受支持。

### macOS 支持

macOS 11 (Big Sur) 是 Go 1.24 支持的最后一个最低版本。Go 1.25 将要求 macOS 12 (Monterey) 或更高版本。

```bash
# 检查 macOS 版本
sw_vers
# ProductVersion: 11.x 仍然支持
# Go 1.25 将要求 12.x+
```

### WebAssembly 改进

#### go:wasmexport 指令

新增 `go:wasmexport` 编译指令，允许 Go 函数被导出到 WebAssembly 模块的导出表中，可以被宿主环境直接调用。

```go
package main

import "fmt"

// 将 Go 函数导出为 WASM 导出函数
//go:wasmexport add
func add(a, b int32) int32 {
    return a + b
}

//go:wasmexport greet
func greet() {
    fmt.Println("Hello from Go WASM!")
}

//go:wasmexport fibonacci
func fibonacci(n int32) int32 {
    if n <= 1 {
        return n
    }
    return fibonacci(n-1) + fibonacci(n-2)
}

func main() {}
```

```javascript
// JavaScript 端调用导出的 Go 函数
const go = new Go();
const result = await WebAssembly.instantiateStreaming(
    fetch("main.wasm"),
    go.importObject
);
await go.run(result.instance);

// 调用导出的函数
const sum = result.instance.exports.add(3, 4);
console.log("Sum:", sum); // 7

result.instance.exports.greet(); // Hello from Go WASM!

const fib = result.instance.exports.fibonacci(10);
console.log("Fibonacci(10):", fib); // 55
```

#### Reactor 模式

WebAssembly 现在支持 reactor 模式，允许创建长期运行的 WASM 模块（而非一次性执行后退出）。

```go
//go:build wasip1

package main

// reactor 模式下，_start 不会退出
// 模块保持活跃，等待宿主调用导出函数

//go:wasmexport process
func process(input int32) int32 {
    // 每次调用都可以处理请求
    return input * 2
}

//go:wasmexport cleanup
func cleanup() {
    // 清理资源
}

func main() {
    // 在 reactor 模式下，main 返回后模块不会终止
    // 导出函数仍然可以被调用
}
```

### windows/arm 标记为 broken

`GOOS=windows GOARCH=arm` 组合已被标记为 broken（损坏）。如果需要在 Windows ARM 设备上运行 Go 程序，应使用 `GOARCH=arm64`。

```bash
# 不推荐（标记为 broken）
GOOS=windows GOARCH=arm go build

# 推荐替代方案
GOOS=windows GOARCH=arm64 go build
```

---

## Quick Reference

### 环境变量速查

| 变量 | 用途 |
|------|------|
| `GOEXPERIMENT=noswissmap` | 禁用 Swiss Tables map 实现 |
| `GOEXPERIMENT=nosynchashtriemap` | 禁用 sync.Map hash-trie 实现 |
| `GOEXPERIMENT=noaliastypeparams` | 禁用泛型类型别名 |
| `GOEXPERIMENT=synctest` | 启用 testing/synctest 实验性包 |
| `GOAUTH` | 私有模块认证配置 |
| `GODEBUG=toolchaintrace=1` | 工具链选择追踪 |
| `GOCACHEPROG` | 自定义构建缓存程序 |

### 新包速查

| 包 | 用途 |
|----|------|
| `weak` | 弱引用 |
| `crypto/mlkem` | ML-KEM 后量子密钥封装 (FIPS 203) |
| `crypto/hkdf` | HMAC 密钥派生 (RFC 5869) |
| `crypto/pbkdf2` | 密码密钥派生 (RFC 8018) |
| `crypto/sha3` | SHA-3 / SHAKE / cSHAKE (FIPS 202) |
| `testing/synctest` | 伪时钟测试（实验性） |

### 关键性能改进

| 改进项 | 效果 |
|--------|------|
| Swiss Tables map | 大型 map ~30% 更快，内存减少 ~70% |
| sync.Map hash-trie | ~49% 更快 |
| 小对象分配优化 | 减少分配器开销 |
| Spinbit mutex | 低竞争下更少的上下文切换 |
| 总体 CPU 开销 | 平均降低 2-3% |

### 升级注意事项

1. **Bootstrap**: 从源码构建 Go 1.24 需要 Go 1.22.6+
2. **Map 行为**: Swiss Tables 改变了 map 的迭代顺序（本来就不应该依赖顺序）
3. **RSA 密钥**: 最小 1024 位，检查是否有使用更短密钥的代码
4. **x509sha1**: SHA-1 证书支持完全移除
5. **tools.go**: 建议迁移到 go.mod `tool` 指令
6. **SetFinalizer**: 建议迁移到 `AddCleanup`
7. **Cgo 方法**: 不再允许在 Cgo 类型上定义方法
8. **windows/arm**: 已标记 broken，使用 arm64 替代
9. **macOS**: 准备好 Go 1.25 将要求 macOS 12+
10. **Linux**: 确保内核版本 >= 3.2
