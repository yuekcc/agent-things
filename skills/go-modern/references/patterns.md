# Go 现代惯用模式 (1.23–1.26)

> 每个模式展示 Before/After 代码对比，标注引入版本。
> 描述使用中文，代码使用英文。

---

## 迭代器模式 (Go 1.23+)

### 自定义迭代器实现

Go 1.23 引入 `range-over-func`，允许自定义函数作为 `range` 的目标。标准迭代器签名定义在 `iter` 包中。

```go
// ===== Before (Go 1.22) — 手动循环或 channel 模式 =====
// 遍历二叉树需要用 channel 或回调函数

type TreeNode struct {
    Value       int
    Left, Right *TreeNode
}

// channel 方式：有 goroutine 泄漏风险
func (t *TreeNode) Values() <-chan int {
    ch := make(chan int)
    go func() {
        defer close(ch)
        t.walk(ch)
    }()
    return ch
}

func (t *TreeNode) walk(ch chan<- int) {
    if t == nil {
        return
    }
    t.Left.walk(ch)
    ch <- t.Value
    t.Right.walk(ch)
}

// 使用
for v := range tree.Values() {
    fmt.Println(v)
}


// ===== After (Go 1.23+) — iter.Seq 迭代器 =====
import "iter"

func (t *TreeNode) All() iter.Seq[int] {
    return func(yield func(int) bool) {
        if t == nil {
            return
        }
        // 中序遍历：左 → 根 → 右
        for v := range t.Left.All() {
            if !yield(v) {
                return
            }
        }
        if !yield(t.Value) {
            return
        }
        for v := range t.Right.All() {
            if !yield(v) {
                return
            }
        }
    }
}

// 使用：干净、无泄漏
for v := range tree.All() {
    fmt.Println(v)
}
```

### 键值对迭代器 (`iter.Seq2`)

```go
// ===== After (Go 1.23+) — iter.Seq2 用于键值对 =====
import "iter"

// 带索引的切片迭代器
func Enumerate[T any](s []T) iter.Seq2[int, T] {
    return func(yield func(int, T) bool) {
        for i, v := range s {
            if !yield(i, v) {
                return
            }
        }
    }
}

// 使用
for i, name := range Enumerate(names) {
    fmt.Printf("%d: %s\n", i, name)
}
```

### 组合迭代器（filter, map, take）

```go
// ===== Before (Go 1.22) — 手动循环过滤和转换 =====
func filterPositive(nums []int) []int {
    result := make([]int, 0)
    for _, n := range nums {
        if n > 0 {
            result = append(result, n)
        }
    }
    return result
}

func mapDouble(nums []int) []int {
    result := make([]int, len(nums))
    for i, n := range nums {
        result[i] = n * 2
    }
    return result
}

positives := filterPositive(numbers)
doubled := mapDouble(positives)


// ===== After (Go 1.23+) — 可组合的惰性迭代器 =====
import "iter"

// 通用过滤器
func Filter[V any](seq iter.Seq[V], pred func(V) bool) iter.Seq[V] {
    return func(yield func(V) bool) {
        for v := range seq {
            if pred(v) {
                if !yield(v) {
                    return
                }
            }
        }
    }
}

// 通用映射
func Map[In, Out any](seq iter.Seq[In], f func(In) Out) iter.Seq[Out] {
    return func(yield func(Out) bool) {
        for v := range seq {
            if !yield(f(v)) {
                return
            }
        }
    }
}

// 取前 N 个
func Take[V any](seq iter.Seq[V], n int) iter.Seq[V] {
    return func(yield func(V) bool) {
        i := 0
        for v := range seq {
            if i >= n {
                return
            }
            if !yield(v) {
                return
            }
            i++
        }
    }
}

// 组合使用 — 惰性求值，无中间分配
for v := range Take(Map(Filter(slices.Values(numbers),
    func(n int) bool { return n > 0 }),
    func(n int) int { return n * 2 }),
    10) {
    fmt.Println(v)
}
```

### `slices.Sorted` + `maps.Keys` 组合

