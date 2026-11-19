---
name: tigerstyle-systems
description: >
  TigerStyle systems-programming guidelines — adapted from TigerBeetle's TIGER_STYLE.md for
  C, Odin, and other explicit systems languages. Use this skill whenever the user is writing,
  reviewing, or refactoring C or Odin code, asking about assertions, error handling, memory
  layout, naming conventions, code style, loop safety, or API design in a systems language.
  Also trigger on "review this C code", "is this Odin idiomatic", "how should I structure this
  struct", "how do I handle this error", or any pasted C/Odin snippet. Consult this skill first
  even if the user does not mention style explicitly.
---

# TigerStyle: Systems Programming Guidelines (C, Odin, and Friends)

Adapted from TigerBeetle's [TIGER_STYLE.md](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md).
Design goal priority: **Safety > Performance > Developer Experience**.

This document has three layers:

1. **Core** — language-agnostic rules. Always apply these.
2. **Language Mapping** — how each Core rule lands in C and Odin.
3. **Project Policy** — decisions the project must make explicitly, per codebase.

Read Core first. Then consult the relevant language section. Then check Project Policy for
anything marked _(policy)_.

---

## Layer 1 — Core (language-agnostic)

### 1.1 Control flow

- Use only **simple, explicit control flow**. Recursion is allowed only with a provable bound.
- Split compound conditions into nested `if/else` branches — handle or assert **both** the
  positive and negative spaces.
- State invariants positively:

  ```c
  /* preferred */
  if (index < length) { ... } else { ... }

  /* avoid */
  if (index >= length) { ... }
  ```

- Every `if` branch should prompt the question: does a corresponding `else` also need to be
  handled?
- Do not hide side effects inside conditions. If a condition is expensive or has effects, evaluate
  it once into a named local, then branch on the local.

### 1.2 Assertions

Assertions detect **programmer errors** — not expected runtime errors. The only correct response
to corrupt state is to crash. Assertions downgrade catastrophic correctness bugs into liveness
bugs.

- A function must not operate blindly on data it has not checked. Assert arguments at the entry
  point.
- **Pair assertions**: for any property you want to enforce, assert it on at least two different
  code paths (e.g. just before writing to disk, and immediately after reading back).
- Split compound assertions:

  ```c
  /* preferred */
  assert(a);
  assert(b);

  /* avoid */
  assert(a && b);
  ```

- Use a single-line `if` to assert an implication: `if (a) assert(b);`
- **Assert relationships between compile-time constants** to verify design integrity before the
  program runs:

  ```c
  /* C11 */
  _Static_assert(sizeof(struct Header) == 128, "header layout changed");

  /* Odin */
  #assert(size_of(Header) == 128)
  ```

- Assert both the **positive space** (what you expect true) and the **negative space** (what you
  expect false). The boundary between valid and invalid is where bugs hide.
- Distinguish **always-on checks** from **debug-only assertions** _(policy)_. Critical invariants
  must survive release builds. See Language Mapping.

### 1.3 Memory

- Initialize large structs **in-place via an out pointer** to eliminate intermediate copies and
  guarantee pointer stability:

  ```c
  /* preferred */
  bool foo_init(struct foo *out, ...);

  /* avoid */
  struct foo foo_init(...);   /* may copy */
  ```

- Make ownership explicit in names and comments: `foo_owned`, `foo_borrowed`, `out_foo`,
  `foo_maybe`. Who allocates, who frees, who is responsible must be visible at the call site.
- Prefer static allocation or caller-provided storage over hidden allocators in library code.

### 1.4 Variable scope

- Declare variables at the **smallest possible scope**.
- Declare variables **close to where they are used**. Do not introduce a variable before it is
  needed — this avoids POCPOU bugs (point of check far from point of use, a cousin of TOCTOU).

### 1.5 Loops and queues

- All loops and queues must have a **fixed upper bound** to prevent infinite loops or tail-latency
  spikes. Fail fast when the bound is exceeded.
- Loops that genuinely cannot terminate (an event loop) must be explicitly asserted or commented
  as such.
- Loops over **untrusted input** must have a hard cap. "It terminates in practice" is not a
  bound.

### 1.6 Error handling

- **All errors must be handled.** Most catastrophic production failures come from mishandling
  non-fatal errors.
