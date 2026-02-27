---
name: nushell-craft
description: |
  Nushell scripting best practices and code quality enforcement. Use when writing, reviewing, or refactoring Nushell (.nu) scripts to ensure they follow idiomatic patterns, naming conventions, proper type annotations, functional style, and Nushell's unique design principles. Triggers on tasks involving Nushell scripts, modules, custom commands, pipelines, or any .nu file editing. Also helps convert Bash/POSIX scripts to idiomatic Nushell.
---

# Nushell Craft — Best Practices Skill

Write idiomatic, performant, and maintainable Nushell scripts. This skill enforces Nushell conventions and helps avoid common pitfalls.

## Core Principles

1. **Think in pipelines** — Data flows through pipelines; prefer functional transformations over imperative loops
2. **Immutability first** — Use `let` by default; only use `mut` when functional alternatives don't apply
3. **Structured data** — Nushell works with tables, records, and lists natively; leverage structured data over string parsing
4. **Static parsing** — All code is parsed before execution; `source`/`use` require parse-time constants
5. **Implicit return** — The last expression's value is the return value; no need for `echo` or `return`
6. **Scoped environment** — Environment changes are local to their block; use `def --env` when caller-side changes are needed
7. **Type safety** — Annotate parameter types and input/output signatures for better error detection and documentation
8. **Parallel ready** — Immutable code enables easy `par-each` parallelization

## Naming Conventions

| Entity              | Convention             | Example                     |
|---------------------|------------------------|-----------------------------|
| Commands            | `kebab-case`           | `fetch-user`, `build-all`   |
| Subcommands         | `kebab-case`           | `"str my-cmd"`, `date list-timezone` |
| Flags               | `kebab-case`           | `--all-caps`, `--output-dir`|
| Variables/Params    | `snake_case`           | `$user_id`, `$file_path`    |
| Environment vars    | `SCREAMING_SNAKE_CASE` | `$env.APP_VERSION`          |
| Constants           | `snake_case`           | `const max_retries = 3`     |

- Prefer full words over abbreviations unless widely known (`url` ok, `usr` not ok)
- Flag variable access replaces dashes with underscores: `--all-caps` → `$all_caps`

## Formatting Rules

### One-line format (default for short expressions)
```nu
[1 2 3] | each {|x| $x * 2 }
{name: 'Alice', age: 30}
```

### Multi-line format (scripts, >80 chars, nested structures)
```nu
[1 2 3 4] | each {|x|
    $x * 2
}

[
    {name: 'Alice', age: 30}
    {name: 'Bob', age: 25}
]
```

### Spacing rules
- One space before and after `|`
- No space before `|params|` in closures: `{|x| ...}` not `{ |x| ...}`
- One space after `:` in records: `{x: 1}` not `{x:1}`
- Omit commas in lists: `[1 2 3]` not `[1, 2, 3]`
- No trailing spaces
- One space after `,` when used (closures params, etc.)

## Custom Commands Best Practices

### Type annotations and I/O signatures
```nu
# Good — fully typed with I/O signature
def add-prefix [text: string, --prefix (-p): string = 'INFO'] : nothing -> string {
    $'($prefix): ($text)'
}

# Good — multiple I/O signatures
def to-list []: [
    list -> list
    string -> list
] {
    # implementation
}
```

### Documentation with comments and attributes
```nu
# Fetch user data from the API
#
# Retrieves user information by ID and returns
# a structured record with all available fields.
@example 'Fetch user by ID' { fetch-user 42 }
@category 'network'
def fetch-user [
    id: int           # The user's unique identifier
    --verbose (-v)    # Show detailed request info
]: nothing -> record {
    # implementation
}
```

### Parameter guidelines
- Maximum 2 positional parameters; use flags for the rest
- Provide both long and short flag names: `--output (-o): string`
- Use default values: `def greet [name: string = 'World']`
- Use `?` for optional positional params: `def greet [name?: string]`
- Use rest params for variadic input: `def multi-greet [...names: string]`

### Environment-modifying commands
```nu
# Use def --env when the command needs to change caller's environment
def --env setup-project [] {
    cd project-dir
    $env.PROJECT_ROOT = (pwd)
}
```

## Pipeline & Functional Patterns

### Prefer functional over imperative
```nu
# Bad — imperative with mutable variable
mut total = 0
for item in $items {
    $total += $item.price
}

# Good — functional pipeline
$items | get price | math sum

# Bad — mutable counter
mut i = 0
for file in (ls) {
    print $'($i): ($file.name)'
    $i += 1
}

# Good — enumerate
ls | enumerate | each {|it| $'($it.index): ($it.item.name)' }
```

### Use reduce for accumulation
```nu
# Find the longest string
[one two three four] | reduce {|curr, acc|
    if ($curr | str length) > ($acc | str length) { $curr } else { $acc }
}
```

### Use par-each for parallelism
```nu
# Good — parallel processing (I/O or CPU-bound)
ls **/*.rs | par-each {|f| open $f.name | lines | length }

# Use each only when: order matters, side effects are sequential, or list is very small
```

