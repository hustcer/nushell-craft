# Nushell Modules & Type System Reference

## Module Organization

### File-form (simple modules)
```
my-command.nu          # Single-file module
```

### Directory-form (larger modules)
```
my-module/
├── mod.nu             # Module entry point (required)
├── utils.nu           # Submodule
├── config.nu          # Submodule
└── tests/
    ├── mod.nu         # Test module entry point
    └── utils_test.nu  # Test file
```

## Export Types

| Export | Keyword | Example |
|--------|---------|---------|
| Commands | `export def` | `export def my-cmd [] { ... }` |
| Env commands | `export def --env` | `export def --env setup [] { ... }` |
| Aliases | `export alias` | `export alias ll = ls -l` |
| Constants | `export const` | `export const version = '1.0.0'` |
| Externals | `export extern` | `export extern "git push" [...]` |
| Submodules | `export module` | `export module utils.nu` |
| Re-exports | `export use` | `export use utils.nu *` |
| Env setup | `export-env` | `export-env { $env.FOO = 'bar' }` |

## The `main` Convention

When a command name matches the module name, use `export def main`:

```nu
# increment.nu
export def main []: int -> int {
    $in + 1
}

export def by [amount: int]: int -> int {
    $in + $amount
}
```

Usage:
```nu
use increment
5 | increment       # => 6
5 | increment by 3  # => 8
```

## Submodule Patterns

### `export module` — Preserves submodule namespace
```nu
# mod.nu
export module utils.nu      # Commands accessed as: my-module utils <cmd>
```

### `export use` — Flattens into parent namespace
```nu
# mod.nu
export use utils.nu *       # Commands accessed as: my-module <cmd>
```

## Environment Setup

```nu
# mod.nu
export-env {
    $env.MY_MODULE_PATH = ($env.CURRENT_FILE | path dirname)
    $env.MY_MODULE_VERSION = '2.0.0'
}
```

## Type System

### Basic types
```nu
int, float, string, bool, datetime, duration, filesize, binary, nothing
```

### Compound types
```nu
list, list<int>, list<string>
record, record<name: string, age: int>
table, table<name: string, size: filesize>
```

### Special types for annotations
```nu
any          # Accepts any type
number       # Accepts int or float
path         # String with ~ and . expansion
directory    # Subset of path, only directories
closure      # Closure value
cell-path    # Cell path for record/table access
range        # Range value (e.g., 1..10)
glob         # Glob pattern
```

### Type annotations on parameters
```nu
def process [
    name: string                          # Simple type
    items: list<int>                      # Generic type
    config?: record<verbose: bool>        # Optional typed param
    --output (-o): string = 'stdout'      # Flag with type and default
]: table<name: string> -> list<string> {  # I/O signature
    # implementation
}
```

### Multiple I/O signatures
```nu
def normalize []: [
    string -> string
    list<string> -> list<string>
    int -> float
] {
    # implementation varies by input type
}
```

## Testing Conventions

### Nupm package tests
```
my-package/
├── nupm.nuon
├── mod.nu
└── tests/
    ├── mod.nu          # Test entry point
    └── utils_test.nu   # Test file
```

Only fully exported commands from `tests` module are run by `nupm test`.

### Standalone tests with std assert
```nu
use std/assert

# Table-driven tests
for t in [
    [input expected];
    [0 0]
    [1 1]
    [2 1]
    [3 2]
] {
    assert equal (fib $t.input) $t.expected
}
```

### Available assert commands
```nu
use std/assert

assert (condition)                    # Basic assertion
assert equal $actual $expected        # Equality check
assert not equal $a $b               # Inequality check
assert str contains $haystack $needle # String containment
assert length $list $expected_len     # List length
assert error { failing-command }      # Expect an error
```

### Custom assertions
```nu
def "assert positive" [n: int] {
    assert ($n > 0) --error-label {
        text: $'Expected positive number, got ($n)'
        span: (metadata $n).span
    }
}
```

## Attribute System (v0.103+)

```nu
@example 'description' { command args } --result expected_output
@deprecated 'Use new-command instead'
@category 'network'
@search-terms ['http' 'web' 'api']
```

## Parse-Time vs Runtime

| Feature | Parse-time | Runtime |
|---------|-----------|---------|
| `const` values | Yes | No (already resolved) |
| `let` values | No | Yes |
| `source` / `use` paths | Must be known | N/A |
| Type checking | Yes | Some |
| `def` names | Must be literal | N/A |
| Syntax errors | Caught here | N/A |

### Parse-time constant evaluation
```nu
# These work at parse time
const path = 'scripts/utils.nu'
source $path

const items = [1 2 3]
const total = $items | math sum    # Const expressions evaluated at parse time

# This does NOT work — let is runtime
let path = 'scripts/utils.nu'
source $path    # Error: not a parse-time constant
```
