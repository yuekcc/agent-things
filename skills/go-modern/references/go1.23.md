# Go 1.23 Reference (August 2024)

Go 1.23 于 2024 年 8 月发布，是一个重要的版本更新。核心亮点包括：range-over-function 迭代器正式进入语言规范、新增 `iter`/`unique`/`structs` 三个标准库包、Timer/Ticker 行为的关键性破坏性变更，以及大量标准库增强。

---

## 1. Language Changes

### 1.1 Range over Function Types（迭代器）

Go 1.23 将 range-over-function 从实验特性提升为正式语言特性。`for-range` 语句现在可以迭代函数类型的表达式。支持三种函数签名：

```go
// 签名 1: 无变量迭代（仅控制循环次数）
func(yield func() bool)

// 签名 2: 单变量迭代（类似 for v := range seq）
func(yield func(V) bool)

// 签名 3: 双变量迭代（类似 for k, v := range seq）
func(yield func(K, V) bool)
```

**Push Iterator 模式详解：**

迭代器函数接收一个 `yield` 回调。迭代器每次调用 `yield` 传递一个值给循环体。如果循环体执行了 `break`、`return` 或其他中断操作，`yield` 返回 `false`，迭代器应立即停止并返回。

```go
package main

import "fmt"

// 自定义迭代器：生成斐波那契数列直到上限
func Fibonacci(limit int) func(yield func(int) bool) {
    return func(yield func(int) bool) {
        a, b := 0, 1
        for a <= limit {
            if !yield(a) {
                return // 调用方 break 了，立即退出
            }
            a, b = b, a+b
        }
    }
}

func main() {
    // 使用 for-range 迭代函数
    for v := range Fibonacci(100) {
        fmt.Println(v)
    }
    // 输出: 0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89

    // 支持 break
    for v := range Fibonacci(1000000) {
        if v > 10 {
            break // yield 返回 false，迭代器停止
        }
        fmt.Println(v)
    }
}
```

**双变量迭代器示例（Key-Value）：**

```go
// 带索引的切片迭代器
func Enumerate[T any](s []T) func(yield func(int, T) bool) {
    return func(yield func(int, T) bool) {
        for i, v := range s {
            if !yield(i, v) {
                return
            }
        }
    }
}

// 使用
for i, name := range Enumerate([]string{"Alice", "Bob", "Carol"}) {
    fmt.Printf("%d: %s\n", i, name)
}
```

**无变量迭代器示例：**

```go
// 重复执行 n 次
func Times(n int) func(yield func() bool) {
    return func(yield func() bool) {
        for i := 0; i < n; i++ {
            if !yield() {
                return
            }
        }
    }
}

// 使用
count := 0
for range Times(5) {
    count++
}
fmt.Println(count) // 5
```

**组合迭代器（Filter + Map 模式）：**

```go
// Filter 过滤迭代器
func Filter[V any](seq func(yield func(V) bool), pred func(V) bool) func(yield func(V) bool) {
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

// Map 转换迭代器
func Map[V, R any](seq func(yield func(V) bool), f func(V) R) func(yield func(R) bool) {
    return func(yield func(R) bool) {
        for v := range seq {
            if !yield(f(v)) {
                return
            }
        }
    }
}

// 组合使用
evens := Filter(Fibonacci(100), func(n int) bool { return n%2 == 0 })
doubled := Map(evens, func(n int) int { return n * 2 })
for v := range doubled {
    fmt.Println(v) // 0, 4, 16, 68, 178
}
```

### 1.2 Generic Type Aliases（预览）

Go 1.23 通过 `GOEXPERIMENT=aliastypeparams` 提供泛型类型别名的预览支持。此特性允许类型别名携带类型参数：

```go
// 需要 GOEXPERIMENT=aliastypeparams 编译
type Set[T comparable] = map[T]struct{}

// 使用
var s Set[string] = make(Set[string])
s["hello"] = struct{}{}
```

启用方式：

```bash
GOEXPERIMENT=aliastypeparams go build ./...
```

注意：这是预览特性，预计在 Go 1.24 中正式发布。`go/types` 包中 `gotypesalias` 的默认值在 1.23 中已改为 `1`，意味着 `go/types.Alias` 类型默认用于表示类型别名。

---

## 2. New Packages

### 2.1 `iter` 包

`iter` 包定义了迭代器的核心类型，是整个迭代器生态的基础。

**类型定义：**

```go
package iter

// Seq 是单值迭代序列的类型。
// 对应 for v := range seq 的使用场景。
type Seq[V any] func(yield func(V) bool)

// Seq2 是键值对迭代序列的类型。
// 对应 for k, v := range seq 的使用场景。
type Seq2[K, V any] func(yield func(K, V) bool)
```

**`iter.Pull` 函数 — 将 push 迭代器转换为 pull 迭代器：**

```go
// Pull 将 push 风格的 Seq 转为 pull 风格。
// 返回 next 函数（每次调用获取下一个值）和 stop 函数（提前终止迭代）。
func Pull[V any](seq Seq[V]) (next func() (V, bool), stop func())

// Pull2 是 Seq2 版本。
func Pull2[K, V any](seq Seq2[K, V]) (next func() (K, V, bool), stop func())
```

**使用示例：**

```go
import "iter"

// 使用 iter.Seq 类型声明迭代器
func Naturals(limit int) iter.Seq[int] {
    return func(yield func(int) bool) {
        for i := 1; i <= limit; i++ {
            if !yield(i) {
                return
            }
        }
    }
}

// Push → Pull 转换
next, stop := iter.Pull(Naturals(100))
defer stop() // 必须调用 stop 以释放资源

v1, ok1 := next() // 1, true
v2, ok2 := next() // 2, true
fmt.Println(v1, ok1, v2, ok2)

// Pull 模式可用于交错读取两个迭代器等场景
```

**Pull2 示例：**