- An error value must be checked, propagated, or explicitly converted into a panic/assertion
  **with a written reason**. Silent discard is forbidden.
- Do not discard error return values.
- Distinguish **expected errors** (returned to the caller) from **programmer errors** (asserted).
  Never use an error return to signal a bug in the caller.

### 1.7 Functions and structure

- **Keep functions as small as possible.** When splitting, find semantically clean cut points:
  - Centralize all `if`/`switch` in the "parent" function; extract pure logic into helpers.
  - Let the parent own all mutable state; helpers compute what to change but do not apply it.
  - Rule of thumb: [push `if`s up and `for`s down](https://matklad.github.io/2023/11/15/push-ifs-up-and-fors-down.html).
- Extract hot-path loops into **standalone functions with primitive arguments** (no context
  struct, no `self`). This lets the compiler keep fields in registers and lets a human spot
  redundant work.
- Public APIs with two or more arguments of the same type must use a **named options struct**
  (or named arguments) to prevent call-site confusion:

  ```c
  struct read_opts {
      size_t offset;
      size_t length;
      bool   direct_io;
  };
  bool read_sector(int fd, const struct read_opts *opts);
  ```

  ```odin
  read_sector :: proc(fd: Handle, opts: Read_Opts) -> bool
  /* or named arguments */
  read_sector(fd, offset = 0, length = 512, direct_io = true)
  ```

### 1.8 Performance

- Solve performance in the **design phase** — the biggest wins (1000x) come from architecture,
  not post-hoc profiling.
- Do **back-of-the-envelope sketches** across the four resources (network, disk, memory, CPU) and
  their two characteristics (bandwidth, latency).
- Optimize the slowest resource first: network → disk → memory → CPU, weighted by access
  frequency.
- **Batching** is the primary tool: it amortizes network, disk, memory, and CPU costs.
- Distinguish **control plane** from **data plane**; batching lets both coexist safely and fast.
- Be explicit. Do not rely on the compiler to do the right thing.
- **Always pass options explicitly** at library call sites — never rely on defaults.

### 1.9 Naming

- **Do not abbreviate variable names** (primitive integer loop indices in sorts/matrices are the
  only exception).
- Acronyms are fully capitalized: `VSRState`, not `VsrState`.
- **Append units and qualifiers**, ordered by descending significance — the most important word
  comes first:

  ```
  latency_ms_max     /* not max_latency_ms */
  latency_ms_min     /* aligns with the above */
  message_size_max
  ```

- Choose related names with the **same character count** so they align visually:

  ```
  source              target
  source_offset       target_offset
  ```

- Name helper/callback functions with the caller's name as a prefix:
  `read_sector()` → `read_sector_callback()`.
- **Callbacks go last** in the parameter list (mirrors invocation order).
- Infuse names with meaning: `gpa` / `arena` are better than `allocator`.
- Encode ownership and nullability in the name: `foo_owned`, `foo_borrowed`, `foo_maybe`,
  `out_foo`.
- Casing and token conventions are **language-specific** — see Language Mapping and _(policy)_.

### 1.10 Comments

- Comments are full sentences: space after `//`, capital letter, ending with a period (or colon
  when introducing something). Inline end-of-line comments may be phrases without punctuation.
- **Always say why.** Code shows what and how; comments explain the reasoning behind decisions.
- Add a description at the top of tests explaining the goal and methodology.
- On occasion, use an obviously-true assertion _instead of_ a comment to document a critical,
  surprising invariant — the assertion is stronger documentation.

### 1.11 Off-by-one

`index` (0-based), `count` (1-based), and `size` (= count × unit) are **distinct concepts** with
clear conversion rules:

- `index` → `count`: add 1
- `count` → `size`: multiply by the unit size
- Include units and qualifiers in variable names to make conversions visible.

Be explicit about **division rounding intent**. Never write a bare `/` and leave the reader to
guess:

- _exact_ — asserts there is no remainder
- _floor_ — rounds toward negative infinity
- _ceil_ — rounds toward positive infinity

### 1.12 Formatting baseline

- **Hard limit of 100 columns per line**, no exceptions. Let the auto-formatter wrap.
- Always run the project's auto-formatter; CI must enforce it.
- **Always add braces to multi-line `if` statements.** A whole `if` that fits on one line may
  omit them:

  ```c
  if (ok) return;                /* single line: braces optional */

  if (condition) {               /* multi-line: braces required */
      do_something();
  }
  ```

- Indentation width is _(policy)_ — but it must be uniform and enforced by tooling, not by hand.

---

## Layer 2 — Language Mapping

### 2.1 Quick reference

| Concern                        | C                                                                 | Odin                                              |
| ------------------------------ | ----------------------------------------------------------------- | ------------------------------------------------- |
| Auto-formatter                 | `clang-format` with a committed `.clang-format`                   | `odin fmt`, run in CI                             |
| Critical invariant check       | Project `CHECK(expr)` macro, always on                            | `assert(expr)`; note build flags                  |
| Debug-only assertion           | `assert(expr)` (disabled by `NDEBUG`)                             | `assert(expr)`                                    |
| Compile-time assertion         | `_Static_assert(cond, "msg")`                                     | `#assert(cond)`                                   |
| Error propagation              | Error enum + out params, or `struct result`                       | `union { T, Error }` / enum error + `or_return`   |
| Discarding an error            | Forbidden; `(void)foo()` only with review + comment               | Forbidden; no `_ = foo()` for error returns       |
| Unused return values           | `__attribute__((warn_unused_result))` + `-Werror=unused-result`   | `or_return` / `switch`; CI lint                   |
| Exact / floor / ceil division  | `div_exact` / `div_floor` / `div_ceil` helpers                    | Same helpers, or `assert(a % b == 0)` before `/`  |
| Prefetch                       | `__builtin_prefetch(p, 0, 3)`                                     | Platform intrinsic if available; otherwise skip   |
| Protocol / disk / network ints | `<stdint.h>` fixed-width (`uint32_t`, `int64_t`)                  | Fixed-width `u32`, `i64`, `u128`                  |
| Memory size and index          | `size_t` is fine and appropriate                                  | `int` or project convention                       |
| Type names                     | `PascalCase` or `PascalCase_t` _(policy)_                         | `PascalCase`                                      |
| Functions and variables        | `snake_case`                                                      | `snake_case`                                      |
| Constants                      | `SCREAMING_SNAKE_CASE`                                            | `SCREAMING_SNAKE_CASE` or `PascalCase` _(policy)_ |
| File names                     | `snake_case.c` / `snake_case.h`                                   | `snake_case.odin`                                 |
| Options struct at call site    | C99 designated initializer                                        | Named arguments or struct literal                 |
| Indentation                    | From `.clang-format`; 4 spaces is a fine default for new projects | Follow `odin fmt`; do not fight it                |
| Ownership markers              | Name prefixes + comments                                          | Name prefixes + comments                          |

### 2.2 C specifics

- **Warnings are errors.** Compile with `-Wall -Wextra -Werror` plus project-relevant additions
  (`-Wconversion`, `-Wshadow`, `-Wundef`, `-Wcast-qual`, `-Wstrict-prototypes`,
  `-Wmissing-prototypes`, `-Wunused-result`). Zero tolerance.
- **`assert` is not enough.** It vanishes under `NDEBUG`. Define an always-on `CHECK(expr)` in a
  project header that prints file/line and aborts. Use `CHECK` for invariants that must survive
  release builds; use `assert` only for debug-only sanity.
- **Errors are values, not a mode.** Pick one convention per project — an error enum, or an
  `int` with documented meaning — and never mix. Every fallible function that returns an error
  also takes an out parameter for the result. Document whether the out parameter is valid on
  failure (prefer: always zero-initialized on failure).
- **Mark fallible returns** with `__attribute__((warn_unused_result))`. Ban `(void)` casts on
  them unless reviewed and annotated with a reason.
- **No hidden side effects in conditions.** Evaluate once into a named local.
- **`size_t` is not a bug.** The Zig rule "avoid `usize`" translates to: _use fixed-width
  integers on the wire and on disk; use `size_t` for memory sizes and indices._ Do not force
  `uint32_t` on in-memory array lengths.
- **Loops over untrusted input need a hard cap.** `while` loops are the usual suspect; add an
  explicit counter and return an error when exceeded.
- **Strings carry an explicit length.** Do not re-scan with `strlen` in loops; do not rely on NUL
  termination for safety boundaries.
- **Integer overflow.** Unsigned wraparound is defined but must be intentional and commented;
  signed overflow is UB and must be checked. Division rounding goes through the `div_*` helpers.
- **`main` stays at the top of its file**, but the file itself stays small — real logic lives in
  libraries.

### 2.3 Odin specifics

- **Run `odin fmt` in CI.** Do not hand-format against it.
- **`assert`** for programmer errors. **`#assert`** for compile-time relationships between
  constants. Do not rely on assertions surviving every build flag — check the project's build
  configuration.
- **Errors** use `or_return`, `or_else`, or an explicit `switch`. `_ = fallible_call()` to discard
  an error is forbidden; if a return truly must be ignored, write the reason in a comment.
- **`defer`** for resource release. Pair every acquisition with a `defer` at the same scope.
- **Named arguments or options structs** for public APIs with same-type parameters.
- **Casing.** Types `PascalCase`; procedures and variables `snake_case`; constants per project
  (`SCREAMING_SNAKE_CASE` is the common choice).
- **Bounds-check pragmas.** `#no_bounds_check` / `@(no_bounds_check)` only on loops where
  safety is proven and the proof is written next to it.
- **No reflection in hot paths.** Avoid `any` and runtime type queries in the data plane.
- **Fixed-width integers on the wire and on disk**, same rule as C.

---

## Layer 3 — Project Policy

Each project must state these explicitly and record deviations. Defaults are suggestions, not
laws.

1. **Casing and token conventions.** C: types `PascalCase_t` vs `PascalCase`; constants. Odin:
   constant style. Pick one per project.
2. **Indentation and formatting config.** Commit `.clang-format` (C) or rely on `odin fmt`
   (Odin). Do not re-litigate formatting in review.
3. **Dependency policy.** Default: no third-party dependencies beyond the language's standard
   library (C: libc; Odin: `core`). Any new dependency needs a written justification.
4. **Script and tooling language.** Default: the project's primary language. A C project may use
   Python for glue; it should not add a second systems language just for scripts.
5. **Assertion levels.** Which checks are always-on (`CHECK`) vs debug-only (`assert`). Which hot
   paths are allowed to drop assertions for performance, and how that is audited.
6. **Event-loop responsiveness.** The rule "do not react to external events inline; let the
   program run at its own pace" applies to servers, batch processors, storage engines, and
   similar. It does **not** apply to GUIs, interrupt handlers, or hard real-time control loops —
   those need a different policy and must say so.
7. **Error representation.** C: error enum vs `int`; out-parameter validity contract. Odin: error
   enum vs union-with-value, and which is used where.
8. **CI enforcement.** Formatter, warning flags, lint, and any custom `CHECK`/naming checks all
   run in CI. Style that is not enforced will erode.

---

## Pre-commit checklist

**Universal**

- [ ] All lines ≤ 100 columns; auto-formatter has been run.
- [ ] All errors are checked, propagated, or converted to an assertion with a written reason.
- [ ] Variable names include units/qualifiers, are not abbreviated, and align in character count.
- [ ] Compound conditions are split into nested `if/else`; positive and negative spaces handled.
- [ ] All loops have an explicit upper bound (or are documented as intentionally unbounded).
- [ ] Comments explain _why_, not just _what_.
- [ ] Compile-time relationships are verified with a static assertion.
- [ ] Public APIs with same-type parameters use an options struct or named arguments.
- [ ] Large structs are initialized in place via an out pointer.

**C**

- [ ] Builds clean with `-Wall -Wextra -Werror` plus project flags.
- [ ] `CHECK` used for always-on invariants; `assert` only for debug-only checks.
- [ ] Fallible functions carry `warn_unused_result`; no silent `(void)` casts.
- [ ] Wire/disk/network integers use `<stdint.h>`; in-memory sizes use `size_t`.
- [ ] Strings carry explicit lengths; no repeated `strlen` in loops.
- [ ] Division uses `div_exact` / `div_floor` / `div_ceil`, not bare `/`.

**Odin**

- [ ] `odin fmt` run; CI passes.
- [ ] Errors handled with `or_return` / `switch`; no `_ =` on fallible returns.
- [ ] `defer` pairs every acquisition at the same scope.
- [ ] `#assert` used for compile-time invariants.
- [ ] `#no_bounds_check` appears only with a written safety proof.
