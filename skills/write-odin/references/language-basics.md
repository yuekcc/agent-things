# Odin Core Language Patterns

Use this reference when writing or reviewing non-trivial Odin. The examples were compiler-checked when authored, but Odin evolves: compile them with the project's active compiler and prefer its diagnostics plus `<odin-root>/examples/demo/demo.odin` if syntax differs.

## Contents

- [Verify unfamiliar or evolving features](#verify-unfamiliar-or-evolving-features)
- [Declarations and zero values](#declarations-and-zero-values)
- [Procedures and results](#procedures-and-results)
- [Control flow, `defer`, and `when`](#control-flow-defer-and-when)
- [Structs, enums, distinct types, and unions](#structs-enums-distinct-types-and-unions)
- [Arrays, slices, dynamic arrays, and maps](#arrays-slices-dynamic-arrays-and-maps)
- [Allocation, ownership, and context](#allocation-ownership-and-context)
- [Optional values and error propagation](#optional-values-and-error-propagation)
- [Parametric polymorphism](#parametric-polymorphism)
- [Strings, Unicode, and `cstring`](#strings-unicode-and-cstring)
- [Tests](#tests)

Most fragments assume:

```odin
package main

import "core:fmt"
```

Declarations such as types and procedures can be placed at file scope. Put executable statements inside `main` or another procedure.

## Verify unfamiliar or evolving features

This file is a practical starting point, not a complete language specification. The official [Odin Overview](https://odin-lang.org/docs/overview/) contains substantially more detail. Jump directly to the relevant section instead of guessing:

| Topic | Official section |
|---|---|
| Declarations, constants, packages | [Variables](https://odin-lang.org/docs/overview/#variable-declarations), [constants](https://odin-lang.org/docs/overview/#constant-declarations), [packages](https://odin-lang.org/docs/overview/#packages) |
| Loops, `switch`, `defer`, `when` | [Control flow](https://odin-lang.org/docs/overview/#control-flow-statements) |
| Procedures and multiple results | [Procedures](https://odin-lang.org/docs/overview/#procedures) |
| Strings and conversions | [Basic types](https://odin-lang.org/docs/overview/#basic-types) |
| Arrays, slices, maps, structs, unions, SOA | [Advanced types](https://odin-lang.org/docs/overview/#advanced-types) |
| Allocators and implicit `context` | [Implicit context system](https://odin-lang.org/docs/overview/#implicit-context-system) |
| Optional/error operators | [`or_else`](https://odin-lang.org/docs/overview/#or_else-expression), [`or_return`](https://odin-lang.org/docs/overview/#or_return-operator) |
| `$` parameters and constraints | [Parametric polymorphism](https://odin-lang.org/docs/overview/#parametric-polymorphism) |
| C ABI and bindings | [Foreign system](https://odin-lang.org/docs/overview/#foreign-system) |
| Attributes, directives, idioms | [Attributes](https://odin-lang.org/docs/overview/#attributes), [directives](https://odin-lang.org/docs/overview/#directives), [useful idioms](https://odin-lang.org/docs/overview/#useful-idioms) |

When a detail remains uncertain, verify it rather than expanding production code around an assumption:

1. Record `odin version` and use the same compiler, target, defines, and collections as the project.
2. Search `<odin-root>/examples/demo/demo.odin` and nearby `core`/`vendor` source for a version-matched idiom.
3. Create a minimal package such as `<system-temp>/odin-probe/main.odin`; do not put exploratory files in the user's repository.
4. Run the narrowest applicable check:

```text
odin check <system-temp>/odin-probe -vet
odin check <system-temp>/probe.odin -file -vet          # self-contained file
odin check <system-temp>/odin-probe -no-entry-point -vet # library-only probe
odin test <system-temp>/odin-probe -vet                 # assertions
odin run <system-temp>/odin-probe                       # runtime behavior only
```

5. Reduce failures to the first useful diagnostic, adjust one assumption at a time, and delete the probe afterwards.

Prefer `odin check` for syntax and type questions because it neither executes the program nor needs a runtime experiment. Use `odin test` for semantic expectations and `odin run` only when execution, allocation, FFI, or other runtime behavior is the question.

## Declarations and zero values

| Form | Meaning |
|---|---|
| `x: int` | Mutable `int`, initialized to its zero value |
| `x: int = 42` | Mutable value with explicit type |
| `x := 42` | Mutable value with inferred type |
| `MAX :: 42` | Compile-time constant/entity |
| `Count : int : 42` | Typed compile-time constant |

Types and procedures are also declared with `::`:

```odin
MAX_RETRIES :: 3

User_ID :: distinct u64

Point :: struct {
	x, y: f32,
}

square :: proc(x: int) -> int {
	return x * x
}

main :: proc() {
	attempts := 0
	answer: i64 = 42
	id := User_ID(7) // explicit conversion to a distinct type
	point := Point{x = 1, y = 2}
	fmt.println(MAX_RETRIES, attempts, answer, id, point, square(6))
}
```

Untyped constants can adapt when representable, but conversions between typed numeric values are generally explicit. `distinct` creates a separate type rather than a freely interchangeable alias.

## Procedures and results

Parameters are values. Pass a pointer when the procedure must mutate caller-owned data. Odin supports multiple results, named results, defaults, and named arguments:

```odin
safe_divide :: proc(a, b: int) -> (quotient: int, ok: bool) {
	if b == 0 {
		return 0, false
	}
	return a / b, true
}

greet :: proc(name: string, punctuation := "!") {
	fmt.printf("Hello, %s%s\n", name, punctuation)
}

increment :: proc(value: ^int) {
	value^ += 1
}

main :: proc() {
	if quotient, ok := safe_divide(84, 2); ok {
		fmt.println(quotient)
	}

	greet("Odin", punctuation = "?")

	value := 41
	increment(&value)
	assert(value == 42)
}
```

Use `^T` for a pointer and `pointer^` for explicit dereference. Struct fields can usually be selected through a struct pointer without spelling the dereference.

## Control flow, `defer`, and `when`

`for` is Odin's only loop statement. It covers C-style loops, while-style loops, infinite loops, ranges, and container iteration:

```odin
Status :: enum {
	Pending,
	Ready,
	Failed,
}

main :: proc() {
	for i := 0; i < 3; i += 1 {
		fmt.println(i)
	}
	for i in 0 ..< 3 { // half-open range: 0, 1, 2
		fmt.println(i)
	}

	values := [3]int{1, 4, 9}
	for value, index in values {
		fmt.println(index, value)
	}

	status := Status.Ready
	switch status {
	case .Pending:
		fmt.println("pending")
	case .Ready:
		fmt.println("ready")
	case .Failed:
		fmt.println("failed")
	}

	when ODIN_DEBUG { // compile-time branch
		fmt.println("debug build")
	}

	{
		fmt.println("scope begin")
		defer fmt.println("scope end")
	}
}
```

- `if` and `switch` are runtime control flow; `when` is compile-time and only the selected branch is checked.
- `switch` does not fall through implicitly. `case:` is the default case; use `#partial switch` only when intentionally omitting enum/union cases.
- Deferred statements run in reverse declaration order when their lexical scope exits. Use a nested block when cleanup must happen before the surrounding procedure returns.
- Container iteration values are copies. Mutate elements through an index or pointer rather than assigning to the iteration value.

## Structs, enums, distinct types, and unions

```odin
User_ID :: distinct u64

User :: struct {
	id:     User_ID,
	name:   string,
	active: bool,
}

State :: enum {
	Idle,
	Running,
}

Payload :: union {
	int,
	string,
}

main :: proc() {
	user := User{id = User_ID(7), name = "Ada"} // active keeps its zero value
	state := State.Running
	assert(state == .Running)

	payload: Payload = "ready"
	if text, ok := payload.(string); ok {
		fmt.println(user, text)
	}

	switch value in payload {
	case int:
		fmt.println(value)
	case string:
		fmt.println(value)
	case: // nil union value
		fmt.println("empty")
	}
}
```

A union is a closed set of possible types. Use `value.(T)` for a checked type assertion and `switch value in union_value` for exhaustive handling. Use `any` only when an open-ended runtime type is actually required.

## Arrays, slices, dynamic arrays, and maps

```odin
main :: proc() {
	fixed := [3]int{1, 4, 9}
	view := fixed[1:] // borrowed view into fixed
	view[0] = 5
	assert(fixed[1] == 5)

	dynamic_values := make([dynamic]int, 0, 4)
	defer delete(dynamic_values)
	append(&dynamic_values, 16, 25)

	scores := make(map[string]int)
	defer delete(scores)
	scores["Ada"] = 99

	if score, exists := scores["Ada"]; exists {
		fmt.println(score)
	}
	missing := scores["Grace"] or_else 0
	fmt.println(missing)
}
```

- `[N]T` is a fixed array value; assigning it copies its elements.
- `[]T` is a slice view over backing storage and does not by itself express ownership.
- `[dynamic]T` can grow; `append` takes its address because growth may replace the backing allocation.
- `map[K]V` lookup can produce `(value, ok)`. Missing keys otherwise yield the element zero value.
- Dynamic arrays, slices, and maps contain references to backing storage. Decide ownership explicitly and avoid double cleanup after shallow copies.

## Allocation, ownership, and context

```odin
main :: proc() {
	owned := new(int)
	defer free(owned)
	owned^ = 42

	allocator := context.allocator
	buffer := make([]int, 3, allocator = allocator)
	defer delete(buffer, allocator)

	fmt.println(owned^, buffer)
}
```

`new(T)` allocates one value; `make` initializes slices, dynamic arrays, and maps. Match them with the correct `free`, `delete`, package-specific destroy procedure, or owning allocator teardown. Do not delete a borrowed slice such as an array view. Many allocation-capable procedures default to `context.allocator`; inspect their signatures before assuming allocation or failure behavior. Arena-style allocators commonly release many allocations together rather than individually.

## Optional values and error propagation

Odin APIs commonly use multiple results, `bool`, an error enum/union, or `Maybe(T)` rather than exceptions. Prefer explicit handling until the local convention is clear:

```odin
Math_Error :: enum {
	None,
	Odd,
}

half_even :: proc(n: int) -> (value: int, err: Math_Error) {
	if n % 2 != 0 {
		return 0, .Odd
	}
	return n / 2, .None
}

quarter_even :: proc(n: int) -> (value: int, err: Math_Error) {
	value = half_even(n) or_return
	value = half_even(value) or_return
	return
}

main :: proc() {
	value, err := quarter_even(84)
	if err != .None {
		fmt.println("error:", err)
	} else {
		fmt.println(value)
	}

	optional: Maybe(int)
	fallback := optional.? or_else 123
	optional = 42
	present, ok := optional.?
	fmt.println(fallback, present, ok)
}
```

`or_else` supplies a fallback for optional-ok expressions. `or_return` propagates the final status result; callers with multiple results require compatible named results. It is concise but less explicit, so use it only when the package already follows that convention and confirm current semantics in the overview/demo.

## Parametric polymorphism

A `$` parameter is known at compile time. It can infer a type from a value or explicitly parameterize a type declaration:

```odin
swap :: proc(a, b: ^$T) {
	a^, b^ = b^, a^
}

Pair :: struct($A, $B: typeid) {
	first:  A,
	second: B,
}

main :: proc() {
	left, right := 1, 2
	swap(&left, &right)

	pair := Pair(string, int){"age", 42}
	fmt.println(left, right, pair)
}
```

Use specialization and `where` constraints only when the simpler inferred form is insufficient. Check current examples before writing complex array-length, type, or value constraints.

## Strings, Unicode, and `cstring`

Compilers that support multiline literals use `"""` for escaped text and three backticks for raw text. Content starts on the following line, the closing delimiter occupies its own line, and indentation matching that delimiter is removed from each content line:

```odin
message := """
	first line
	second line
	"""
```

This produces `"first line\nsecond line"` without a trailing newline. Check the project's compiler with a minimal probe before using this newer syntax with an older toolchain.

Odin `string` values hold UTF-8 bytes. `len(text)` counts bytes; string iteration decodes runes and reports byte offsets:

```odin
package main

import "core:fmt"
import "core:strings"

main :: proc() {
	text := "Hi, 世界"
	fmt.println("bytes:", len(text))
	for r, byte_offset in text {
		fmt.println(byte_offset, r)
	}

	allocator := context.allocator
	owned_cstring, err := strings.clone_to_cstring(text, allocator)
	if err != nil {
		return
	}
	defer free(rawptr(owned_cstring), allocator)

	// Use owned_cstring only while its allocation remains alive.
	fmt.println(owned_cstring)
}
```

`cstring` is a null-terminated pointer for foreign interfaces, not a normal Odin string. Avoid unchecked pointer casts for runtime strings. Use a binding/package conversion that makes termination and ownership explicit, and keep the storage alive for the entire foreign call.

## Tests

Tests use `@(test)` and one `^testing.T` parameter:

```odin
package arithmetic

import "core:testing"

add :: proc(a, b: int) -> int {
	return a + b
}

@(test)
add_test :: proc(t: ^testing.T) {
	testing.expect_value(t, add(20, 22), 42)
}
```

Run it with `odin test <package-dir> -vet`. Use `odin doc core:testing -short` and https://odin-lang.org/docs/testing/ for the current assertion and runner options.