```go
func MapEntries[K comparable, V any](m map[K]V) iter.Seq2[K, V] {
    return func(yield func(K, V) bool) {
        for k, v := range m {
            if !yield(k, v) {
                return
            }
        }
    }
}

next, stop := iter.Pull2(MapEntries(map[string]int{"a": 1, "b": 2}))
defer stop()

k, v, ok := next()
fmt.Println(k, v, ok) // 某个键值对, true
```

### 2.2 `unique` 包

`unique` 包提供值的规范化（canonicalization）功能，类似于 Java 的 `String.intern()` 或 Lisp 的 symbol interning。通过 `Make` 将值转换为 `Handle`，相同值的 `Handle` 可以用 `==` 直接进行指针级别的快速比较。

**API 签名：**

```go
package unique

// Handle 是一个值的规范化句柄。
// 相同值的 Handle 可以用 == 高效比较。
// Handle 是一个轻量级值类型，可以安全复制。
type Handle[T comparable] struct {
    // 内部包含指向规范化值的指针
}

// Make 返回 value 的规范化 Handle。
// 如果之前已经对相同的 value 调用过 Make，则返回相同的 Handle。
// Handle 内部持有的值在所有引用该 Handle 的代码都不可达后，可被 GC 回收。
func Make[T comparable](value T) Handle[T]

// Value 返回 Handle 对应的规范化值。
func (h Handle[T]) Value() T
```

**使用场景与示例：**

```go
import "unique"

// 场景 1: 字符串去重/intern
h1 := unique.Make("hello")
h2 := unique.Make("hello")
h3 := unique.Make("world")

fmt.Println(h1 == h2) // true  — 相同值，指针比较
fmt.Println(h1 == h3) // false — 不同值
fmt.Println(h1.Value()) // "hello"

// 场景 2: 高性能集合键
type InternedKey struct {
    handle unique.Handle[string]
}

// map 查找使用指针比较而非字符串比较，性能更优
cache := make(map[unique.Handle[string]]int)
cache[unique.Make("key1")] = 100
```

**语义要点：**

- `Make` 对相同值保证返回可用 `==` 比较的 `Handle`
- 底层值在没有 `Handle` 引用时可被 GC 回收
- 适用于大量重复字符串的去重场景（如 HTTP header 名称、DNS 名称等）
- `Handle` 是值类型，可安全传递和复制
- 比较操作是 O(1) 的指针比较，而非 O(n) 的值比较

### 2.3 `structs` 包

`structs` 包提供用于修改结构体属性的标记类型。Go 1.23 引入了 `HostLayout`。

**API 签名：**

```go
package structs

// HostLayout 是一个标记类型。
// 将其嵌入到结构体中，表明该结构体的内存布局
// 遵循宿主平台的 ABI 约定（C 语言兼容布局）。
// 这对于与 cgo 或 unsafe 代码交互时确保布局兼容非常重要。
type HostLayout struct{}
```

**使用示例：**

```go
import "structs"

// 标记此结构体使用宿主平台的内存布局
// Go 编译器保证字段布局与 C 编译器一致
type CCompatibleStruct struct {
    _ structs.HostLayout // 零大小标记，不占用空间
    X int32
    Y int64
    Z float32
}
```

**意义：** 目前 Go 编译器的结构体布局恰好与 C ABI 兼容，但这并非语言规范保证。`HostLayout` 标记为未来编译器可能改变默认布局提供了前向兼容性。对于通过 cgo 或 `unsafe.Pointer` 与 C 代码共享的结构体，建议添加此标记。

---

## 3. Standard Library Changes

### 3.1 Timer/Ticker 行为变更（重大破坏性变更）

**这是 Go 1.23 中最容易导致线上问题的变更，务必仔细阅读。**

当 `go.mod` 中 `go` 指令为 `1.23` 或更高时，`time.NewTimer` 和 `time.NewTicker` 创建的 channel 行为发生根本性变化：

#### 变更内容

| 行为 | Go <= 1.22 | Go >= 1.23 |
|------|-----------|-----------|
| Channel 容量 | 缓冲 (cap=1) | 无缓冲 (cap=0) |
| 未 Stop 的 Timer | 即使无引用也不会被 GC | 可以被 GC 回收 |
| Reset 后旧值 | 可能残留旧值在 channel 中 | channel 已被清空（drain） |
| Stop 后 channel | 可能残留未读取的值 | 保证 channel 已被清空 |

#### 危险代码模式（必须迁移）

**模式 1：使用 `len(timer.C)` 检查是否有待读取的值**

```go
// ❌ Go 1.23 中永远返回 0（无缓冲 channel 的 len 总是 0）
if len(timer.C) > 0 {
    <-timer.C
}
```

迁移方案：

```go
// ✅ 使用 non-blocking select
select {
case <-timer.C:
    // 消费掉旧值
default:
    // 没有值，继续
}
```

**模式 2：Stop 后 drain channel**

```go
// Go 1.22 中常见的 Timer reset 模式
if !timer.Stop() {
    <-timer.C // ❌ Go 1.23 中会永久阻塞！因为 Stop 已经 drain 了 channel
}
timer.Reset(newDuration)
```

迁移方案：

```go
// ✅ Go 1.23: Stop + Reset 直接使用即可
timer.Stop()
timer.Reset(newDuration)

// 或者，如果需要兼容两个版本：
if !timer.Stop() {
    select {
    case <-timer.C:
    default:
    }
}
timer.Reset(newDuration)
```

**模式 3：`cap(timer.C)` 依赖**

```go
// ❌ 依赖 channel 容量的代码会出问题
if cap(timer.C) == 1 {
    // Go 1.23 中 cap 为 0
}
```

#### 回退机制

如果迁移过程中遇到问题，可以通过 GODEBUG 回退到旧行为：

```go
// go.mod 中
godebug asynctimerchan=1

// 或者环境变量
// GODEBUG=asynctimerchan=1
```