### Pipeline input with $in
```nu
def double-all []: list<int> -> list<int> {
    $in | each {|x| $x * 2 }
}

# Or capture $in early when needed later
def process []: table -> table {
    let input = $in
    let count = $input | length
    $input | first ($count / 2)
}
```

## Variable Best Practices

### Prefer immutability
```nu
# Good — immutable by default
let config = open config.toml
let names = $config.users | get name

# Acceptable — mut when no functional alternative
mut retries = 0
loop {
    if (try-connect) { break }
    $retries += 1
    if $retries >= 3 { error make {msg: 'Connection failed'} }
    sleep 1sec
}
```

### Constants for parse-time values
```nu
# const is required for source/use paths
const lib_path = 'src/lib.nu'
source $lib_path

# const for truly constant values
const max_buffer = 1024
const version = '1.0.0'
```

### Closures cannot capture mut
```nu
# Bad — closures can't capture mutable variables
mut count = 0
ls | each {|f| $count += 1 }  # Error!

# Good — use length or reduce
ls | length

# Or use a loop if mutation is truly needed
mut count = 0
for f in (ls) { $count += 1 }
```

## String Conventions

Refer to the [String Formats Reference](references/string-formats.md) for the full priority list and rules.

**Quick summary (high to low priority):**
1. Bare words in arrays: `[foo bar baz]`
2. Raw strings for regex: `r#'(?:pattern)'#`
3. Single quotes: `'simple string'`
4. Single-quoted interpolation: `$'Hello, ($name)!'`
5. Double quotes only for escapes: `"line1\nline2"`
6. Double-quoted interpolation: `$"tab:\t($value)\n"` (only with escapes)

## Modules & Scripts

### Module structure
```
my-module/
├── mod.nu              # Module entry point
├── utils.nu            # Submodule
└── tests/
    └── mod.nu          # Test module
```

### Export rules
- Only `export` definitions are public
- Use `export def main` when command name matches module name
- Use `export use submodule.nu *` to re-export submodule commands
- Use `export-env` for environment setup blocks

### Script with main command
```nu
#!/usr/bin/env nu

# Build the project
def "main build" [
    --release (-r)    # Build in release mode
] {
    print 'Building...'
}

# Run tests
def "main test" [
    --verbose (-v)    # Show test details
] {
    print 'Testing...'
}

def main [] {
    print 'Usage: script.nu <build|test>'
}
```

## Error Handling

### Custom errors with span info
```nu
def validate-age [age: int] {
    if $age < 0 or $age > 150 {
        let span = (metadata $age).span
        error make {
            msg: 'Invalid age value'
            label: {
                text: $'Age must be between 0 and 150, got ($age)'
                span: $span
            }
        }
    }
    $age
}
```

### try/catch pattern
```nu
let result = try {
    http get 'https://api.example.com/data'
} catch {|err|
    print $'Request failed: ($err.msg)'
    null
}
```

## Testing

### Using std assert
```nu
use std/assert

# Table-driven tests
for t in [
    [input expected];
    [0 0]
    [1 1]
    [2 1]
    [5 5]
] {
    assert equal (fib $t.input) $t.expected
}
```

### Custom assertions
```nu
def "assert even" [number: int] {
    assert ($number mod 2 == 0) --error-label {
        text: $'($number) is not an even number'
        span: (metadata $number).span
    }
}
```

## Common Anti-Patterns

Refer to the [Anti-Patterns Reference](references/anti-patterns.md) for detailed explanations.

| Anti-Pattern | Fix |
|---|---|
| `echo $value` | Just `$value` (implicit return) |
| `$"simple text"` | `'simple text'` (no interpolation needed) |
| `for` as final expression | Use `each` (for doesn't return a value) |
| `mut` for accumulation | Use `reduce` |
| `let path = ...; source $path` | `const path = ...; source $path` |
| `"hello" > file.txt` | `'hello' \| save file.txt` |
| `grep pattern` | `where $it =~ pattern` or built-in `find` |
| Parsing string output | Use structured commands (`ls`, `ps`, `http get`) |
| `$env.FOO = bar` inside `def` | Use `def --env` |
| `{ |x| ... }` (space before pipe) | `{|x| ...}` (no space) |

## Workflow

When writing or reviewing Nushell code:

1. **Read existing code** to understand the context
2. **Check naming** — kebab-case commands, snake_case variables
3. **Check types** — Add/verify type annotations and I/O signatures
4. **Check strings** — Follow the string format priority
5. **Check patterns** — Prefer functional pipelines over imperative loops
6. **Check formatting** — Spacing, line length, multi-line rules
7. **Check documentation** — Comments for exported commands, parameter descriptions
8. **Run validation** if possible — `nu -c 'source file.nu'` or `nu file.nu`
9. **Summarize changes** made

## Getting Help

- Use `nu -c 'help <command>'` to check command signatures and examples
- Use Nushell MCP tools for evaluating and testing Nushell code
- Consult the [Nushell Book](https://www.nushell.sh/book/) for in-depth documentation
