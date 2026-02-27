# Nushell Anti-Patterns Reference

Common mistakes and their idiomatic fixes when writing Nushell scripts.

## 1. Using `echo` Instead of Implicit Return

Nushell implicitly returns the last expression's value. `echo` is almost never needed.

```nu
# Bad
def greet [name: string]: nothing -> string {
    echo $'Hello, ($name)!'
}

# Good
def greet [name: string]: nothing -> string {
    $'Hello, ($name)!'
}
```

**Exception**: `echo` is useful for generating multiple values in a pipeline:
```nu
echo 1 2 3 | each {|x| $x * 2 }
```

Use `print` when you want to display a message as a side effect (not as return value):
```nu
def process [] {
    print 'Processing...'    # Side effect: displayed to user
    do-work                  # Return value: result of do-work
}
```

## 2. Using `for` as Final Expression

`for` is a statement that returns `null`. Use `each` for transformations.

```nu
# Bad — returns nothing
def squares []: nothing -> list<int> {
    for x in [1 2 3 4] {
        $x ** 2
    }
}

# Good — returns the list
def squares []: nothing -> list<int> {
    [1 2 3 4] | each {|x| $x ** 2 }
}
```

## 3. Mutable Variables for Accumulation

```nu
# Bad — imperative accumulation
mut total = 0
for item in $items {
    $total += $item.price
}
$total

# Good — math sum
$items | get price | math sum

# Bad — building a list with mutation
mut result = []
for f in (ls) {
    if ($f.size > 1mb) {
        $result = ($result | append $f.name)
    }
}

# Good — filter pipeline
ls | where size > 1mb | get name
```

## 4. Dynamic `source`/`use` Paths

Nushell parses all code before evaluation. `source` and `use` require parse-time constant paths.

```nu
# Bad — let is evaluated at runtime, source needs parse-time value
let my_path = '~/scripts'
source $'($my_path)/utils.nu'    # Error!

# Good — use const for parse-time resolution
const my_path = '~/scripts'
source $'($my_path)/utils.nu'
```

## 5. Bash-Style Redirection

```nu
# Bad — > is the comparison operator in Nushell
"hello" > file.txt       # Error! This is a boolean comparison

# Good — use save command
'hello' | save file.txt
'hello' | save --append file.txt   # For appending
```

## 6. String Parsing External Commands

```nu
# Bad — parsing ls output as strings
^ls -la | lines | each {|l| $l | split column ' ' }

# Good — use Nushell's structured ls
ls -la

# Bad — parsing JSON from curl
^curl -s https://api.example.com | from json

# Good — use http get (returns structured data directly)
http get https://api.example.com
```

## 7. Ignoring Type Annotations

```nu
# Bad — untyped command, hard to catch errors
def process [data] {
    $data | get name
}

# Good — typed, catches misuse at parse time
def process [data: record<name: string, age: int>]: nothing -> string {
    $data.name
}

# Good — I/O signature
def double []: int -> int {
    $in * 2
}
```

## 8. Space Before Closure Parameters

```nu
# Bad — space before |params|
ls | each { |f| $f.name }
[1 2 3] | reduce { |x, acc| $x + $acc }

# Good — no space before |params|
ls | each {|f| $f.name }
[1 2 3] | reduce {|x, acc| $x + $acc }
```

## 9. Environment Changes in Regular `def`

```nu
# Bad — cd change is lost after command returns
def go-project [] {
    cd ~/projects/my-app
}
go-project
pwd   # Still in original directory!

# Good — use def --env to propagate environment changes
def --env go-project [] {
    cd ~/projects/my-app
}
go-project
pwd   # Now in ~/projects/my-app
```

## 10. Unnecessary String Interpolation

```nu
# Bad — interpolation with no variables
let msg = $"hello world"

# Good — simple string
let msg = 'hello world'

# Bad — double-quoted interpolation without escapes
let greeting = $"Hello, ($name)!"

# Good — single-quoted interpolation (no escapes needed)
let greeting = $'Hello, ($name)!'
```

## 11. Using `each` When `par-each` Works

```nu
# Suboptimal — sequential file processing
ls **/*.json | each {|f| open $f.name | get version }

# Better — parallel processing for I/O bound work
ls **/*.json | par-each {|f| open $f.name | get version }
```

Use `each` only when: order must be preserved exactly, side effects must be sequential, or the list is very small.

## 12. Missing Command Documentation

```nu
# Bad — no documentation
def deploy [env, --force] {
    # ...
}

# Good — documented command
# Deploy the application to the specified environment
#
# Handles building, testing, and deployment in one step.
# Use --force to skip confirmation prompts.
@example 'Deploy to staging' { deploy staging }
@example 'Force deploy to prod' { deploy production --force }
def deploy [
    env: string     # Target environment (staging, production)
    --force (-f)    # Skip confirmation prompts
] {
    # ...
}
```

## 13. Not Using `default` for Optional Values

```nu
# Bad — verbose null check
let name = if $input == null { 'anonymous' } else { $input }

# Good — use default command
let name = $input | default 'anonymous'
```

## 14. Manual JSON/YAML/TOML Parsing

```nu
# Bad — manual string manipulation
let version = (open Cargo.toml | lines | where $it =~ '^version' | first | split column '=' | get column2.0 | str trim)

# Good — native structured data support
let version = (open Cargo.toml | get package.version)
```

## 15. Not Using `match` for Multi-Branch Logic

```nu
# Bad — chain of if/else
if $status == 'ok' {
    handle-ok
} else if $status == 'error' {
    handle-error
} else if $status == 'pending' {
    handle-pending
} else {
    handle-unknown
}

# Good — pattern matching
match $status {
    ok => { handle-ok }
    error => { handle-error }
    pending => { handle-pending }
    _ => { handle-unknown }
}
```

## 16. Incorrect Shebang for stdin Scripts

```nu
# Bad — script won't receive stdin
#!/usr/bin/env nu

# Good — add --stdin flag
#!/usr/bin/env -S nu --stdin
def main [] {
    $in | process
}
```

## 17. Forgetting `export` in Modules

```nu
# Bad — command is private, can't be imported
# my-module.nu
def helper [] { 'hello' }

# Good — export makes it public
# my-module.nu
export def helper [] { 'hello' }

# Also good — keep internal helpers private intentionally
def internal-helper [] { 'private' }
export def public-cmd [] { internal-helper }
```