也可以在 `go.mod` 中设置：

```
module myapp

go 1.23

godebug asynctimerchan=1
```

#### GC 回收行为变更

```go
func leakyOldCode() {
    // Go 1.22: 这个 timer 永远不会被 GC，造成内存泄漏
    // Go 1.23: timer 在无引用后可被 GC 回收
    timer := time.NewTimer(time.Hour)
    _ = timer // 即使不调用 Stop()，也能被正常回收
}
```

### 3.2 `slices` 包新增函数

Go 1.23 为 `slices` 包新增了大量基于迭代器的函数：

```go
// All 返回切片的索引-值迭代器
func All[Slice ~[]E, E any](s Slice) iter.Seq2[int, E]

// Values 返回切片的纯值迭代器
func Values[Slice ~[]E, E any](s Slice) iter.Seq[E]

// Backward 返回反向遍历的索引-值迭代器
func Backward[Slice ~[]E, E any](s Slice) iter.Seq2[int, E]

// Collect 将迭代器收集为切片
func Collect[E any](seq iter.Seq[E]) []E

// AppendSeq 将迭代器中的值追加到现有切片
func AppendSeq[Slice ~[]E, E any](s Slice, seq iter.Seq[E]) Slice

// Sorted 将迭代器收集并排序（使用 cmp.Ordered 约束）
func Sorted[E cmp.Ordered](seq iter.Seq[E]) []E

// SortedFunc 将迭代器收集并使用自定义比较函数排序
func SortedFunc[E any](seq iter.Seq[E], cmp func(E, E) int) []E

// SortedStableFunc 将迭代器收集并使用自定义比较函数稳定排序
func SortedStableFunc[E any](seq iter.Seq[E], cmp func(E, E) int) []E

// Chunk 将切片分割为指定大小的子切片迭代器
func Chunk[Slice ~[]E, E any](s Slice, n int) iter.Seq[Slice]

// Repeat 将切片重复 count 次（count < 0 表示无限重复）
func Repeat[Slice ~[]E, E any](x Slice, count int) Slice
```

**使用示例：**

```go
import "slices"

// All: 带索引遍历
s := []string{"a", "b", "c"}
for i, v := range slices.All(s) {
    fmt.Printf("%d: %s\n", i, v)
}

// Values: 仅遍历值
for v := range slices.Values(s) {
    fmt.Println(v)
}

// Backward: 反向遍历
for i, v := range slices.Backward(s) {
    fmt.Printf("%d: %s\n", i, v) // 2:c, 1:b, 0:a
}

// Collect: 收集迭代器为切片
nums := slices.Collect(Naturals(5))
fmt.Println(nums) // [1 2 3 4 5]

// AppendSeq: 追加迭代器值
existing := []int{0}
result := slices.AppendSeq(existing, Naturals(3))
fmt.Println(result) // [0 1 2 3]

// Sorted: 收集并排序
sorted := slices.Sorted(slices.Values([]int{3, 1, 4, 1, 5}))
fmt.Println(sorted) // [1 1 3 4 5]

// SortedFunc: 自定义排序
words := slices.SortedFunc(
    slices.Values([]string{"banana", "apple", "cherry"}),
    strings.Compare,
)
fmt.Println(words) // [apple banana cherry]

// SortedStableFunc: 稳定排序
type Item struct {
    Name     string
    Priority int
}
items := []Item{{"a", 2}, {"b", 1}, {"c", 2}, {"d", 1}}
stableSorted := slices.SortedStableFunc(
    slices.Values(items),
    func(a, b Item) int { return a.Priority - b.Priority },
)
// 相同 Priority 的元素保持原始顺序

// Chunk: 分块
for chunk := range slices.Chunk([]int{1, 2, 3, 4, 5}, 2) {
    fmt.Println(chunk) // [1 2], [3 4], [5]
}

// Repeat: 重复
repeated := slices.Repeat([]int{1, 2}, 3)
fmt.Println(repeated) // [1 2 1 2 1 2]
```

### 3.3 `maps` 包新增函数

```go
// All 返回 map 的键值对迭代器
func All[Map ~map[K]V, K comparable, V any](m Map) iter.Seq2[K, V]

// Keys 返回 map 的键迭代器
func Keys[Map ~map[K]V, K comparable, V any](m Map) iter.Seq[K]

// Values 返回 map 的值迭代器
func Values[Map ~map[K]V, K comparable, V any](m Map) iter.Seq[V]

// Insert 将键值对迭代器中的所有条目插入到 map 中
func Insert[Map ~map[K]V, K comparable, V any](m Map, seq iter.Seq2[K, V])

// Collect 将键值对迭代器收集为新 map
func Collect[K comparable, V any](seq iter.Seq2[K, V]) map[K]V
```

**使用示例：**

```go
import "maps"

m := map[string]int{"a": 1, "b": 2, "c": 3}

// Keys: 获取所有键
for k := range maps.Keys(m) {
    fmt.Println(k)
}

// Values: 获取所有值
for v := range maps.Values(m) {
    fmt.Println(v)
}

// All: 键值对迭代
for k, v := range maps.All(m) {
    fmt.Printf("%s=%d\n", k, v)
}

// Collect: 从迭代器创建 map
pairs := func(yield func(string, int) bool) {
    yield("x", 10)
    yield("y", 20)
}
newMap := maps.Collect(pairs)
fmt.Println(newMap) // map[x:10 y:20]

// Insert: 批量插入
target := map[string]int{"a": 1}
maps.Insert(target, maps.All(map[string]int{"b": 2, "c": 3}))
fmt.Println(target) // map[a:1 b:2 c:3]

// 组合使用: 获取排序后的键
sortedKeys := slices.Sorted(maps.Keys(m))
fmt.Println(sortedKeys) // [a b c]
```

### 3.4 `crypto/tls`

**Encrypted Client Hello (ECH) 支持：**

