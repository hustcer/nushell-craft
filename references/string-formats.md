# Nushell String Formats Reference

## String Format Priority (High to Low)

1. **Bare word** — Simple word-character-only strings in data contexts
2. **Raw string** `r#'...'#` — Regex patterns, paths with quotes, multi-line content
3. **Single-quoted** `'...'` — Simple strings without embedded single quotes
4. **Single-quoted interpolation** `$'...'` — Interpolation without escape
   sequences **and without literal parentheses**
5. **Backtick** `` `...` `` — Paths/globs with spaces
6. **Double-quoted** `"..."` — Only when escape sequences are needed (`\n`, `\t`, `\"`, etc.)
7. **Double-quoted interpolation** `$"..."` — When interpolation is combined with
   escape sequences **or with a literal `(`** (written `\(`)

## Conversion Rules

### Use bare words when:

- Inside arrays: `[foo bar baz]` not `["foo" "bar" "baz"]`
- Path join arrays: `[$dir patches]` not `[$dir "patches"]`
- Match patterns: `match $x { absolute => ... }` not `match $x { "absolute" => ... }`

### Use raw strings when:

- Regex patterns with special chars: `r#'(?:a/|b/)?'#` not `"(?:a/|b/)?"`
- Strings containing both single and double quotes
- Multi-line content without interpolation

### Use single quotes when:

- Simple strings: `'hello world'` not `"hello world"`
- No escape sequences or interpolation needed

### Use single-quoted interpolation when:

- Variables/expressions present but NO escape sequences:
  - `$'Package: ($pkg.name)'` not `$"Package: ($pkg.name)"`
  - `$'Error: ($msg)'` not `$"Error: ($msg)"`