```go
// ===== Before (Go 1.22) — 手动排序 map keys =====
keys := make([]string, 0, len(m))
for k := range m {
    keys = append(keys, k)
}
sort.Strings(keys)
for _, k := range keys {
    fmt.Println(k, m[k])
}

// ===== After (Go 1.23+) — 一行完成 =====
import (
    "maps"
    "slices"
)

for _, k := range slices.Sorted(maps.Keys(m)) {
    fmt.Println(k, m[k])
}
```

### `strings.Lines` / `strings.SplitSeq`

```go
// ===== Before (Go 1.22) — strings.Split 分配完整切片 =====
lines := strings.Split(text, "\n")
for _, line := range lines {
    if strings.TrimSpace(line) != "" {
        process(line)
    }
}

// ===== After (Go 1.24+) — strings.Lines 惰性迭代 =====
for line := range strings.Lines(text) {
    line = strings.TrimRight(line, "\n")
    if strings.TrimSpace(line) != "" {
        process(line)
    }
}

// strings.SplitSeq — 通用分隔符的惰性版本 (Go 1.24+)
for part := range strings.SplitSeq(csv, ",") {
    process(part)
}
```

### `go/types` 迭代器方法

```go
// ===== Before (Go 1.22) — 索引循环访问方法集 =====
iface := typ.Underlying().(*types.Interface)
for i := 0; i < iface.NumMethods(); i++ {
    method := iface.Method(i)
    fmt.Println(method.Name())
}

// ===== After (Go 1.23+) — 迭代器方法 =====
iface := typ.Underlying().(*types.Interface)
for method := range iface.Methods() {
    fmt.Println(method.Name())
}
```

---

## 错误处理 (Go 1.26+)

### `errors.AsType` vs `errors.As`

Go 1.26 引入泛型版本 `errors.AsType`，避免手动声明目标变量和指针传递。

```go
// ===== Before (Go 1.22) — errors.As 需要预声明变量 =====
import "errors"

func handleError(err error) {
    var pathErr *os.PathError
    if errors.As(err, &pathErr) {
        fmt.Println("path error:", pathErr.Path)
    }

    var netErr net.Error
    if errors.As(err, &netErr) && netErr.Timeout() {
        fmt.Println("network timeout")
    }
}

// ===== After (Go 1.26+) — errors.AsType 泛型版本 =====
import "errors"

func handleError(err error) {
    if pathErr, ok := errors.AsType[*os.PathError](err); ok {
        fmt.Println("path error:", pathErr.Path)
    }

    if netErr, ok := errors.AsType[net.Error](err); ok && netErr.Timeout() {
        fmt.Println("network timeout")
    }
}
```

---

## 并发模式 (Go 1.24+/1.25+)

### `WaitGroup.Go` 模式

Go 1.25 新增 `sync.WaitGroup.Go` 方法，合并了 `Add(1)` + `go func` + `defer Done()` 模式。

```go
// ===== Before (Go 1.24) — 手动管理 WaitGroup 计数 =====
import "sync"

func processAll(items []Item) {
    var wg sync.WaitGroup
    for _, item := range items {
        wg.Add(1)
        go func(it Item) {
            defer wg.Done()
            process(it)
        }(item)
    }
    wg.Wait()
}

// ===== After (Go 1.25+) — WaitGroup.Go =====
import "sync"

func processAll(items []Item) {
    var wg sync.WaitGroup
    for _, item := range items {
        wg.Go(func() {
            process(item) // Go 1.22+ 循环变量安全
        })
    }
    wg.Wait()
}
```

### `synctest` 虚拟时钟测试

Go 1.25 引入 `testing/synctest` 包，提供虚拟时间用于测试并发代码。

```go
// ===== Before (Go 1.24) — 依赖真实时间，测试缓慢且不稳定 =====
func TestDebounce(t *testing.T) {
    var count atomic.Int32
    debounced := Debounce(func() { count.Add(1) }, 100*time.Millisecond)

    debounced()
    debounced()
    debounced()

    time.Sleep(200 * time.Millisecond) // 真实等待！测试缓慢
    if got := count.Load(); got != 1 {
        t.Errorf("got %d, want 1", got)
    }
}

// ===== After (Go 1.25+) — synctest 虚拟时钟 =====
import "testing/synctest"

func TestDebounce(t *testing.T) {
    synctest.Run(func() {
        var count atomic.Int32
        debounced := Debounce(func() { count.Add(1) }, 100*time.Millisecond)

        debounced()
        debounced()
        debounced()

        // 虚拟时间推进：瞬间完成，行为确定
        time.Sleep(200 * time.Millisecond) // 在 synctest 中不会真正等待
        synctest.Wait()                    // 等待所有 goroutine 空闲
        if got := count.Load(); got != 1 {
            t.Errorf("got %d, want 1", got)
        }
    })
}
```