```go
// 新增 Config 字段
type Config struct {
    // EncryptedClientHelloConfigList 设置 ECH 配置列表
    // 客户端使用此配置加密 ClientHello
    EncryptedClientHelloConfigList []byte

    // EncryptedClientHelloRejectionVerify 用于在 ECH 被拒绝时
    // 验证服务器证书的回调
    EncryptedClientHelloRejectionVerify func(ConnectionState) error
}
```

**3DES 密码套件移除：**

Go 1.23 将 3DES 密码套件从默认列表中移除。如需回退：

```go
// GODEBUG 回退
// GODEBUG=tls3des=1

// 或者显式指定
tlsConfig := &tls.Config{
    CipherSuites: []uint16{
        tls.TLS_RSA_WITH_3DES_EDE_CBC_SHA, // 不推荐
        // ... 其他套件
    },
}
```

**X25519Kyber768Draft00 后量子密钥交换：**

Go 1.23 默认启用 `X25519Kyber768Draft00` 后量子密钥交换。如有兼容性问题：

```go
// 回退方式
// GODEBUG=tlskyber=0
```

**QUICConn 新增方法：**

```go
// SetTransportParameters 设置 QUIC 传输参数
func (q *QUICConn) SetTransportParameters(params []byte)

// StoreSession 存储 TLS 会话以供 0-RTT 使用
func (q *QUICConn) StoreSession(session *SessionState) error
```

### 3.5 `crypto/x509`

```go
// 新增 OID 解析函数
func ParseOID(oid string) (asn1.ObjectIdentifier, error)

// 示例
oid, err := x509.ParseOID("2.5.4.3") // commonName
```

**SHA-1 签名弃用警告：** `x509sha1` GODEBUG 设置在 Go 1.23 中仍然可用但会在未来版本移除。SHA-1 签名的证书验证默认失败：

```go
// 临时回退（不推荐，将在未来移除）
// GODEBUG=x509sha1=1
```

### 3.6 `database/sql`

错误包装增强：`database/sql` 中的 `ErrNoRows` 及其他错误类型现在使用 `%w` 进行包装，支持 `errors.Is` 和 `errors.As`：

```go
import "database/sql"
import "errors"

err := db.QueryRow("SELECT ...").Scan(&v)
if errors.Is(err, sql.ErrNoRows) {
    // 即使错误被包装，也能正确匹配
}
```

### 3.7 `encoding/binary`

新增三个便捷函数，替代手动使用 `binary.Write` + `bytes.Buffer` 的模式：

```go
// Encode 将数据编码为字节切片
func Encode(buf []byte, order ByteOrder, data any) (int, error)

// Decode 从字节切片解码数据
func Decode(buf []byte, order ByteOrder, data any) (int, error)

// Append 将编码后的数据追加到字节切片
func Append(buf []byte, order ByteOrder, data any) ([]byte, error)
```

**使用示例：**

```go
import "encoding/binary"

// Append: 追加编码数据
var buf []byte
buf, _ = binary.Append(buf, binary.LittleEndian, uint32(42))
buf, _ = binary.Append(buf, binary.LittleEndian, float64(3.14))
fmt.Printf("%x\n", buf)

// Decode: 从字节解码
var val uint32
n, _ := binary.Decode(buf[:4], binary.LittleEndian, &val)
fmt.Println(val, n) // 42, 4

// Encode: 编码到已有 buffer
data := make([]byte, 4)
binary.Encode(data, binary.BigEndian, uint32(100))
```

### 3.8 `go/ast`

新增 `Preorder` 函数，返回 AST 节点的前序遍历迭代器：

```go
// Preorder 返回 AST 节点的前序遍历迭代器
func Preorder(root ast.Node) iter.Seq[ast.Node]
```

**使用示例：**

```go
import (
    "go/ast"
    "go/parser"
    "go/token"
)

fset := token.NewFileSet()
f, _ := parser.ParseFile(fset, "example.go", src, 0)

// 使用迭代器遍历 AST（替代 ast.Inspect）
for node := range ast.Preorder(f) {
    if fn, ok := node.(*ast.FuncDecl); ok {
        fmt.Println("Found function:", fn.Name.Name)
    }
}
```

### 3.9 `go/types`

**Alias 类型变更：**

`GODEBUG=gotypesalias` 的默认值从 `0` 改为 `1`。这意味着 `go/types` 现在默认使用 `types.Alias` 类型来表示类型别名，而非直接解析为底层类型。

```go
// 影响使用 go/types 的工具
// 以前 type S = string 会直接返回 *types.Basic
// 现在默认返回 *types.Alias

// 新增方法
func (*Alias) Rhs() Type      // 返回别名的右侧类型
func (*Alias) Origin() *Alias  // 返回泛型别名的原始定义
func (*Alias) TypeParams() *TypeParamList // 返回类型参数
func (*Alias) SetTypeParams(tparams []*TypeParam) // 设置类型参数
func (*Alias) TypeArgs() *TypeList // 返回类型实参

// Unalias 函数用于获取别名的底层真实类型
func Unalias(t Type) Type
```

**迁移建议：** 使用 `go/types` 编写分析工具的开发者应检查代码中的类型断言，确保能处理 `*types.Alias`。

### 3.10 `math/rand/v2`

新增 `Uint` 函数：

```go
// Uint 返回均匀分布的随机 uint 值
func Uint() uint

// 等价于截断版本的 Uint64，但在 32 位平台上可能更高效
```

### 3.11 `net`

**KeepAliveConfig 新结构体：**

```go
// KeepAliveConfig 提供精细的 TCP keep-alive 配置
type KeepAliveConfig struct {
    // Enable 是否启用 keep-alive
    Enable bool
    // Idle 设置在发送第一个 keep-alive 探测之前的空闲时间
    Idle time.Duration
    // Interval 设置 keep-alive 探测之间的间隔
    Interval time.Duration
    // Count 设置在判定连接断开之前发送的未确认探测数
    Count int
}
```

