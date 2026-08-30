# C3 语言简介

本文档是面向智能体的 **C3 语法参考**，覆盖编写、调试、解释 C3 代码时最常用的语法、类型系统、错误处理、内存模型与编译期特性。C3 是 C 的演进版本，保持 C ABI 兼容与底层控制力，同时加入模块、可选类型、接口、卫生宏等现代特性。

---

## 1. 基础语法

### 1.1 变量

```c3
int  a = 10;            // 显式类型
var  b @safeinfer = 20; // 类型推断（运行时局部必须带 @safeinfer）
const MAX = 100;        // 编译期常量
int  c @noinit;         // 跳过零初始化
```

- 所有变量默认**零初始化**；`@noinit` 退出此行为（常用于确定会立即写满的 I/O 缓冲）。
- **坑：`var` 用于运行时局部变量时必须带 `@safeinfer`**，否则报错 `Defining a variable using 'var b = ...' is only allowed inside a macro, or when defining a lambda`。宏体、lambda、编译期变量中的 `var` 不需要该属性。
- 命名规则（编译器强制的是首字母大小写）：类型与常量以大写字母开头（类型还需至少含 1 个小写字母），变量与参数以小写字母开头；`PascalCase`、`SCREAMING_SNAKE_CASE`、`snake_case` 是建立在强制规则之上的惯例。

### 1.2 函数

```c3
fn int add(int x, int y) { return x + y; }
fn int square(int x) => x * x;                 // 单行简写
fn void greet(String name) { io::printfn("Hello %s", name); }
```