### 容器感知的 `GOMAXPROCS`

Go 1.25 自动根据 cgroup CPU 限制设置 `GOMAXPROCS`。

```go
// ===== Before (Go 1.24) — 需要第三方库或手动设置 =====
import "go.uber.org/automaxprocs" // 第三方依赖

func main() {
    automaxprocs.Set() // 读取 cgroup 限制
    // 或手动设置
    // runtime.GOMAXPROCS(numCPU)
}

// ===== After (Go 1.25+) — 自动处理，无需任何操作 =====
func main() {
    // runtime 自动读取 cgroup CPU 限制
    // 不再需要 automaxprocs 依赖
    // 如需覆盖：runtime.GOMAXPROCS(n) 或 GODEBUG=containermaxprocs=0
}
```

---

## 测试模式 (Go 1.24+/1.25+)

### `B.Loop` 基准测试

```go
// ===== Before (Go 1.23) =====
func BenchmarkConcat(b *testing.B) {
    // setup 时间被计入！
    data := generateData()
    b.ResetTimer() // 必须手动重置

    for i := 0; i < b.N; i++ {
        _ = concat(data)
    }
}

// ===== After (Go 1.24+) =====
func BenchmarkConcat(b *testing.B) {
    data := generateData() // setup 自动排除
    for b.Loop() {
        _ = concat(data) // 编译器不会优化掉未使用的结果
    }
}
```

### `T.Context` / `T.Chdir`

```go
// ===== Before (Go 1.23) =====
func TestWithTimeout(t *testing.T) {
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    dir := t.TempDir()
    origDir, _ := os.Getwd()
    if err := os.Chdir(dir); err != nil {
        t.Fatal(err)
    }
    defer os.Chdir(origDir)

    result, err := longOperation(ctx)
    // ...
}

// ===== After (Go 1.24+) =====
func TestWithTimeout(t *testing.T) {
    ctx := t.Context() // 测试结束/超时自动取消
    t.Chdir(t.TempDir()) // 自动恢复原目录

    result, err := longOperation(ctx)
    // ...
}
```

### `T.ArtifactDir` 测试产物目录

```go
// ===== Before (Go 1.24) — 测试产物无标准保存位置 =====
func TestRenderChart(t *testing.T) {
    img := renderChart(data)
    // 保存到临时文件，位置随机
    f, _ := os.CreateTemp("", "chart-*.png")
    defer f.Close()
    png.Encode(f, img)
    t.Logf("chart saved to: %s", f.Name()) // 需手动记录路径
}

// ===== After (Go 1.25+) — 标准化测试产物目录 =====
func TestRenderChart(t *testing.T) {
    img := renderChart(data)
    // 保存到标准产物目录
    path := filepath.Join(t.ArtifactDir(), "chart.png")
    f, _ := os.Create(path)
    defer f.Close()
    png.Encode(f, img)
    // 运行：go test -artifactdir=./test-outputs ./...
    // 所有产物整齐保存在 ./test-outputs/ 下
}
```

---

## 资源管理 (Go 1.24+)

### `runtime.AddCleanup` vs `SetFinalizer`