**在 TCPConn 和 Dialer 上使用：**

```go
// TCPConn 新增方法
func (c *TCPConn) SetKeepAliveConfig(config KeepAliveConfig) error

// Dialer 新增字段
type Dialer struct {
    // ... 现有字段 ...
    KeepAliveConfig KeepAliveConfig
}
```

**DNSError 包装：**

`DNSError` 现在包装了底层错误，支持 `errors.Is` 和 `errors.As`：

```go
var dnsErr *net.DNSError
if errors.As(err, &dnsErr) {
    // 可以进一步检查底层错误
    if errors.Is(err, context.DeadlineExceeded) {
        // DNS 查询超时
    }
}
```

### 3.12 `net/http`

大量 Cookie 和请求处理增强：

```go
// Cookie 新增字段
type Cookie struct {
    // ... 现有字段 ...
    Quoted      bool // 值是否使用引号包裹
    Partitioned bool // 是否为分区 Cookie (CHIPS 提案)
}

// Request 新增方法
func (r *Request) CookiesNamed(name string) []*Cookie

// Request 新增字段
type Request struct {
    // ... 现有字段 ...
    Pattern string // 匹配的路由模式（配合 Go 1.22 的增强路由）
}

// 新增 Cookie 解析函数
func ParseCookie(line string) ([]*Cookie, error)
func ParseSetCookie(line string) (*Cookie, error)
```

**使用示例：**

```go
import "net/http"

// 解析 Cookie header
cookies, err := http.ParseCookie("name=value; name2=value2")
if err == nil {
    for _, c := range cookies {
        fmt.Printf("%s = %s (quoted: %v)\n", c.Name, c.Value, c.Quoted)
    }
}

// 解析 Set-Cookie header
cookie, err := http.ParseSetCookie("session=abc; Path=/; HttpOnly; Partitioned")
if err == nil {
    fmt.Println(cookie.Partitioned) // true
}

// 获取指定名称的所有 Cookie
handler := func(w http.ResponseWriter, r *http.Request) {
    // 获取所有名为 "session" 的 cookie
    sessionCookies := r.CookiesNamed("session")

    // 使用 Pattern 获取匹配的路由模式
    fmt.Println(r.Pattern) // 例如 "GET /users/{id}"
}
```

**ServeContent 头部变更：** `ServeContent`、`ServeFile` 和 `FileServer` 不再为 `Content-Type` 为 `""` 的小文件生成 `Content-Type: application/octet-stream`。HTTP/1 响应中的 `Content-Encoding` 处理也有所改进。

### 3.13 `os`

**CopyFS：复制整个文件系统树**

```go
// CopyFS 将 fsys 中的所有文件复制到以 dir 为根的本地目录
func CopyFS(dir string, fsys fs.FS) error
```

**使用示例：**

```go
import (
    "embed"
    "os"
)

//go:embed templates/*
var templateFS embed.FS

func deployTemplates() error {
    // 将嵌入的模板复制到本地目录
    return os.CopyFS("/tmp/templates", templateFS)
}
```

**Linux pidfd 支持：**

在 Linux 5.4+ 上，`os.Process` 内部使用 pidfd（进程文件描述符）而非传统的 PID。这解决了 PID 复用带来的竞态条件问题：

```go
// 新增方法
func (p *Process) Pid() int // 仍然返回传统 PID，但内部通过 pidfd 管理

// pidfd 确保 Signal/Wait 操作作用于正确的进程
// 即使在进程退出后 PID 被复用的情况下也不会出错
```

**FindProcess 行为变更：** 在 Linux 上，如果支持 pidfd，`FindProcess` 返回的进程可以安全地发送信号，不会因 PID 复用而误杀其他进程。

### 3.14 `path/filepath`

```go
// Localize 将斜杠分隔的路径转换为操作系统本地路径
// 如果路径无法安全表示为本地路径则返回错误
// 这比简单的 filepath.FromSlash 更安全
func Localize(path string) (string, error)
```

**使用示例：**

```go
import "path/filepath"

// 安全地将 URL 路径转换为本地文件路径
localPath, err := filepath.Localize("templates/pages/index.html")
if err != nil {
    // 路径包含不安全的元素（如 ".." 或绝对路径）
    log.Fatal(err)
}
// Windows 上: "templates\\pages\\index.html"
// Unix 上:    "templates/pages/index.html"

// 危险路径会返回错误
_, err = filepath.Localize("../etc/passwd")
// err != nil，因为包含 ".."

_, err = filepath.Localize("/etc/passwd")
// err != nil，因为是绝对路径
```

### 3.15 `reflect`

**新增多个方法：**

```go
// SliceAt 创建一个指向指定地址和长度的切片的 Value
// 这是 unsafe.Slice 的 reflect 版本
func SliceAt(typ Type, p unsafe.Pointer, len int) Value

// Value.Seq 返回值的单值迭代器（用于 for-range）
// 支持的 Kind: Slice, Array, String, Map, Chan, Func(iter.Seq), Int/Int8/...
func (v Value) Seq() iter.Seq[Value]

// Value.Seq2 返回值的键值对迭代器（用于 for-range）
// 支持的 Kind: Slice, Array, String, Map, Func(iter.Seq2)
func (v Value) Seq2() iter.Seq2[Value, Value]
```

**使用示例：**

```go
import "reflect"

// Seq: 反射值的迭代
v := reflect.ValueOf([]int{10, 20, 30})
for elem := range v.Seq() {
    fmt.Println(elem.Int()) // 10, 20, 30
}

// Seq2: 带索引/键的迭代
m := reflect.ValueOf(map[string]int{"a": 1, "b": 2})
for k, v := range m.Seq2() {
    fmt.Printf("%s: %d\n", k.String(), v.Int())
}

// 切片迭代也支持 Seq2（索引 + 值）
s := reflect.ValueOf([]string{"x", "y"})
for i, v := range s.Seq2() {
    fmt.Printf("%d: %s\n", i.Int(), v.String())
}
```

