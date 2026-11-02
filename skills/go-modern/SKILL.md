---
name: go-modern
description: "Go 1.23–1.26 modern features, migration guide, and best practices for code generation. Use this skill whenever writing new Go code, refactoring existing Go code, reviewing Go code, upgrading Go versions, or generating Go code that should use modern idioms. Trigger on any Go code generation task to ensure the output uses the latest language features (iterators, generic type aliases, new(expr)), modern stdlib APIs (iter, unique, weak, os.Root, errors.AsType, sync.WaitGroup.Go, testing.B.Loop, runtime.AddCleanup), and avoids deprecated patterns (runtime.SetFinalizer, crypto OFB/CFB, httputil.ReverseProxy.Director, math/rand.Seed). Also use when the user asks about Go version differences, migration concerns, GODEBUG settings, or Go modernization."
---

# Go Modern (1.23–1.26) — Code Generation Skill

This skill equips a Code Agent with comprehensive knowledge of Go 1.23 through Go 1.26 features, deprecations, migration pitfalls, and best practices. The goal: **every line of generated Go code should be idiomatic for the target Go version**, leveraging new APIs and avoiding deprecated patterns.

## How to Use This Skill

1. **Determine the target Go version** from the project's `go.mod` (`go` directive). If absent, assume the latest (1.26).
2. **Read the relevant version reference** from `references/` for detailed API signatures, examples, and caveats.
3. **Apply the Quick Reference** below for the most impactful patterns.
4. **Check the Deprecation & Migration tables** before using any API that may have changed.

> The SKILL.md provides the decision framework and quick lookup tables. For full details on each version's changes, read the corresponding reference file.

## References (read on demand)

| File | Content |
|------|---------|
| `references/go1.23.md` | Go 1.23 full changelog: iterators, iter/unique/structs packages, Timer/Ticker changes |
| `references/go1.24.md` | Go 1.24 full changelog: generic type aliases, Swiss Tables, weak/crypto packages, tool directive |
| `references/go1.25.md` | Go 1.25 full changelog: container GOMAXPROCS, GreenTea GC, synctest, json/v2, WaitGroup.Go |
| `references/go1.26.md` | Go 1.26 full changelog: new(expr), recursive constraints, go fix modernizers, errors.AsType, HPKE |
| `references/migration-guide.md` | Cross-version migration guide, GODEBUG settings, breaking changes |
| `references/deprecations.md` | Complete deprecation list with replacements |
| `references/patterns.md` | Modern idiomatic patterns and anti-patterns with before/after examples |

---

## Quick Decision Table: Which Features to Use

When generating Go code, consult this table to pick the most modern API available for the target `go` version:

### Language Features

| Feature | Min Version | Usage |
|---------|-------------|-------|
| Range over int (`for i := range n`) | 1.22+ | Use instead of `for i := 0; i < n; i++` |
| Range over func (iterators) | **1.23+** | Use `iter.Seq[V]` / `iter.Seq2[K,V]` for custom iteration |
| Generic type aliases (`type Set[T] = map[T]bool`) | **1.24+** | Use freely; experimental in 1.23 |
| `new(expr)` with expression argument | **1.26+** | Use `new(someFunc())` to get `*T` from expression |
| Recursive generic constraints | **1.26+** | Self-referencing type constraints are now legal |

### Standard Library — Top Patterns

| Task | Old Way | Modern Way | Min Ver |
|------|---------|------------|---------|
| Iterate map keys sorted | `keys := make([]K, 0); for k := range m { ... }; sort.Slice(...)` | `slices.Sorted(maps.Keys(m))` | **1.23** |
| Iterate slice values | `for _, v := range s` | `for v := range slices.Values(s)` (when composing iterators) | **1.23** |
| Canonicalize/intern values | Manual sync.Map dedup | `unique.Make[T](val)` → `Handle[T]` pointer comparison | **1.23** |
| Set finalizer on object | `runtime.SetFinalizer(obj, fn)` | `runtime.AddCleanup(obj, fn, arg)` | **1.24** |
| Track tool dependencies | `tools.go` with blank imports | `tool` directive in `go.mod` + `go tool <name>` | **1.24** |
| Check error type | `var target *T; errors.As(err, &target)` | `target, ok := errors.AsType[*MyError](err)` | **1.26** |
| Benchmark loop | `for i := 0; i < b.N; i++` | `for b.Loop() { ... }` | **1.24** |
| Test context | `ctx, cancel := context.WithCancel(...)` | `t.Context()` — auto-cancelled when test ends | **1.24** |
| Spawn counted goroutines | `wg.Add(1); go func() { defer wg.Done(); ... }()` | `wg.Go(func() { ... })` | **1.25** |
| Split string lines | `strings.Split(s, "\n")` | `for line := range strings.Lines(s)` | **1.24** |
| JSON omit zero value | `omitempty` (broken for time.Time) | `omitzero` tag | **1.24** |
| Directory-scoped file ops | Manual path joining + validation | `os.OpenRoot("dir")` → `root.Open()/Create()/...` | **1.24** |
| Weak reference | Not possible | `weak.Pointer[T]` | **1.24** |
| Concurrent code testing | Flaky time.Sleep-based tests | `testing/synctest.Test()` with fake clock | **1.25** |
| HTTP CSRF protection | Token-based middleware | `net/http.CrossOriginProtection` (Fetch metadata) | **1.25** |
| Crypto random text | `crypto/rand` + manual encoding | `rand.Text()` — cryptographic Base32 string | **1.24** |
| Read all from reader | `io.ReadAll(r)` (same API) | Same API but ~2x faster, half allocs in **1.26** | **1.26** |
| Multi-handler logging | Manual fan-out | `slog.NewMultiHandler(h1, h2)` | **1.26** |
| Type-specific net dial | `net.Dial("tcp", addr)` | `dialer.DialTCP(ctx, addr)` | **1.26** |