```go
// ===== Before (Go 1.23) — SetFinalizer =====
type FileHandle struct {
    fd int
}

func OpenFile(path string) *FileHandle {
    fd := syscallOpen(path)
    fh := &FileHandle{fd: fd}
    // 问题1: 如果 fh 被 finalizer 引用，fh 不会被 GC
    // 问题2: 不能对同一对象设置多个 finalizer
    // 问题3: finalizer 中 fh 被"复活"，延迟一轮 GC
    runtime.SetFinalizer(fh, func(fh *FileHandle) {
        syscallClose(fh.fd)
    })
    return fh
}

// ===== After (Go 1.24+) — AddCleanup =====
type FileHandle struct {
    fd int
}

func OpenFile(path string) *FileHandle {
    fd := syscallOpen(path)
    fh := &FileHandle{fd: fd}
    // 优势1: cleanup 函数接收值（非指针），不会复活对象
    // 优势2: 可以为同一对象添加多个 cleanup
    // 优势3: 不阻止 GC 回收
    runtime.AddCleanup(fh, func(fd int) {
        syscallClose(fd)
    }, fh.fd) // 第三个参数是传给 cleanup 函数的值
    return fh
}
```

### `os.Root` 目录范围操作

Go 1.24 引入 `os.Root`，将文件操作限制在指定目录内，防止路径遍历攻击。

```go
// ===== Before (Go 1.23) — 手动验证路径 =====
func serveFile(userInput string) ([]byte, error) {
    // 必须手动防止路径遍历
    cleaned := filepath.Clean(userInput)
    if strings.Contains(cleaned, "..") {
        return nil, errors.New("path traversal detected")
    }
    fullPath := filepath.Join("/var/data", cleaned)
    // 仍然不够安全：符号链接可能逃逸
    return os.ReadFile(fullPath)
}

// ===== After (Go 1.24+) — os.Root 自动限制 =====
func serveFile(userInput string) ([]byte, error) {
    root, err := os.OpenRoot("/var/data")
    if err != nil {
        return nil, err
    }
    defer root.Close()

    // 自动拒绝 .. 遍历和符号链接逃逸
    f, err := root.Open(userInput)
    if err != nil {
        return nil, err // 路径遍历尝试会返回 error
    }
    defer f.Close()
    return io.ReadAll(f)
}
```

### `weak.Pointer` 弱引用缓存

Go 1.24 引入 `weak.Pointer`，用于构建不阻止 GC 的缓存。

```go
// ===== Before (Go 1.23) — 手动管理缓存生命周期 =====
type Cache struct {
    mu    sync.Mutex
    items map[string]*BigObject
}

func (c *Cache) Get(key string) *BigObject {
    c.mu.Lock()
    defer c.mu.Unlock()
    return c.items[key] // 强引用，对象永远不会被 GC
}

// 需要手动驱逐策略（LRU、TTL 等）

// ===== After (Go 1.24+) — weak.Pointer 弱引用缓存 =====
import "weak"

type Cache struct {
    mu    sync.Mutex
    items map[string]weak.Pointer[BigObject]
}

func (c *Cache) Get(key string) *BigObject {
    c.mu.Lock()
    defer c.mu.Unlock()
    if wp, ok := c.items[key]; ok {
        if obj := wp.Value(); obj != nil {
            return obj // 对象仍在内存中
        }
        delete(c.items, key) // 已被 GC，清理条目
    }
    return nil
}

func (c *Cache) Set(key string, obj *BigObject) {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.items[key] = weak.Make(obj) // 不阻止 GC 回收 obj
}
```

---

## JSON 处理 (Go 1.24+)

### `omitzero` 标签

```go
// ===== Before (Go 1.23) — omitempty 对某些类型无效 =====
type Config struct {
    Name      string        `json:"name,omitempty"`
    Timeout   time.Duration `json:"timeout,omitempty"`  // 0 不被视为"空"，仍输出
    CreatedAt time.Time     `json:"created_at,omitempty"` // 零值仍输出
    Tags      []string      `json:"tags,omitempty"`      // nil 省略但 [] 不省略
}

c := Config{Name: "test"}
// 输出: {"name":"test","timeout":0,"created_at":"0001-01-01T00:00:00Z"}
// timeout 和 created_at 的零值仍然出现

// ===== After (Go 1.24+) — omitzero 按 IsZero() 判断 =====
type Config struct {
    Name      string        `json:"name,omitempty"`
    Timeout   time.Duration `json:"timeout,omitzero"`     // 0 会被省略
    CreatedAt time.Time     `json:"created_at,omitzero"`  // 零值会被省略
    Tags      []string      `json:"tags,omitzero"`        // nil 和 [] 都会被省略
}

c := Config{Name: "test"}
// 输出: {"name":"test"}
// 干净！零值字段全部省略
```