### 3.16 `runtime/debug`

```go
// SetCrashOutput 设置程序崩溃（runtime crash/panic 未恢复时）的输出目标
// 允许将崩溃日志写入文件而非 stderr
func SetCrashOutput(f *os.File, opts CrashOptions) error

type CrashOptions struct {
    // 目前没有可选字段，预留给未来扩展
}
```

**使用示例：**

```go
import "runtime/debug"

func init() {
    f, err := os.OpenFile("/var/log/myapp-crash.log",
        os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
    if err != nil {
        log.Fatal(err)
    }
    if err := debug.SetCrashOutput(f, debug.CrashOptions{}); err != nil {
        log.Fatal(err)
    }
    // 此后运行时崩溃信息会写入该文件
}
```

### 3.17 `runtime/pprof`

goroutine 堆栈深度从 32 帧增加到 128 帧。这意味着深度递归或链式调用的 goroutine profile 现在能显示更完整的调用栈：

```go
// 无需代码变更，自动生效
// 对于深度嵌套的中间件链或递归调用，pprof 输出更完整
```

### 3.18 `sync`

```go
// Map.Clear 删除 Map 中的所有条目
func (m *Map) Clear()
```

**使用示例：**

```go
import "sync"

var cache sync.Map
cache.Store("key1", "value1")
cache.Store("key2", "value2")

// 清空所有条目
cache.Clear()

// 确认已清空
_, ok := cache.Load("key1")
fmt.Println(ok) // false
```

### 3.19 `sync/atomic`

新增 `And` 和 `Or` 原子位操作：

```go
// 对所有整数原子类型新增 And 和 Or 方法
func (x *Int32) And(val int32) int32   // 返回旧值
func (x *Int32) Or(val int32) int32    // 返回旧值
func (x *Int64) And(val int64) int64
func (x *Int64) Or(val int64) int64
func (x *Uint32) And(val uint32) uint32
func (x *Uint32) Or(val uint32) uint32
func (x *Uint64) And(val uint64) uint64
func (x *Uint64) Or(val uint64) uint64
func (x *Uintptr) And(val uintptr) uintptr
func (x *Uintptr) Or(val uintptr) uintptr

// 顶层函数版本
func AndInt32(addr *int32, mask int32) int32
func AndInt64(addr *int64, mask int64) int64
func AndUint32(addr *uint32, mask uint32) uint32
func AndUint64(addr *uint64, mask uint64) uint64
func AndUintptr(addr *uintptr, mask uintptr) uintptr
func OrInt32(addr *int32, mask int32) int32
func OrInt64(addr *int64, mask int64) int64
func OrUint32(addr *uint32, mask uint32) uint32
func OrUint64(addr *uint64, mask uint64) uint64
func OrUintptr(addr *uintptr, mask uintptr) uintptr
```

**使用示例：**

```go
import "sync/atomic"

var flags atomic.Uint64

// 原子设置位
const (
    FlagReady   uint64 = 1 << 0
    FlagRunning uint64 = 1 << 1
    FlagDone    uint64 = 1 << 2
)

// Or: 设置标志位
old := flags.Or(FlagReady | FlagRunning)
fmt.Printf("old: %b, new: %b\n", old, flags.Load())

// And: 清除标志位（使用掩码的补码）
old = flags.And(^FlagRunning) // 清除 Running 位
fmt.Printf("old: %b, new: %b\n", old, flags.Load())
```

### 3.20 `text/template`

新增 `{{else with}}` 语法，类似于 `else if` 但用于 `with` 块：

```go
import "text/template"

const tmpl = `
{{with .Primary}}
    Primary: {{.}}
{{else with .Secondary}}
    Secondary: {{.}}
{{else}}
    No value found
{{end}}
`

// 等价于之前的嵌套写法：
// {{with .Primary}}...{{else}}{{with .Secondary}}...{{else}}...{{end}}{{end}}
```

**使用示例：**

```go
t := template.Must(template.New("test").Parse(`
{{- with .Name -}}
    Hello, {{.}}!
{{- else with .Nickname -}}
    Hey, {{.}}!
{{- else -}}
    Hello, stranger!
{{- end -}}
`))

// 使用 Name
t.Execute(os.Stdout, map[string]string{"Name": "Alice"}) // Hello, Alice!

// 使用 Nickname (Name 为零值)
t.Execute(os.Stdout, map[string]string{"Nickname": "Bob"}) // Hey, Bob!

// 都没有
t.Execute(os.Stdout, map[string]string{}) // Hello, stranger!
```

### 3.21 `time`（Windows 精度改进）

Go 1.23 改进了 Windows 平台上的定时器精度。之前 Windows 上的 `time.Sleep`、`time.NewTimer` 等的精度受系统全局定时器分辨率限制（通常为 ~15.6ms）。Go 1.23 使用更高精度的 Windows API：

```go
// 无需代码变更
// Windows 上的 time.Sleep(time.Millisecond) 现在更精确
// 不再依赖 timeBeginPeriod/timeEndPeriod 全局设置
```

**行为变更：** Go 不再自动调用 `timeBeginPeriod(1)` 来提升全局定时器分辨率。这意味着其他使用低精度定时器的应用不会受到 Go 程序的"副作用"影响，系统功耗也会降低。

### 3.22 `unicode/utf16`

```go
// RuneLen 返回 UTF-16 编码给定 rune 所需的 16 位码元数量
// 返回 1 表示 BMP 字符，2 表示需要代理对的字符，-1 表示无效 rune
func RuneLen(r rune) int
```

**使用示例：**

