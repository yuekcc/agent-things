---
name: write-c3
description: Guidance on write C3 codes. Use when you are programming in C3 language
---

# Write C3 Codes

## C3 Language Quick Intro

C3 is an evolution of C designed for systems programming. It maintains C ABI compatibility and low-level control while adding modern features:

- Modules and imports: declare a module with `module mymod;`, use it with `import mymod; mymod::public_method()`
- Stronger type system (fixed-size integers, slices, vectors)
- Error handling via **optional types** (`T?`) and **faults**
- Manual memory management with temporary allocators (`tmem`, `@pool`)
- Compile-time evaluation and hygienic macros
- Operator overloading, generics, interfaces
- Built-in slices, strings, and containers in the standard library

C3 code uses `fn` for functions, `struct`/`union`/`enum` for types, and follows strict naming rules (types: `PascalCase`, constants: `SCREAMING_SNAKE_CASE`, everything else: `snake_case`).

## Reading std library for code example

By exploring the standard library source code, you can quickly familiarize yourself with C3 coding practices. 

The std source code can be found at `${C3C_INSTALLED_DIRECTORY}\lib\std`. You can determine the exact location of `C3C_INSTALLED_DIRECTORY` by running `c3c --version`.

## Compilation

`c3c` is the C3 language compiler. 

When the code repository contains a `project.json` file, use:

- Compile the project: `c3c build`
- Run tests: `c3c test`
- Run a specific test: `c3c test --test-filter <test_function_name> --test-show-output`

When  no `project.json` found, use `c3c compile-only <source_file> <...deps_source_files>` for compilation verification.