### `TextAppender` / `BinaryAppender`

```go
// ===== Before (Go 1.23) — TextMarshaler 每次分配 =====
type Duration struct{ d time.Duration }

func (d Duration) MarshalText() ([]byte, error) {
    return []byte(d.d.String()), nil // 分配新 []byte
}

// JSON 编码器每次都会分配新切片

// ===== After (Go 1.24+) — TextAppender 追加到已有 buffer =====
type Duration struct{ d time.Duration }

// 同时实现 TextMarshaler 和 TextAppender
func (d Duration) MarshalText() ([]byte, error) {
    return d.AppendText(nil) // 复用实现
}

func (d Duration) AppendText(b []byte) ([]byte, error) {
    return append(b, d.d.String()...), nil // 追加到已有 buffer
}

// encoding/json 会优先调用 AppendText，减少内存分配
```

### `encoding/json/v2`（实验性，Go 1.24+）

```go
// ===== 实验性 json/v2 — 通过 GOEXPERIMENT 或独立模块使用 =====
import "encoding/json/v2" // 或 github.com/go-json-experiment/json

type APIResponse struct {
    Data      any           `json:"data"`
    CreatedAt time.Time     `json:"created_at,omitzero,format:RFC3339"`
    Duration  time.Duration `json:"duration,format:nano"`
    Extra     any           `json:"extra,omitzero"`
}

// json/v2 特性：
// - 严格默认（不允许未知字段、重复键）
// - 更丰富的 struct tag（format、inline 等）
// - 更好的 time.Time / time.Duration 格式化
// - 自定义 MarshalJSON/UnmarshalJSON 签名变更
// - 与 v1 不完全兼容 — 谨慎迁移
```

---

## 密码学 (Go 1.24+/1.26+)

### `rand.Text()` 生成随机文本

```go
// ===== Before (Go 1.23) — 手动生成随机字符串 =====
import (
    "crypto/rand"
    "encoding/hex"
)

func generateToken() (string, error) {
    b := make([]byte, 16)
    _, err := rand.Read(b)
    if err != nil {
        return "", err
    }
    return hex.EncodeToString(b), nil
}

// ===== After (Go 1.24+) — rand.Text() =====
import "crypto/rand"

func generateToken() string {
    return rand.Text() // 返回随机的 base32 编码文本（26 字符，~128 位熵）
}
// 不返回 error — 系统随机源失败会 panic（极罕见）
```

### HPKE（混合公钥加密）

```go
// ===== After (Go 1.24+) — crypto/hpke =====
import "crypto/hpke"

// 发送方加密
func encryptMessage(recipientPubKey *ecdh.PublicKey, plaintext, info []byte) (enc, ciphertext []byte, err error) {
    suite := hpke.Suite{
        KEM:  hpke.KEM_P256_HKDF_SHA256,
        KDF:  hpke.KDF_HKDF_SHA256,
        AEAD: hpke.AEAD_AES_128_GCM,
    }
    sender, enc, err := suite.NewSender(recipientPubKey, info)
    if err != nil {
        return nil, nil, err
    }
    sealer, err := sender.Setup()
    if err != nil {
        return nil, nil, err
    }
    ciphertext = sealer.Seal(nil, plaintext, nil)
    return enc, ciphertext, nil
}
```

### ML-KEM 后量子密码

```go
// ===== After (Go 1.24+) — crypto/mlkem =====
import "crypto/mlkem"

// 密钥生成
func generateMLKEMKeyPair() (*mlkem.EncapsulationKey1024, *mlkem.DecapsulationKey1024, error) {
    dk, err := mlkem.GenerateKey1024()
    if err != nil {
        return nil, nil, err
    }
    return dk.EncapsulationKey(), dk, nil
}

// 密钥封装
func encapsulate(ek *mlkem.EncapsulationKey1024) (sharedKey, ciphertext []byte, err error) {
    ss, ct, err := ek.Encapsulate()
    return ss, ct, err // sharedKey 可用作对称加密密钥
}
```

---

## 工具链 (Go 1.24+/1.26+)

### `tool` 指令在 `go.mod` 中