```go
import "unicode/utf16"

fmt.Println(utf16.RuneLen('A'))     // 1 (BMP 字符)
fmt.Println(utf16.RuneLen('中'))     // 1 (BMP 字符)
fmt.Println(utf16.RuneLen('𝄞'))     // 2 (需要代理对, U+1D11E)
fmt.Println(utf16.RuneLen(-1))      // -1 (无效)
fmt.Println(utf16.RuneLen(0x110000)) // -1 (超出 Unicode 范围)
```

---

## 4. Toolchain Changes

### 4.1 Go Telemetry（遥测系统）

Go 1.23 引入了 Go 工具链遥测系统。该系统收集 Go 工具链的使用统计和崩溃报告以帮助改进 Go。

```bash
# 查看遥测状态
go telemetry

# 启用遥测（opt-in，默认关闭）
go telemetry on

# 关闭遥测
go telemetry off

# 查看本地收集的数据
go telemetry view
```

**重要：** 遥测默认关闭（`local` 模式），只在本地收集数据。必须用户显式执行 `go telemetry on` 才会上传数据。

### 4.2 `go env -changed`

新增 `-changed` 标志，仅显示与默认值不同的环境变量：

```bash
# 显示所有环境变量
go env

# 仅显示被修改过的环境变量
go env -changed
# 输出示例:
# GOPATH=/home/user/go
# GOBIN=/home/user/go/bin
# CGO_ENABLED=0
```

### 4.3 `go mod tidy -diff`

新增 `-diff` 标志，以 diff 格式显示 `go mod tidy` 将要做的更改，而不实际修改文件：

```bash
# 预览 tidy 将做的更改
go mod tidy -diff

# 输出 unified diff 格式
# --- go.mod.orig
# +++ go.mod
# @@ -3,7 +3,6 @@
#  require (
#      golang.org/x/text v0.14.0
# -    golang.org/x/unused v0.0.0  // 将被删除
#  )

# 可用于 CI 检查 go.mod 是否 tidy
go mod tidy -diff && echo "OK" || echo "go.mod needs tidying"
```

### 4.4 `go list` 新字段

`go list -m -json` 输出新增 `Sum` 和 `GoModSum` 字段：

```bash
go list -m -json all
```

```json
{
    "Path": "golang.org/x/text",
    "Version": "v0.14.0",
    "Sum": "h1:ScX5w1eTa3QqT8oi6+ziP7dTV1S2+ALU0bI+0zXKWiQ=",
    "GoModSum": "h1:ScX5w1eTa3QqT8oi6+ziP7dTV1S2+ALU0bI+0zXKWiQ="
}
```

- `Sum`: 模块 zip 文件的 checksum（对应 go.sum 中的 `h1:` 行）
- `GoModSum`: go.mod 文件的 checksum（对应 go.sum 中的 `/go.mod h1:` 行）

### 4.5 `godebug` 指令

Go 1.23 在 `go.mod` 和 `go.work` 中支持 `godebug` 指令，用于设置 `GODEBUG` 行为：

```
module myapp

go 1.23

// 设置 GODEBUG 选项
godebug asynctimerchan=1
godebug httpmuxgo121=1
```

这替代了通过环境变量设置 GODEBUG 的方式，使配置与代码版本一起管理。每个模块可以独立设置自己的 GODEBUG 值。

### 4.6 Vet `stdversion` 分析器

新增 `stdversion` vet 分析器，检测代码中使用的标准库符号是否与 `go.mod` 中声明的 Go 版本兼容：

```bash
# 如果 go.mod 中是 go 1.21，但代码使用了 Go 1.23 才有的 API
go vet ./...
# 输出: slices.Chunk requires go1.23 or later (module is go1.21)
```

**示例场景：**

```go
// go.mod 中: go 1.21

package main

import "slices"

func main() {
    // vet 会报警: slices.Chunk 需要 go 1.23
    for chunk := range slices.Chunk([]int{1, 2, 3}, 2) {
        _ = chunk
    }
}
```

### 4.7 Cgo `-ldflags` 变更

cgo 新增支持在 `#cgo` 指令中使用 `-ldflags` 标志。同时完善了 cgo 工具对各种 C 编译器标志的处理。

### 4.8 Trace 工具容错

`go tool trace` 现在能够容忍部分损坏的 trace 数据，在数据不完整时仍然尝试展示已收集的部分。这对于程序崩溃后分析 trace 数据特别有用。

### 4.9 `//go:linkname` 限制

Go 1.23 开始限制 `//go:linkname` 指令的使用。链接器现在会对使用 `//go:linkname` 引用未导出函数的代码发出警告，未来版本将更严格：

```go
// ⚠️ 以下用法在未来可能无法编译
//go:linkname someInternalFunc runtime.someInternalFunc
func someInternalFunc()
```

**影响：** 依赖 `//go:linkname` 访问运行时或标准库内部函数的第三方包可能需要迁移。使用 `-checklinkname=0` 链接器标志可以临时禁用此检查。

### 4.10 链接器 `-bindnow` 标志

新增链接器标志 `-bindnow`，设置 ELF `DF_BIND_NOW` 标志，启用完全 RELRO（RELocation Read-Only）保护：

```bash
go build -ldflags="-bindnow" ./...
```

**安全意义：** 这使得 GOT（Global Offset Table）在程序启动时完成所有符号解析后变为只读，防止 GOT overwrite 攻击。

---

## 5. Compiler & Runtime

### 5.1 PGO 构建开销降低

Profile-Guided Optimization (PGO) 的编译开销从之前的可能增加编译时间 100%+ 降低到个位数百分比：

```bash
# 收集 profile
go test -cpuprofile=default.pgo -bench=. ./...

# 使用 PGO 构建（编译时间增加不明显）
go build -pgo=default.pgo ./...

# 如果 default.pgo 在 main 包目录下，会自动使用
cp default.pgo ./cmd/myapp/
go build ./cmd/myapp/
```

### 5.2 栈帧优化（重叠槽位）

