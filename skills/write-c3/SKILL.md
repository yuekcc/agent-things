---
name: write-c3
description: 编写 C3 代码的指导。当你使用 C3 语言编程时使用
---

# 编写 C3 代码

## C3 语言简介

C3 是 C 语言的演进版本，专为系统编程设计。它在保持 C ABI 兼容性和底层控制能力的同时，增加了现代语言特性：

- 模块与导入：用 `module mymod;` 声明模块，用 `import mymod;` 引入，通过 `mymod::public_method()` 调用
- 更强的类型系统（定长整数、切片、向量）
- 通过**可选类型**（`T?`）和 **fault**（错误类型）进行错误处理
- 手动内存管理，配合临时分配器（`tmem`、`@pool`）
- 编译期求值与卫生宏（hygienic macro）
- 运算符重载、泛型、接口
- 标准库内置切片、字符串与容器

C3 代码用 `fn` 声明函数，用 `struct`/`union`/`enum` 声明类型，并遵循严格的命名规则（类型：`PascalCase`，常量：`SCREAMING_SNAKE_CASE`，其余一律：`snake_case`）。

## 阅读标准库以获取代码示例

通过阅读标准库源码，你可以快速熟悉 C3 的编码实践。

标准库源码位于 `${C3C_INSTALLED_DIRECTORY}\lib\std`。运行 `c3c --version` 可以确定 `C3C_INSTALLED_DIRECTORY` 的确切位置。

## 编译

`c3c` 是 C3 语言的编译器。

当代码仓库中包含 `project.json` 文件时，使用：

- 编译项目：`c3c build`
- 运行测试：`c3c test`
- 运行指定测试：`c3c test --test-filter <测试函数名> --test-show-output`

当找不到 `project.json` 时，使用 `c3c compile-only <源文件> <...依赖源文件>` 来做编译校验。

## 链接器（Windows）

`c3c` 只生成目标文件，链接由系统链接器完成（默认 `--linker=cc`）。

- **默认用 MSVC**：需要有 Visual Studio 环境（Developer PowerShell 或先执行 `vcvarsall.bat`），否则会报找不到 C 编译器。
- **没有 MSVC 时用 MinGW 的 gcc**：让 `c3c` 只编译，再由 `gcc` 链接。
  ```bash
  c3c compile-only a.c3 b.c3 --target mingw-x64 --single-module=yes -O2
  gcc -municode -o dist/app.exe ./obj/mingw-x64/a.obj ./obj/mingw-x64/b.obj -ldbghelp -lshlwapi
  ```
  `c3c` 生成的入口符号是 `wmain`，gcc 链接必须加 `-municode`；标准库 backtrace 需要 `-ldbghelp`。

## 快速入门

见 [./c3-quick-intro.md](./c3-quick-intro.md)