---

## Critical Deprecations — DO NOT USE

These patterns should be avoided in new code. If you see them in existing code during refactoring, suggest the replacement.

| Deprecated | Replacement | Since |
|------------|-------------|-------|
| `runtime.SetFinalizer` | `runtime.AddCleanup` | 1.24 |
| `math/rand.Seed()` | No-op since 1.24; remove the call | 1.24 |
| `runtime.GOROOT()` | `go env GOROOT` | 1.24 |
| `crypto/cipher.NewOFB` | AEAD modes or `NewCTR` | 1.24 |
| `crypto/cipher.NewCFBEncrypter/Decrypter` | AEAD modes or `NewCTR` | 1.24 |
| `net/http/httputil.ReverseProxy.Director` | `ReverseProxy.Rewrite` | 1.26 |
| `crypto/rsa.EncryptPKCS1v15` | OAEP encryption | 1.26 |
| `go/ast.FilterPackage, PackageExports, MergePackageFiles` | Custom implementations | 1.25 |
| `go/parser.ParseDir` | Manual directory walking | 1.25 |
| `//go:linkname` to stdlib internals | Use public APIs | 1.23 |
| `tools.go` blank-import pattern | `tool` directive in go.mod | 1.24 |

---

## GODEBUG Rollback Settings

When migrating, these GODEBUG settings provide escape hatches. Include them as comments in generated code when relevant:

| Setting | Effect | Removal Target |
|---------|--------|----------------|
| `asynctimerchan=1` | Restore buffered Timer/Ticker channels | 1.27 |
| `tlsmlkem=0` | Disable post-quantum key exchange ML-KEM | — |
| `tlssha1=1` | Re-enable SHA-1 in TLS 1.2 | — |
| `tls3des=1` | Re-enable 3DES cipher suites | 1.27 |
| `tlsrsakex=1` | Re-enable pure RSA key exchange | 1.27 |
| `tls10server=1` | Allow TLS 1.0/1.1 on server | 1.27 |
| `x509sha256skid=0` | Use SHA-1 for SubjectKeyId | — |
| `containermaxprocs=0` | Disable container-aware GOMAXPROCS | — |
| `updatemaxprocs=0` | Disable periodic GOMAXPROCS updates | — |
| `rsa1024min=0` | Allow RSA keys < 1024 bits | — |
| `cryptocustomrand=1` | Honor custom random source in crypto | — |
| `urlstrictcolons=0` | Allow malformed URLs with colons in host | — |

---

## Version-Gated Behavior Changes

Some behavior changes only activate when `go.mod` declares a specific minimum version. This is critical for understanding why code behaves differently after upgrading the `go` line:

| Behavior | Activates When `go` ≥ | Impact |
|----------|----------------------|--------|
| Timer/Ticker unbuffered channels, GC-eligible without Stop | `1.23` | `len(timer.C)` returns 0; use non-blocking receive |
| `vet` printf diagnostic for `Printf(s)` | `1.24` | CI may fail if format string is variable without args |
| Container-aware GOMAXPROCS | `1.25` | GOMAXPROCS may be lower than `runtime.NumCPU()` in containers |
| Correct nil pointer check timing | `1.25` | Programs that used return values before checking error may now panic |
| `net/url.Parse` rejects colons in host | `1.26` | `http://::1/` rejected; use `http://[::1]/` |
| `ServeMux` trailing-slash redirect 307 vs 301 | `1.26` | Clients that don't follow 307 may break |

---

## Code Generation Rules

When generating Go code, follow these rules in order of priority:

1. **Check `go.mod` version** — never use features newer than the declared version.
2. **Prefer iterators** (1.23+) for any sequence processing: `slices.Sorted(maps.Keys(m))`, `strings.Lines(s)`, custom `iter.Seq`.
3. **Prefer `b.Loop()`** over `b.N` loop in benchmarks (1.24+).
4. **Prefer `t.Context()`** over manually created contexts in tests (1.24+).
5. **Prefer `wg.Go()`** over `wg.Add(1) + go func() + defer wg.Done()` (1.25+).
6. **Prefer `errors.AsType[T](err)`** over `errors.As(err, &target)` (1.26+).
7. **Use `runtime.AddCleanup`** instead of `runtime.SetFinalizer` (1.24+).
8. **Use `omitzero`** JSON tag for zero-value omission (1.24+), especially for `time.Time`.
9. **Use `os.OpenRoot`** for directory-scoped file operations (1.24+).
10. **Use `testing/synctest`** for concurrent code tests with fake clocks (1.25+).
11. **Never generate `math/rand.Seed()`** — it's a no-op since 1.24.
12. **Never generate `tools.go`** blank-import files — use `tool` directive in go.mod (1.24+).
13. **Run `go fix`** after version upgrades to auto-modernize code (1.26+).

---

## Performance-Aware Patterns

These patterns leverage runtime/compiler improvements across versions:

| Pattern | Why | Version |
|---------|-----|---------|
| Pre-size maps with `make(map[K]V, n)` | Swiss Tables make pre-sized maps ~35% faster for assignment | 1.24+ |
| Use `unique.Make` for dedup/interning | Pointer comparison is faster than value comparison | 1.23+ |
| Use `sync.Map` for concurrent access | Rewritten with hash-trie, ~49% faster geomean | 1.24+ |
| Use `encoding.TextAppender` / `BinaryAppender` | Append to existing slice, avoid allocation | 1.24+ |
| Prefer `crypto/rand.Text()` | Optimized, guaranteed no error return | 1.24+ |
| Avoid `reflect.DeepEqual` for IP comparison | IPv4 vs IPv4-mapped IPv6 bug was fixed in 1.23 | 1.23+ |
| Set `GOAMD64=v3` for float-heavy workloads | FMA instructions: faster + more precise | 1.25+ |
| Use `io.ReadAll` confidently | ~2x faster, half memory in 1.26 | 1.26+ |

---

## Example: Modern Go 1.26 Code

```go
package main

import (
    "errors"
    "fmt"
    "iter"
    "log/slog"
    "maps"
    "slices"
    "sync"
    "testing/synctest"
    "unique"
)

// Generic type alias (1.24+)
type Set[T comparable] = map[T]bool

// new(expr) syntax (1.26+)
func optionalAge(years int) *int {
    return new(years) // pointer to value directly
}

// Iterator pattern (1.23+)
func FilterPositive(seq iter.Seq[int]) iter.Seq[int] {
    return func(yield func(int) bool) {
        for v := range seq {
            if v > 0 {
                if !yield(v) {
                    return
                }
            }
        }
    }
}

// Modern sorted keys (1.23+)
func SortedMapKeys[K cmp.Ordered, V any](m map[K]V) []K {
    return slices.Sorted(maps.Keys(m))
}

// errors.AsType (1.26+)
type AppError struct{ Code int }
func (e *AppError) Error() string { return fmt.Sprintf("code %d", e.Code) }

func handleErr(err error) {
    if appErr, ok := errors.AsType[*AppError](err); ok {
        slog.Error("app error", "code", appErr.Code)
    }
}

// WaitGroup.Go (1.25+)
func processAll(items []string) {
    var wg sync.WaitGroup
    for _, item := range items {
        wg.Go(func() {
            process(item)
        })
    }
    wg.Wait()
}

// Value interning (1.23+)
func intern(s string) unique.Handle[string] {
    return unique.Make(s)
}
```

## Example: Modern Benchmark (1.24+)

```go
func BenchmarkProcess(b *testing.B) {
    data := setupTestData()
    for b.Loop() {  // NOT b.N
        process(data)
    }
    // No b.ResetTimer() needed
    // No sink variable needed — compiler won't optimize away
}
```

## Example: Modern Test (1.24+/1.25+)

```go
func TestService(t *testing.T) {
    ctx := t.Context()  // auto-cancelled when test ends
    t.Chdir("testdata") // auto-restored after test

    svc := NewService(ctx)
    result, err := svc.Process(ctx)
    if err != nil {
        t.Fatal(err)
    }
    // ...
}

// Concurrent test with fake clock (1.25+)
func TestTimeout(t *testing.T) {
    synctest.Test(t, func(t *testing.T) {
        ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
        defer cancel()
        // Time advances instantly when all goroutines block
        <-ctx.Done()
        // This completes immediately, no real 5s wait
    })
}
```