编译器现在能够将不同时活跃的局部变量分配到相同的栈空间（overlapping stack frame slots）。这减少了函数的栈帧大小，对深度递归函数尤其有益：

```go
func process(data []byte) {
    // 编译器分析发现 a 和 b 不同时存在
    if len(data) > 100 {
        var a [1024]byte // 使用栈空间 X
        doSomething(a[:])
    } else {
        var b [1024]byte // 复用栈空间 X（与 a 重叠）
        doOther(b[:])
    }
}
```

### 5.3 热块对齐

在 386 和 amd64 架构上，编译器现在会将频繁执行的代码块（热块）对齐到缓存行边界。配合 PGO 使用时效果更显著，减少 instruction cache miss：

```bash
# PGO + 热块对齐 = 最优性能
go build -pgo=default.pgo ./cmd/myapp
```

### 5.4 Panic 输出格式优化

运行时 panic 的输出格式改进，使用制表符缩进使其更易读：

```
// Go 1.22 输出
goroutine 1 [running]:
main.main()
	/home/user/main.go:10 +0x40

// Go 1.23 输出（制表符对齐更清晰）
goroutine 1 [running]:
main.main()
	/home/user/main.go:10 +0x40
```

panic 输出中多个 goroutine 的信息现在使用更一致的缩进格式，改善了可读性。

---

## 6. Platform Changes

### 6.1 macOS

**最低版本要求提升至 macOS 11 Big Sur。** Go 1.23 不再支持 macOS 10.15 Catalina 及更早版本：

```bash
# macOS 10.15 上编译的程序仍可运行（交叉编译），
# 但 Go 工具链本身需要 macOS 11+
```

### 6.2 Linux

**Go 1.23 是最后一个支持 Linux kernel 2.6.32 的版本。** Go 1.24 将要求 Linux kernel 3.2+。

```bash
# 检查内核版本
uname -r

# 如果仍在 2.6.32 上运行（如老旧的 CentOS 6），
# 应在升级到 Go 1.24 之前迁移
```

### 6.3 新端口：`openbsd/riscv64`

Go 1.23 新增 OpenBSD on RISC-V 64-bit 架构支持：

```bash
GOOS=openbsd GOARCH=riscv64 go build ./...
```

### 6.4 `GOARM64` 环境变量

新增 `GOARM64` 环境变量，控制 ARM64 架构编译的最低特性集：

```bash
# 默认值: v8.0
GOARM64=v8.0 go build ./...

# 启用 LSE（Large System Extensions）原子操作
# 需要 ARMv8.1 或更高
GOARM64=v8.1 go build ./...

# 可选的加密扩展
GOARM64=v8.0,crypto go build ./...
```

**可用值：**

| 值 | 含义 |
|---|---|
| `v8.0` | 基础 ARMv8.0（默认） |
| `v8.1` | 包含 LSE 原子操作 |
| `v8.{2-9}` | 对应 ARMv8.x 特性集 |

可选后缀 `,crypto` 启用加密指令扩展。

### 6.5 `GORISCV64` 环境变量

新增 `GORISCV64` 环境变量，控制 RISC-V 64-bit 架构的指令集版本：

```bash
# 默认: rva20u64 (RVA20U64 profile)
GORISCV64=rva20u64 go build ./...

# 使用 RVA22U64 profile（包含更多扩展）
GORISCV64=rva22u64 go build ./...
```

**可用值：**

| 值 | 含义 |
|---|---|
| `rva20u64` | RVA20U64 应用处理器 profile（默认） |
| `rva22u64` | RVA22U64 应用处理器 profile |

---

## 7. Quick Migration Checklist

在升级到 Go 1.23 时，按以下清单检查：

### 高优先级（可能导致运行时错误）

- [ ] **Timer/Ticker channel 使用方式检查**
  - 搜索所有 `len(timer.C)` 和 `cap(timer.C)` 使用，替换为 non-blocking select
  - 搜索 `if !timer.Stop() { <-timer.C }` 模式，评估是否需要修改
  - 考虑先设置 `godebug asynctimerchan=1` 作为过渡
- [ ] **`//go:linkname` 使用检查**
  - 检查代码和依赖中的 `//go:linkname` 使用
  - 如有问题，临时使用 `-checklinkname=0`

### 中优先级（功能影响）

- [ ] **`go/types` Alias 行为变更**
  - 如果编写了 Go 分析工具，检查类型断言中是否处理 `*types.Alias`
- [ ] **crypto/tls 3DES 移除**
  - 检查是否有客户端/服务端依赖 3DES 密码套件
- [ ] **crypto/x509 SHA-1**
  - 检查是否有证书使用 SHA-1 签名

### 低优先级（增强特性）

- [ ] 开始使用 `for-range` 迭代函数替代回调模式
- [ ] 使用 `iter.Seq`/`iter.Seq2` 作为库的迭代器返回类型
- [ ] 使用 `slices.Chunk`/`maps.All` 等新函数简化代码
- [ ] 使用 `unique.Make` 优化高频字符串比较场景
- [ ] 使用 `os.CopyFS` 替代手动文件树复制
- [ ] 使用 `go mod tidy -diff` 集成到 CI
- [ ] 使用 `godebug` 指令管理 GODEBUG 设置

---

## 8. Version History Context

| 版本 | 发布日期 | 核心特性 |
|------|---------|---------|
| Go 1.21 | 2023-08 | min/max/clear 内置函数, slog, slices/maps 包 |
| Go 1.22 | 2024-02 | range-over-int, 增强 HTTP 路由, for 循环变量语义 |
| **Go 1.23** | **2024-08** | **range-over-func, iter/unique/structs 包, Timer 变更** |
| Go 1.24 | 2025-02 | 泛型类型别名正式, 弱指针, 更多迭代器支持 |

---

*参考来源: [Go 1.23 Release Notes](https://go.dev/doc/go1.23), [Go Blog: Range Over Function Types](https://go.dev/blog/range-functions)*