> 字符串**不能**用 `+`（或 `++`）拼接，见 [1.5 字符串](#15-字符串)。

- 返回可选类型且函数未标 `@maydiscard` 时，调用方**必须用 `(void)` 显式忽略返回值**，否则编译报错：
  ```c3
  (void)file.close();
  defer (void)process.destroy();
  ```

### 1.3 控制流

```c3
if (x > 0) { ... } else { ... }

for (int i = 0; i < 10; i++) { ... }
while (cond) { ... }
do { ... } while (cond);

switch (x) {
    case 1:  ...;            // 隐式 break
    case 2:  ...; nextcase;  // 落入下一 case
    default: unreachable("unexpected");
}
```

- `foreach (v : list)` 遍历；`foreach (&v : list)` 取引用。
- 可给循环加标签：`while LOOP: (true) { ... continue LOOP; }`。
- `defer expr` 在函数退出前执行；`defer (void)resource.free();`。

### 1.4 数组与切片

```c3
int[4] arr = {1, 2, 3, 4};   // 定长数组（值类型）
int[]  slice = &arr;         // 切片视图（数组指针隐式转切片）
int[*] inferred = {1, 2, 3}; // 长度推断：int[3]
int[]  sub = arr[1..3];      // 子切片，闭区间：[2, 3, 4]，len == 3
int[]  tail = arr[1:2];      // [起始:长度]：{2, 3}
```

- **坑：`a[i..j]` 的 `j` 是闭区间（含 j）**，与 Python/Rust/Go 的半开区间相反。`"abcd"[1..3]` 得到 `"bcd"`（len 3）而不是 `"bc"`。0.8.3 实测确认。
- **坑：`a[0..a.len]` 直接 panic**。合法下标只到 `len-1`，安全模式报 `End index out of bounds (end index of 4 exceeds size of 4)`。**c3c 不在编译期拦这个**（下标是常量也不拦），只能靠运行时的边界检查暴露。取整段切片写 `a[..]` 或 `a[0:^0]`。
- 唯一允许 `i == len` 的情形是空切片 `j == i-1`：`a[1..0]`、`a[4..3]` 都合法且 len 为 0。
- `a[start:len]` 中冒号后是**长度**不是结束下标，可省略写成 `a[:len]`（从头取 len 个）。
- `^n` 从尾部倒数：`^1 == len-1`、`^0 == len`。`s[1..^2]` 去掉首尾各 1 个，`s[0:^0]` 是整串。**指针没有长度，不能用 `^n` 也不能省略边界。**
- 要半开区间语义 `[from, to)` 只能手动换算：`a[from : to - from]`。`to < from` 时无符号减法会下溢，需自己先判空。
- 切片有 `.ptr` 与 `.len`。
- 常用整数类型：`usz`（无符号 size）、`sz`（有符号）、`iptr`/`uptr`（与 `void*` 同宽）。

### 1.5 字符串

`String` 是 `inline char[]` 的 typedef（`std::core::string` 中定义），方法丰富：

```c3
String s = "Hello";
String up = s.replace(mem, "l", "L");  // 返回新串（需分配器）
String[] parts = s.split(mem, " ");
String t = s.trim();
usz n = s.len;
```

`String` 就是 `char[]`，切片规则同 [1.4](#14-数组与切片)：`s[1..3]` 是 `"ell"`（闭区间），`s[0..s.len]` 会 panic，取整段用 `s[..]`。

**C3 没有运行时的字符串拼接运算符**——`++` 是自增运算符，不是拼接。两种拼接方式：

```c3
// 1) 编译期拼接：+++（要求两侧都是编译期已知值）
const String A = "Hello ";
const String B = "World";
const String GREETING = A +++ B;

// 2) 运行时拼接：方法 .concat(分配器, s2) / .tconcat(s2)（tmem 版）
String greeting = "Hello ".tconcat(name);
String kept     = "Hello ".concat(mem, name);   // 落到指定分配器，需自行 free
```

> 需要格式化的运行时拼接用 `string::format(mem, "Hello %s", name)` / `string::tformat("Hello %s", name)`，比 `.concat` 更常用。

---

## 2. 模块与导入

- 每个文件以 `module` 开头；模块可任意嵌套（`module foo::bar::baz;`），编译器按模块名查找文件（`foo::bar` 通常落在 `foo/bar.c3` 或 `foo_bar.c3`）。
- 同模块可跨多文件：`a.c3` 与 `b.c3` 都写 `module util;` 会合并为一个模块。单个文件也可以有多段 `module` 声明，每段称为一个 module section。
- 导入：`import std::io;`，多个用逗号 `import std::io, std::math;`。导入是递归的（导入父模块即导入其所有子模块）。
- 可见性：**默认对所有模块可见**；`@private` 收窄到模块内，`@local` 收窄到当前 module section（一般即当前文件）。
- 模块级变量本身就是静态存储期，不需要 C 的 `static`；`tlocal` 声明线程局部存储：
  ```c3
  tlocal GlobalState state;
  ```
- 类型可不加前缀使用（除非名字有歧义）；函数、宏、常量、变量需带最后一段模块名（`io::printfn`）。
- `std::core` 及其子模块默认隐式导入，所以 `String`、`mem`、`tmem`、`string::format` 等无需显式 import。

---

## 3. 错误处理

C3 用 **可选类型**（`T?`）表达“值或错误（fault）”。

### 3.1 定义 fault

```c3
faultdef
    NOT_FOUND, PERMISSION_DENIED, IO_ERROR,
;
```

### 3.2 返回可选类型

```c3
fn int? read_int(String s) {
    if (s.len == 0) return NOT_FOUND~;   // ~ 把 fault 包成可选类型
    return s.to_int()!;                   // ! 解包或向上传播 fault
}
```

### 3.3 处理可选类型

- `if (try v = expr)`：成功分支，`v` 已解包
- `if (catch err = expr)`：失败分支，`err` 是 fault
- `expr ?? default`：为空时给默认值
- `expr!`：解包，失败则本函数返回该 fault
- `expr!!`：解包，失败则直接 panic（初始化等“失败即致命”处使用）

```c3
int? v = read_int("123");
if (catch err = v) {
    io::printfn("error: %s", err);
    return;
}
// 走出 if (catch) 后 v 被自动解包，此处可当普通 int 用
int x = v;
```

> 注意：`if (catch e = <可选变量>)` 的自动解包只对**被 catch 绑定的那个变量**生效，且发生在**离开 if 作用域之后**（或 catch 分支里 return/break/continue/`!` 之后）。写成 `if (catch err = read_int(s)) {...} else { int x = read_int(s); }` 是编译错误——else 分支里第二次调用的结果仍是 `int?`。

---

## 4. 内存管理

### 4.1 临时分配器 `tmem` + `@pool`

`tmem` 上的内存在**退出 `@pool()` 块时**统一回收（注意：不是函数返回时，函数返回不会触发回收）。**绝不要把 `tmem` 分配的内存返回出其 `@pool` 作用域**，也不要传给其他线程。

```c3
@pool()
{
    DString result = dstring::new(tmem);
    result.append("hello");
    return result.copy_str(mem);   // 复制出池外
};
```

带标签的池化循环：

```c3
while LOOP: (true) @pool()
{
    ...
    continue LOOP;   // @pool 作用域重新开始
}
```

### 4.2 堆分配 `mem` / `alloc`

需要跨函数长期持有（存入结构体、全局）的数据用显式分配器：

```c3
MyStruct* p = mem::new(MyStruct);          // 堆分配，零初始化（推荐写法）
MyStruct* q = mem::alloc(MyStruct);        // 同上但不零初始化
MyStruct* r = mem::tnew(MyStruct);         // tmem 版，随 @pool 回收
MyStruct* s = alloc::new(mem, MyStruct);   // 显式传入分配器的通用形式

defer free(p);                             // 堆内存必须显式释放
alloc::free(mem, s);                       // 与 alloc::new 成对
```

`Allocator` 主要有 `mem`（堆全局）与 `tmem`（临时）。

> 坑：`allocator` 不是内置变量，别照着文档里的占位名直接写——实参要传 `mem`、`tmem` 或自定义的 `Allocator`。

### 4.3 字符串构建用 `DString`

```c3
DString buf = dstring::new(tmem);
buf.append("line\n");
buf.appendf("- %s: %s", name, desc);
String out  = buf.copy_str(mem);   // 落到指定分配器
String view = buf.str_view();      // 仅视图（生命周期同 buf）
```

### 4.4 容器 `List{Type}`

```c3
import std::collections::list;   // List 不在隐式导入范围内，需显式导入

List{int} list;
list.init(tmem);                    // 未初始化时默认也是 tmem
list.push(1);
usz n = list.len();                 // 元素个数（也可访问 .size 字段）
int[] arr = list.to_array(mem);     // 转定长数组
list.free();                        // 手动释放（默认 tmem 时也可靠 @pool 自动）
```

> 坑：容器默认 `tmem`，若要在 `@pool()` 之外长期存活，必须 `init(mem)` 或把元素 `copy(mem)`。
> 全局容器可用静态初始化直接指定堆分配器：`List{int} g = list::ONHEAP{int};`

---

## 5. 时间与日期

```c3
import std::time::datetime;   // 时间不在隐式导入范围内
```

`datetime::now()` 返回 **UTC** 的 `DateTime`；直接读 `.year` / `.hour` 等分量拿到的是 UTC 值。转本地时间调 `.to_local()`，返回的是 **`TzDateTime`**（带 gmt offset 的日期时间），**两者类型不同**：

```c3
DateTime utc   = datetime::now();          // UTC
TzDateTime now = utc.to_local();           // 本地时间，类型是 TzDateTime
String ts      = now.format(mem, DateTimeFormat.DATETIME);
io::printfn("utc=%d local=%d", utc.hour, now.hour);
```

- `to_local()` 只定义在 `DateTime` 上：`TzDateTime` 上没有 `to_local()`，不要重复调用。
- `TzDateTime` 换时区用 `to_gmt_offset(offset)` / `with_gmt_offset(offset)`。
- `DateTime.to_local(dt)` 与 `dt.to_local()` 两种写法等价（C3 方法调用惯例）。

---

## 6. 文件与 I/O

### 6.1 打开/读写

```c3
char[]? content = file::load(mem, "data.txt");   // 一次性读，返回 char[]?
if (try c = content) { ... }

file::save(path, content)!!;                     // 保存，失败即 panic
File f = file::open(path, "r")!!;                // 打开，返回 File（不是可选）
defer (void)f.close();                           // close 返回 void?，必须处理
```

- **坑：`!` 只能在返回可选类型的函数里用**。`fn void main()` 里写 `file::open(path)!` 会报 *This expression is doing a rethrow, but 'main' returns 'void'*，此时用 `!!`；若所在函数返回 `T?`，则用 `!` 向上传播。
- **坑：`File?`（可选）不能用 `= null` 赋空**——实测报错 `You cannot cast 'void*' to 'File'`。管理“可关闭资源”的惯用法是 `File` + `bool` 标志位。

### 6.2 写入流：必须传指针

`io::fprintf(OutStream out, ...)` 等接收流接口的参数**必须传指针** `&file`。`File` 实现了 `OutStream`/`InStream` 接口，传 `&file` 可隐式转换。这些流函数返回值是可选类型（`fprintf` 返回 `sz?`，`flush` 返回 `void?`），**必须显式处理**：

```c3
(void)io::fprintf(&file, "x=%d\n", x);   // 或 !! / !，直接写会编译报错
(void)file.flush();
```

### 6.3 路径 `Path`

```c3
import std::io::path;

Path cwd  = path::cwd(mem)!!;                 // 在 main 中用 !!
Path home = path::home_directory(tmem)!!;
Path cfg  = home.append(mem, ".config/app")!!;
if (try parent = cfg.parent())
{
    if (!path::exists(parent)) (void)path::mkdir(parent, true);   // mkdir 返回 bool?
}
String base = cfg.basename();                 // 注意：basename() 返回 String，不是 Path
```

---

## 7. 格式化与打印

```c3
io::printn("hello");                  // 换行
io::printfn("x=%d", x);               // 格式化 + 换行
io::eprintfn("[WARN] %s", msg);      // 走 stderr

String a = string::format(mem, "id_%s", id);   // 落到指定分配器
String b = string::tformat("tmp_%s", id);      // tmem 临时版
String c = string::tcopy(tmem, src);           // 复制一份
```

传给需要以 `\0` 结尾字符串的 C 接口时转 `ZString`（`ZString` 是 typedef，必须显式强转，转换前要确认数据真的以 `\0` 结尾——`str_view()` 不保证）：

```c3
ZString z = (ZString)buf.str_view();   // 仅当 buf 内容已 \0 结尾时才安全
```

---

## 8. 宏与编译期特性

### 8.1 变参宏

```c3
macro void log_error(String $format, args...) {
    io::eprintfn("[ERROR] " +++ $format, ...args);   // +++ 编译期拼接；...args 展开变参
}
```

- 变参声明 `args...`；函数体内是 `any[]`；调用其他变参函数时用 `...args` 展开。
- `$format` 用 `$` 前缀声明编译期参数，调用处必须是编译期已知值。
- 拼接格式串前缀要用**编译期拼接运算符 `+++`**（`++` 是自增，不是拼接）。

### 8.2 条件编译

顶层（函数/全局声明层面）**不能用 `$if`**，会报 `Expected the start of a global declaration here`。0.8.3 起用特性标注：

```c3
fn void win_only() @feat(WIN32) { ... }     // 仅当目标特性 WIN32 生效时编译
fn void not_win()  @feat(!WIN32) { ... }
```

`$if` / `$foreach` / `$for` / `$switch` 只能出现在**函数体或宏体内部**：

```c3
$if $defined(some::func):
    some::func();
$endif
```

### 8.3 编译期变量与反射

反射用 `Type::members`（返回编译期 reflective reference 列表），循环变量必须带 `$` 前缀：

```c3
macro print_fields($Type)
{
    $foreach $field : $Type::members:
        io::printfn("Field %s, offset: %s, size: %s, type: %s",
                    $field.name, $field.offset, $field.size, $field.type.name);
    $endforeach
}
```

可用属性：`.name`、`.qname`、`.type`、`.offset`、`.alignment`、`.kind`、`.get_tag(name)`。

> 没有 `.nameof` / `.offsetof` / `.membersof` 这种写法。

### 8.4 嵌入资源 `$embed`

把文本/二进制文件编译进二进制，避免运行时路径依赖。`$embed` 的结果可直接隐式转换成 `String` / `char[]` / `char[*]` 等，**无需强转**：

```c3
const char[*] TEMPLATE = $embed("template.md");   // 二进制数据用 char[*]
const String  GREETING = $embed("greeting.txt");  // 文本用 String
```

---

## 9. 接口与动态分派

```c3
interface Animal {
    fn String name();
    fn void speak();
}

struct Dog (Animal) {
    int age;
}

fn String Dog.name(&self) @dynamic { return "Dog"; }
fn void Dog.speak(&self) @dynamic { io::printn("Woof"); }
```

接口建立在 `any`（指针 + typeid）之上，是消息传递而非布局兼容，**具体类型不需要为接口留占位字段**。

调用侧由具体类型**隐式转换**成接口，通过接口调用动态方法：

```c3
Dog dog = { .age = 3 };
Animal a = &dog;                        // 隐式转换，无需强转
io::printn(a.name());                   // 走 @dynamic 分派

Animal h = alloc::new(mem, Dog);        // 堆上对象同样可直接赋值
```

---

## 10. 泛型

```c3
module stack <Type>;

struct Stack {
    usz capacity;
    usz size;
    Type* elems;
}

fn void Stack.push(&self, Type elem) { ... }
fn Type Stack.pop(&self) { ... }

// 使用
module main;
import stack;
alias IntStack = Stack{int};
```

---

## 11. 常用标准库模块

| 模块 | 用途 |
| --- | --- |
| `std::io` | 打印、`File`、流 |
| `std::io::file` | `file::load`/`save`/`open` |
| `std::io::path` | `Path` 相关操作 |
| `std::core::mem` / `std::core::mem::allocator` | 分配器、`mem::new`/`free`、`alloc::new`、`tmem`、`mem` |
| `std::collections::list` 等 | `DString`、`List`、`HashMap`（`List` 不在隐式导入内，需显式 import） |
| `std::core::string` | `string::format` / `tformat`、`.concat` |
| `std::math` | 数学、随机 |
| `std::os` | 进程、环境变量 |
| `std::time` / `std::time::datetime` | 计时器；`DateTime`/`TzDateTime`/`DateTimeFormat`（需显式 import） |
| `std::threads` | 平台无关线程、互斥量 |

除 `std::core`（及其子模块）外，上表中的模块大多需要显式 `import`；`List`、时间、日期等都不在隐式导入范围内。

---

## 12. 测试

测试函数用 `@test` 标注，断言用 `test::eq`：

```c3
fn void test_add() @test {
    test::eq(add(1, 2), 3);
}
```

运行：`c3c test`，单个测试 `c3c test --test-filter test_add --test-show-output`。

---

## 13. 项目配置 `project.json`

C3 使用 `project.json` 描述构建：

```json
{
  "langrev": "1",
  "authors": ["Your Name"],
  "version": "0.1.0",
  "sources": ["src/**"],
  "dependencies": ["some_lib"],
  "targets": {
    "my_app": { "type": "executable" }
  }
}
```

- `dependencies`：依赖的 `.c3l` 库名。
- `linked-libraries`：要链接的 C 库（如 `"m"`）；库搜索路径用 `linker-search-paths`。
- `target`：编译目标三元组（如 `"windows-x64"`、`"mingw-x64"`），决定后端与默认链接器。
- `cpu`：CPU 名，仅用于 LLVM 后端优化（如 `"generic"`），**不是**编译目标。
- `opt`：优化级别 `O0`–`O5` / `Os` / `Oz`。
- `safe`：是否开启安全检查（默认 `true`）。

---

## 14. 最佳实践与坑

- **命名规则**由编译器强制：类型/常量大写开头（类型需含小写字母），变量/参数小写开头。
- **零初始化**：局部变量默认清零；`char[N] buf @noinit` 仅用于确定立即写满的缓冲。
- **错误处理**：能恢复用 `catch`/`??`；向上传播用 `!`；初始化等致命处才用 `!!`。
- **`(void)` 丢弃**：返回 `void?`/`sz?` 等且函数未标 `@maydiscard` 时，调用方必须 `(void)fn()`。
- **`tmem` 不逃逸**：只在退出 `@pool()` 块时回收（函数返回不会回收）；要长期持有就 `.copy(mem)` 或 `init(mem)`。`List`/`DString` 默认 `tmem`。
- **字符串拼接**：没有 `+` / `++` 运算符——编译期用 `+++`，运行时用 `.concat(mem, s2)` / `.tconcat(s2)` 或 `string::format`。
- **切片区间是闭区间**：`a[1..3]` 取 3 个元素（不是 2 个）；`a[start:len]` 冒号后是长度；**`a[0..a.len]` 会 panic**，取整段用 `a[..]`，要半开语义就写 `a[from : to-from]`。
- **`var` 推断**：运行时局部必须写 `var x @safeinfer = ...`。
- **`allocator` 不是变量**：分配器实参写 `mem` / `tmem`。
- **时间**：取本地时间必须 `datetime::now().to_local()`，否则拿到 UTC。
- **`File?` 不能 `= null`**：`null` 会被当作 `void*`，报 `You cannot cast 'void*' to 'File'`；用 `File` + `bool` 标志位管理可关闭资源。
- **流参数传指针**：`io::fprintf(&file, ...)`、`f.read(&buf, ...)`。
- **接口实现**：`struct X (Iface)` + `@dynamic` 方法；调用时隐式转换成接口，无需强转。
- **资源嵌入**：模板/配置用 `$embed` 编进二进制。
- **安全模式**：`-O0`/`-O1` 为安全模式（含契约、边界、空指针检查），`-O2` 及以上默认关闭；也可用 `--safe=<yes|no>` 单独开关。**没有 `--fast` 开关**。

---

## 15. C 互操作与工具链

### 15.1 调用 C 函数

C3 与 C ABI 兼容，只要符号能链接上，直接声明就能调用：

```c3
extern fn int putchar(int c);                    // 直接按 C 名调用
extern fn void do_it(int) @cname("real_name");   // C3 名与符号名不同时用 @cname
```

反向导出给 C 用 `@export`（默认外部名会带模块前缀，给 C 用时建议显式指定）：

```c3
module foo;
fn int square(int x) @export("square") { return x * x; }
```

### 15.2 链接 C 库

只有 C 标准库会自动传给链接器，其他库必须显式指定：

| 方式 | 命令行 | `project.json` |
| --- | --- | --- |
| 库 | `-l foo` | `"linked-libraries": ["foo"]` |
| 搜索路径 | `-L ../mylibs/` | `"linker-search-paths": ["../mylibs/"]` |

### 15.3 类型映射的坑

- **定长整型不等于 C 的整型**：C3 的 `int`/`long` 是固定位宽，跨语言函数签名请用 `CInt`、`CLong` 等 C 兼容类型。
- **定长数组不会退化成指针**：C 的 `void test(int[] a)` 要写成 `extern fn void test(int* a)`；`void test2(int[4] b)` 要写成 `extern fn void test2(int[4]* b)`（`int[4]*` 可隐式转成 `int*`）。
- **按值传数组**必须在 C3 侧包一层 struct。
- **没有 `const` / `volatile` 限定符**：用标准库的 `@volatile_load` / `@volatile_store`。
- **不支持 C 的 `_Atomic`**：改用标准库的泛型 `Atomic` 类型。
- **bitstruct** 对 C 呈现为其 backing type；C 的 bitfield 需要手工转成对应布局的 bitstruct。
- **C 枚举大小按 `CInt`**；非连续枚举用 `constdef`。
- **可选类型的 C ABI**：`fn int? get_value();` 对应 `c3fault_t get_value(int* value_ref);`，fault 作返回值，结果通过引用传出。

### 15.4 编译器与链接器

`c3c` 只负责把 C3 编译成目标文件，**链接由"系统链接器"完成**：

```
--linker=<builtin|cc|custom> [<path>]   // 默认 cc，即用 C 编译器充当链接器
--cc <path>                             // 指定 C 编译器（也用于编译项目中的 .c 文件）
--target <target>                       // 目标三元组，如 windows-x64 / mingw-x64
-z <argument>                           // 参数原样透传给链接器
--print-linking                         // 打印实际链接命令，排错首选
--wincrt=<none|static|static-debug|dynamic|dynamic-debug>
```

**Windows 默认走 MSVC**（`cl.exe` / `link.exe`）。因此构建前需要有 Visual Studio 环境（Developer PowerShell 或执行 `vcvarsall.bat`），否则会看到找不到 C 编译器的错误。

**没有 MSVC 时用 MinGW 的 gcc**：让 `c3c` 只编译，链接交给 `gcc`。实测 0.8.3 下 `--cc gcc --linker=cc` 会回退到内置链接器并失败，所以走手动链接更可靠：

```bash
#!/bin/bash
set -ex

OUTPUT=dist/app.exe

# 1) c3c 只编译，产出 obj/mingw-x64/*.obj
c3c compile-only src_a.c3 src_b.c3 --target mingw-x64 --single-module=yes -O2

# 2) gcc 链接
#    -municode  : c3c 生成的入口是 wmain，必须加，否则报 undefined reference to `WinMain'
#    -ldbghelp  : 标准库 backtrace 用到 SymGetLineFromAddr64
gcc -municode -o $OUTPUT ./obj/mingw-x64/src_a.obj ./obj/mingw-x64/src_b.obj -ldbghelp -lshlwapi
strip -s $OUTPUT
```

要点：

- c3c 生成的入口符号是 **`wmain`**，gcc 链接必须加 `-municode`。
- 标准库需要 `-ldbghelp`（`-lshlwapi` 常一起加），否则报 `undefined reference to 'SymGetLineFromAddr64'`。
- 目标不同，产物目录也不同：`obj/windows-x64`（MSVC 用）与 `obj/mingw-x64`（MinGW 用）**两者的 .obj 不能混用**。
- 可用目标用 `c3c --list-targets` 查看（Windows 相关：`windows-x64`、`windows-aarch64`、`mingw-x64`）。

可复用的构建脚本范例：`Z:\projects\cli4win\build_bash_prompt_mingw64.sh`（MinGW 构建 bash_prompt 的两步式脚本）。

---

## 参考

- [C3 官方文档](https://c3-lang.org)
- 本机权威手册：`D:\app\c3-windows-Release\MANUAL.md`（与 `c3c --version` 版本一致，语法细节以此为准）
- 标准库源码：运行 `c3c --version` 查看 `Installed directory`，其下 `lib\std` 可查阅示例；标准库 API 手册不覆盖，直接读源码最准