```go
// ===== Before (Go 1.23) — tools.go 文件 hack =====
// tools.go
//go:build tools

package tools

import (
    _ "golang.org/x/tools/cmd/stringer"
    _ "github.com/golangci/golangci-lint/cmd/golangci-lint"
)

// 使用：
// go run golang.org/x/tools/cmd/stringer -type=Color

// ===== After (Go 1.24+) — go.mod tool 指令 =====
// go.mod 中添加：
// tool (
//     golang.org/x/tools/cmd/stringer
//     github.com/golangci/golangci-lint/cmd/golangci-lint
// )

// 添加工具依赖：
// go get -tool golang.org/x/tools/cmd/stringer@latest

// 使用：
// go tool stringer -type=Color
// go tool golangci-lint run
```

### `go fix` modernizers (Go 1.26+)

```bash
# ===== Before (Go 1.25) — 手动逐个重构旧模式 =====
# 开发者需要手动查找并替换旧写法

# ===== After (Go 1.26+) — 自动重写 =====

# 预览所有可用的修复（不修改文件）
go fix -fix all -diff ./...

# 应用所有 modernizer
go fix -fix all ./...

# 仅应用特定 modernizer
go fix -fix slicesclip ./...   # a[:len(a):len(a)] → slices.Clip(a)
go fix -fix rangeint ./...     # C-style for → range int
go fix -fix sortslice ./...    # sort.Slice → slices.SortFunc
go fix -fix efaceany ./...     # interface{} → any
go fix -fix minmax ./...       # if/else min/max → built-in
go fix -fix bloop ./...        # for i := 0; i < b.N; i++ → for b.Loop()
go fix -fix waitgroupgo ./...  # wg.Add(1)+go func → wg.Go
go fix -fix errorsas ./...     # errors.As → errors.AsType
```

### `go build -json` (Go 1.24+)

```bash
# ===== Before (Go 1.23) — 解析文本输出 =====
go build -v ./... 2>&1 | grep "^#"

# ===== After (Go 1.24+) — 结构化 JSON 输出 =====
go build -json ./...
# 输出结构化的 JSON，包含编译步骤、依赖图、错误位置等
# 便于 IDE、CI 工具解析

# 结合 jq 提取编译错误：
go build -json ./... 2>&1 | jq 'select(.Action == "build-output" and .Output != null)'
```

---

## 性能优化模式

### 预分配 map + Swiss Tables

```go
// ===== Before (Go 1.23) — 可选的 make(map, hint) =====
m := make(map[string]int, 100) // hint 仅供参考，效果有限

// ===== After (Go 1.24+) — Swiss Tables 下 hint 更有效 =====
// Swiss Tables 实现对 size hint 更好地利用
m := make(map[string]int, 100) // 预分配更精准，减少扩容

// Go 1.24+ 额外的 map 优化：
// 1. 小 map (<=8 个元素) 可能使用内联存储
// 2. 迭代性能提升（更好的缓存局部性）
// 3. 内存占用通常更低

// 注意：map 迭代顺序可能变化（规范从未保证）
// 不要依赖 map 遍历顺序！
```

### `unique.Make` 字符串驻留

```go
// ===== Before (Go 1.23) — 手动字符串驻留 =====
type StringInterner struct {
    mu    sync.Mutex
    cache map[string]string
}

func (si *StringInterner) Intern(s string) string {
    si.mu.Lock()
    defer si.mu.Unlock()
    if existing, ok := si.cache[s]; ok {
        return existing
    }
    si.cache[s] = s
    return s
}
// 问题：缓存永远增长，需要手动驱逐

// ===== After (Go 1.23+) — unique.Make =====
import "unique"

// unique.Handle 是一个可比较的句柄
type normalizedKey struct {
    name unique.Handle[string]
    ns   unique.Handle[string]
}

func makeKey(name, ns string) normalizedKey {
    return normalizedKey{
        name: unique.Make(name), // 全局自动驻留
        ns:   unique.Make(ns),   // 相同字符串返回相同 Handle
    }
}

// 优势：
// 1. 运行时管理生命周期，配合 GC 自动回收
// 2. Handle 比较是 O(1)（指针比较）
// 3. 内存效率：相同值只存储一份
// 4. 并发安全，无需外部锁
```