- …and the string contains **no literal `(`**. If it does, `$'...'` cannot
  express it at all — see
  [Literal parentheses](#literal-parentheses-need-double-quoted-interpolation)
  below.

### Keep double quotes ONLY when:

- Escape sequences present: `"\n"`, `"\t"`, `"\r"`, `"\""`
- Need both interpolation and escapes: `$"Line: ($n)\n"`
- A **literal parenthesis** is needed alongside interpolation: `$"\(abc)($var)"`

### YAML output in 0.113.1+

`to yaml` no longer quotes every string. It emits plain scalars when they are
safe to round-trip as strings, keeps quotes for values that YAML could
reinterpret (for example `'off'`), and emits multiline strings as block scalars.

```nu
{value: 'off', path: '/dev/stdout', name: 'kong'} | to yaml
# value: 'off'
# path: /dev/stdout
# name: kong
```

When testing YAML output, assert parsed structure where possible instead of exact
quote style.

### Important: Single quotes don't escape

In Nushell, `\'` inside `$'...'` is NOT an escape — it's a literal backslash + quote.

```nu
# Correct — use double quotes when literal single quotes needed
let marker = $"'($pkg)@($ver)':"

# Wrong — backslash doesn't escape in single quotes
let marker = $'\'($pkg)@($ver)\':'  # Produces literal backslashes!
```

### Literal Parentheses Need Double-Quoted Interpolation

**Rule: if a string must contain a literal `(`, write it as `$"...\(..."`.
`$'...'` cannot express a literal paren at all.**

This is the single most common interpolation mistake. Because `$'...'` does no
escape processing, `\` is always a literal backslash and `(` _always_ opens an
interpolation expression — `\(` does not stop it. Only `$"..."` treats `\(` as
an escaped, literal paren. From `crates/nu-parser/src/parse_literals.rs`, a `(`
opens an expression when:

```rust
current_byte == b'(' && (!double_quote || preceding_consecutive_backslashes.is_multiple_of(2))
```

For `$'...'` the first disjunct is unconditionally true, so no amount of
backslashes changes the outcome.

Both quote styles interpolate `($var)` identically. The only difference that
matters here is that `$"..."` can escape and `$'...'` cannot.

#### Three failure modes, two of them silent

```nu
let count = 3

# 1. Silent corruption — no error, just a wrong string
$'(1 + 1) items'                   # => "2 items"

# 2. Silent information disclosure — `env` really exists, so it runs
$'Usage: deploy (env) --force'     # => "Usage: deploy HOME=/Users/me
                                   #     API_TOKEN=sk-... --force"

# 3. Runtime error — the paren content is run as an external command
$'Done ($count) file(s)'           # => Error: `s` is neither a Nushell built-in
                                   #    nor a known external command
$'[link](https://example.com)'     # => Error: external command failed
$'expected list(int)'              # => Error: external command failed
```

Failure mode 2 is the reason to treat this as a security item, not just a
correctness one: any parenthesized text that happens to name a real command is
executed and its output is spliced into the string. A message intended for a log
can end up carrying command output or credentials.

#### The fix

```nu
let var = 'X'
let n = 5
let count = 3

$"\(abc)($var)"                    # => "(abc)X"
$"\(1 + 1) items"                  # => "(1 + 1) items"
$"[link]\(https://example.com) ($n)"  # => "[link](https://example.com) 5"
$"Done ($count) file\(s)"          # => "Done 3 file(s)"
$"Usage: deploy \(env) --force"    # => "Usage: deploy (env) --force"
$"expected list\(int)"             # => "expected list(int)"
```

Only `(` needs escaping. A `)` outside an expression is already literal, so
`$"\(abc) ok"` and `$"\(abc\) ok"` both produce `(abc) ok`.

#### Frequent real-world triggers

Markdown links, usage/help text, type names in error messages, `file(s)`-style
pluralization, `(y/n)` prompts, and any regex or code snippet embedded in a
message.

#### When `$'...'` is still the better choice

When there are no literal parens but there _are_ literal backslashes — `$'...'`
avoids doubling every one:

```nu
$'C:\Users\Data ($var)'            # => C:\Users\Data X
$"C:\\Users\\Data ($var)"          # same result, noisier
```

If a string needs both a literal `(` and literal backslashes, `$"..."` is the
only option: escape both (`\(` and `\\`).

#### Decision table

| String contains                      | Use                   |
| ------------------------------------ | --------------------- |
| No interpolation                     | `'...'` or `r#'...'#` |
| Interpolation only                   | `$'...'`              |
| Interpolation + literal `\`          | `$'...'`              |
| Interpolation + literal `(`          | `$"...\(..."`         |
| Interpolation + escapes (`\n`, `\t`) | `$"..."`              |
| Interpolation + literal `(` and `\`  | `$"...\(...\\..."`    |

### Important: Command expressions require `$` prefix

Strings containing Nushell command expressions wrapped in `()` MUST keep the `$` prefix:

```nu
# Correct — $ prefix required for command expressions
print $'(char nl)Done:'
print $'(ansi g)Success!(ansi rst)'

# Wrong — without $ these are literal text
print '(char nl)Done:'      # Prints literal "(char nl)"
print '(ansi g)Success!'    # Prints literal "(ansi g)"
```

**Rule**: If a string contains `(...)` that should be evaluated as a command, always use `$'...'` or `$"..."`.

The converse also holds: if the `(...)` should **not** be evaluated, `$'...'` is
not an option — escape it as `\(` inside `$"..."`. See
[Literal parentheses](#literal-parentheses-need-double-quoted-interpolation).

### External command format strings

For external command format strings, prefer double quotes with a single escape
backslash for simple escape sequences so Nushell materializes the separator
before calling the external tool. `"%H\t%an"` passes an actual tab; `"%H\\t%an"`
passes a literal `\t`. Use `char tab` / `char nl` when the format string also
needs Nushell interpolation or when explicit separators make parsing clearer.

```nu
# Wrong — single quotes pass literal "\t" to git
^git log --format='%H\t%an'

# Wrong — double backslash also passes literal "\t"
^git log --format="%H\\t%an"

# Preferred — simple and Nushell passes an actual tab
^git log --format="%H\t%an"

# Also good — explicit separator, useful with interpolation
let tab = (char tab)
^git log --format=$'%H($tab)%an'

# Also good — use a real newline delimiter, then parse with lines/parse
let nl = (char nl)
^some-tool --format=$'field1=%a($nl)field2=%b'
| lines
| parse '{key}={value}'
```

## String Type Overview

| Format              | Syntax      | Escapes            | Interpolation | Literal `(` | Use case                                    |
| ------------------- | ----------- | ------------------ | ------------- | ----------- | ------------------------------------------- |
| Single-quoted       | `'...'`     | None               | No            | Yes         | Simple strings, Windows paths               |
| Double-quoted       | `"..."`     | `\n \t \" \\` etc. | No            | Yes         | Strings needing escape sequences            |
| Raw string          | `r#'...'#`  | None               | No            | Yes         | Regex, strings with quotes, multi-line      |
| Bare word           | `hello`     | None               | No            | —           | Command arguments, list items               |
| Backtick            | `` `...` `` | None               | No            | Yes         | Paths/args with spaces, globs               |
| Single-interpolated | `$'...'`    | None               | Yes           | **No**      | Embedding variables (preferred default)     |
| Double-interpolated | `$"..."`    | Yes                | Yes           | Yes (`\(`)  | Variables plus escapes **or** a literal `(` |

## Examples

### Array optimization

```nu
# Before
let dirs = [$root, "node_modules", ".pnpm"]
let tools = ["git", "patch"]

# After
let dirs = [$root node_modules .pnpm]
let tools = [git patch]
```

### Interpolation optimization

```nu
# Before
print $"Package: ($pkg.name)"
print $"Error: ($tool) not found"

# After
print $'Package: ($pkg.name)'
print $'Error: ($tool) not found'
```

Do **not** apply this rewrite when the string contains a literal `(` — the
double-quoted form is required there and converting it breaks the string:

```nu
# Keep as-is — `\(` has no equivalent in $'...'
print $"Removed ($n) file\(s)"
print $"See [docs]\(https://example.com)"
```

### Keep double quotes for escapes or literal parens

```nu
# Keep — has \n escape
print $"\nNext steps:"
let content = "line1\nline2"

# Keep — contains literal single quote and interpolation
let marker = $"'($name)@($ver)':"

# Keep — literal parentheses alongside interpolation; $'...' cannot do this
let usage = $"deploy \(env) [--force] — ($count) target\(s)"
```

### Regex with raw strings

```nu
# Before
let pattern = "(?:a/|b/)?"

# After
let pattern = r#'(?:a/|b/)?'#
```
