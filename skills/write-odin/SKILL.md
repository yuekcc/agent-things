---
name: write-odin
description: Odin 语言编程指导。使用 Odin 编程语言时使用
metadata:
  url: https://github.com/4fuu/odin-lang-skill
  license: MIT
---

# Odin Development Guide

Treat the active compiler distribution as the primary source of truth. Odin is still evolving, so remembered syntax and online examples from another release may be wrong for the user's compiler.

## Start with the project

1. Read the README, build scripts, CI, and nearby `.odin` files before choosing commands or layout.
2. Honor any project-pinned compiler/version instead of silently using another installation.
3. Locate the package directory. Odin commands normally take a directory; eligible `.odin` files there form one package and declare the same package name.
4. Capture the active environment without scanning the filesystem:

```text
odin version
odin root
odin help <command>
```

`odin root` resolves matching `base`, `core`, `vendor`, and examples when included, without platform-specific paths. If `odin` is missing, use the official installation guide rather than guessing package-manager or linker setup.

Minimal executable smoke test:

```odin
package main

import "core:fmt"

main :: proc() {
	fmt.println("Hello, Odin!")
}
```

## Command map

Prefer the project's established command. Otherwise use the narrowest applicable command:

```text
odin check <package-dir> -vet                         # executable package
odin check <library-dir> -no-entry-point -vet         # package without main
odin build <package-dir>
odin build <package-dir> -debug                       # debug info + ODIN_DEBUG
odin run <package-dir>
odin run <package-dir> -- <program-args>
odin test <package-dir> -vet                          # @(test) procedures
odin check path/to/file.odin -file -vet               # self-contained file only
odin doc core:fmt -short                              # installed package API
```

- `-file` is for a self-contained file, not a package directory.
- `-vet` is useful for first-party code; preserve intentional project policy and do not impose it on unrelated third-party code.
- Confirm uncommon or release-sensitive flags with `odin help build`, `check`, `test`, or `doc`.
- Custom collections use `-collection:<name>=<directory>` and imports such as `import "<name>:pkg"`. Current compilers can also resolve collection-qualified native library paths in `foreign import`; confirm this in `odin help check` for older project toolchains and reuse the project's convention.

## Find exact APIs before coding

Resolve `<odin-root>` with `odin root`, then use these version-matched locations:

| Need | Path |
|---|---|
| Language feature survey | `<odin-root>/examples/demo/demo.odin` |
| Bundled-example index | `<odin-root>/examples/README.md` |
| `core:x/y` implementation | `<odin-root>/core/x/y/` |
| `vendor:x/y` binding | `<odin-root>/vendor/x/y/` |
| Installed vendor index | `<odin-root>/vendor/README.md` |
| Runtime and intrinsics | `<odin-root>/base/` |

Use `odin doc <collection:package> -short` for discovery, then read that package's source, comments, tests, README, and adjacent examples. For foreign bindings, prefer the installed Odin declarations over upstream C examples: names, types, libraries, feature flags, and ownership may differ.

Official references:

- Docs index: https://odin-lang.org/docs/
- Install: https://odin-lang.org/docs/install/
- Language overview: https://odin-lang.org/docs/overview/
- Annotated demo: https://odin-lang.org/docs/demo/
- Testing: https://odin-lang.org/docs/testing/
- FAQ: https://odin-lang.org/docs/faq/
- `core`/`vendor` APIs: https://pkg.odin-lang.org/
- Idiomatic examples: https://github.com/odin-lang/examples
- Compiler, collections, grammar, and tests: https://github.com/odin-lang/Odin

Online pages may track a newer revision. If sources disagree, prefer project constraints, compiler diagnostics, local source, and a matching release/tag over `master`.

## Core language patterns

Read [the core language patterns](references/language-basics.md) before implementing anything beyond a minimal entry point, diagnosing type/ownership behavior, reviewing unfamiliar syntax, or teaching Odin. It gives compiler-checked examples for declarations, procedures, control flow, types, containers, allocation, optional/error handling, parametric polymorphism, strings/FFI, and tests. For a narrow task, read the relevant headings rather than treating it as a fixed specification.

The official [Odin Overview](https://odin-lang.org/docs/overview/) is the broader language reference and covers many features intentionally omitted here. Consult its relevant section whenever syntax or semantics are unfamiliar or release-sensitive. If documentation and memory are still insufficient, create the smallest disposable package under the system temporary directory and compile it with the project's exact compiler and flags:

```text
odin check <system-temp>/odin-probe -vet
odin test <system-temp>/odin-probe -vet     # assertions or library behavior
odin run <system-temp>/odin-probe           # only when runtime behavior matters
```

Keep probes outside the user's project, reproduce only the uncertain feature, and remove them afterwards. Compiler diagnostics beat speculation.

Keep these high-level guardrails in mind:

- `:=` declares an inferred mutable variable; `::` declares a compile-time entity such as a constant, type, or procedure. Numeric conversions are generally explicit.
- `when` is compile-time control flow; `if` is runtime. `defer` runs when its current lexical scope exits, so scope affects cleanup and paired operations.
- Fixed arrays, slices, dynamic arrays, and maps differ in value semantics, backing storage, and allocation. Identify the owner and lifetime.
- For allocations and resources, use the appropriate `delete`, `free`, package cleanup, or allocator teardown. Place cleanup with `defer` after successful acquisition and check implicit `context.allocator` use.
- Follow each package's actual multi-result, `ok`, error, or union convention; do not invent exceptions or assume a universal error type.
- `string` and `cstring` differ. At FFI boundaries, verify termination, conversion, mutability, and lifetime in the binding source.
- Check current syntax and nearby idioms before using `$` parameters or other parametric features.

## Edit and verify

1. Follow the target package's naming, organization, allocator, and error style; avoid unrelated rewrites.
2. Compile a minimal reproduction with the same compiler whenever an API or syntax point is uncertain.
3. After each logical edit, run `odin check` on the narrowest affected package, then relevant tests. Build or run when linking or runtime behavior matters.
4. Preserve platform suffixes, build tags, foreign-library setup, and project flags.
5. For toolchain failures, collect `odin version`, `odin report`, the exact command, and the first diagnostic before changing dependencies.
6. Report commands that passed and checks that could not run.

Do not freeze a framework or package catalog into this skill. Discover the installed collections and current official examples at task time so the guidance remains small and revision-compatible.