### `io.ReadAll` 改进

```go
// ===== Before (Go 1.23) — 对已知大小的输入效率低 =====
// io.ReadAll 从 512 字节开始，倍增扩容
data, err := io.ReadAll(resp.Body) // 可能多次分配和复制

// ===== After (Go 1.24+) — 利用 WriterTo 接口 =====
// io.ReadAll 现在检查 src 是否实现 WriterTo，
// 以及是否可以预知大小（如 bytes.Buffer、os.File）
// 这些情况下避免不必要的中间分配

// 对于已知大小的场景，仍建议预分配：
func readResponse(resp *http.Response) ([]byte, error) {
    if resp.ContentLength > 0 {
        buf := make([]byte, resp.ContentLength)
        _, err := io.ReadFull(resp.Body, buf)
        return buf, err
    }
    return io.ReadAll(resp.Body) // Go 1.24+ 内部优化更好
}
```

### `sync.Map` hash-trie 新实现

```go
// ===== Go 1.24+ — sync.Map 使用 hash-trie 实现 =====
// 无需代码变更，但性能特征变化：

// sync.Map 最佳使用场景（不变）：
// 1. 键一旦写入很少删除（读多写少）
// 2. 多个 goroutine 访问不同的键集合
var cache sync.Map

// 存储
cache.Store("key", value)

// 加载
if v, ok := cache.Load("key"); ok {
    use(v)
}

// Go 1.24+ hash-trie 改进：
// - 读取路径完全无锁（比旧版本快 2-3x）
// - 写入性能略有提升
// - 内存碎片更少
// - 删除操作不再导致全局重建

// 如果大部分操作是写入，考虑分片 map：
type ShardedMap[K comparable, V any] struct {
    shards [64]struct {
        sync.RWMutex
        m map[K]V
    }
}

func (s *ShardedMap[K, V]) shard(key K) *struct {
    sync.RWMutex
    m map[K]V
} {
    h := maphash.Bytes(maphash.MakeSeed(), []byte(fmt.Sprint(key)))
    return &s.shards[h%64]
}
```

---

## 版本特性速查

| 模式 | 最低版本 | 关键 API |
|-----|---------|---------|
| 迭代器 (range-over-func) | 1.23 | `iter.Seq`, `iter.Seq2` |
| `maps.Keys` / `maps.Values` 返回迭代器 | 1.23 | `maps.Keys`, `maps.Values` |
| `slices.Sorted` | 1.23 | `slices.Sorted`, `slices.SortedFunc` |
| `unique.Make` | 1.23 | `unique.Make`, `unique.Handle` |
| `strings.Lines` / `SplitSeq` | 1.24 | `strings.Lines`, `strings.SplitSeq` |
| `omitzero` JSON 标签 | 1.24 | `json:"field,omitzero"` |
| `b.Loop()` | 1.24 | `testing.B.Loop` |
| `t.Context()` / `t.Chdir()` | 1.24 | `testing.T.Context`, `testing.T.Chdir` |
| `runtime.AddCleanup` | 1.24 | `runtime.AddCleanup` |
| `os.Root` | 1.24 | `os.OpenRoot`, `os.Root.Open` |
| `weak.Pointer` | 1.24 | `weak.Make`, `weak.Pointer.Value` |
| `rand.Text()` | 1.24 | `crypto/rand.Text` |
| ML-KEM | 1.24 | `crypto/mlkem` |
| `tool` in go.mod | 1.24 | `go get -tool`, `go tool` |
| `TextAppender` | 1.24 | `encoding.TextAppender` |
| `sync.WaitGroup.Go` | 1.25 | `sync.WaitGroup.Go` |
| `synctest` 虚拟时钟 | 1.25 | `testing/synctest.Run` |
| 容器 GOMAXPROCS 自动适配 | 1.25 | 自动（`GODEBUG=containermaxprocs`） |
| `t.ArtifactDir()` | 1.25 | `testing.T.ArtifactDir` |
| `errors.AsType` | 1.26 | `errors.AsType[T]` |
| `go fix` modernizers | 1.26 | `go fix -fix all` |
| `go build -json` | 1.24 | `go build -json` |
