# Nu 0.115 Migration and Review Reference

Use this reference when upgrading to Nu 0.115, reviewing code whose behavior
changed in 0.115, or deciding whether a new 0.115 idiom is compatible with a
project's supported Nushell range.

## Contents

- [Establish the compatibility target](#establish-the-compatibility-target)
- [Breaking changes and migration blockers](#breaking-changes-and-migration-blockers)
- [High-frequency command improvements](#high-frequency-command-improvements)
- [Correctness fixes that affect reviews](#correctness-fixes-that-affect-reviews)
- [Secondary additions and performance](#secondary-additions-and-performance)
- [Migration review checklist](#migration-review-checklist)
- [Focused validation](#focused-validation)

## Establish the Compatibility Target

Check the project's documented minimum/maximum version and CI matrix before
using the local binary as evidence:

```console
nu --version
```

From inside Nushell:

```nu
version | get version
```

Direct comparison operators on `semver` values were added in 0.115. If a
script must still run on 0.114, use a `semver-range` membership test rather than
putting a 0.115-only comparison in the compatibility gate.

## Breaking Changes and Migration Blockers

### YAML now defaults to 1.2 and enforces explicit contracts

`from yaml` now defaults to YAML 1.2. Values such as `yes` and `off` remain
strings, leading-zero decimal values are decimal, and octal uses the `0o`
prefix. Use `--spec 1.1` only for an input contract that intentionally relies
on YAML 1.1 coercion:

```nu
'yes' | from yaml              # string
'yes' | from yaml --spec 1.1   # bool

'0247' | from yaml             # decimal 247
'0247' | from yaml --spec 1.1  # octal 0o247
```

The parser is also stricter at the boundaries where YAML does not map cleanly
to Nushell values:

- Plain mapping keys that resolve to bool, number, or null error because Nu
  record keys are strings. Use `--key-resolution verbatim` only when retaining
  the original key text is the intended contract.
- Unknown tags error. Use `--ignore-tags` only when discarding tag semantics is
  safe; it is not a validation mechanism.
- `--multiple auto` returns one document directly but a list for multiple
  documents. Use `--multiple list` for a stable list-shaped API or
  `--multiple single` to reject streams.
- Anchors, aliases, and merge keys now resolve correctly. Re-test code that
  previously worked around missing merge behavior.

`to yaml` now errors on values such as closures that cannot round-trip. Keep
that safe default. Choose `--non-roundtrip null`, `--non-roundtrip lossy`, or
`--serialize` only when the caller explicitly accepts data loss or
Nushell-specific tags. Generated quoting, indentation, and tags also changed,
so semantic round-trip assertions are more stable than byte-for-byte golden
files.

Useful explicit writer options include `--spec`, `--add-directives`,
`--multiple`, `--indent`, `--quote`, and `--non-roundtrip`.

### Parser keywords and `$ans` are reserved

Commands, aliases, module names, exports, and wildcard imports must not shadow
parser keywords. A module that exports a keyword-named `main` also fails. Check
the final imported namespace, not just the local `def` declarations.

`$ans` is reserved for the last successful REPL result. Rename older bindings
such as `let ans = ...`; do not use `$ans.last` as script state. At the REPL,
the record exposes `last`, `exit_code`, `duration`, and `command`.
`$ans.last` storage is opt-in through `$env.config.max_last_result_size` and
defaults to `0b`, so code must not assume the previous output is retained.

### Test and index commands removed

- `nu --testbin` no longer exists. Replace it with a small Nushell fixture or a
  purpose-built test executable.
- `idx import` and `idx export` were removed. Build the in-memory index with
  `idx init`; use `--no-watch` only when live watching is not wanted.

## High-Frequency Command Improvements

### Preserve raw script CLI tokens with `external_arg`

Use `external_arg` on `main` parameters when a script intentionally needs the
caller's token spelling rather than Nushell literal coercion. For example,
unquoted `0001` and `true` stay token-like `glob` values instead of becoming an
integer and a boolean:

```nu
def main [
    revision: external_arg
    --define (-D): external_arg
    ...rest: external_arg
] {
    let revision_text = ($revision | into string)
    let rest_text = ($rest | each { into string })
    {revision: $revision_text, define: $define, rest: $rest_text}
}
```

Prefer concrete types such as `string`, `int`, or `path` when coercion and type
validation are part of the API. `external_arg` preserves a token; it does not
sanitize it. Validate it before using it as a path or pattern, and pass it as a
separate argv value rather than interpolating it into `nu -c` or a shell
command string.

Nu 0.115 also accepts arguments after `--` for `nu -c` / `nu --commands`.
When a nested Nu process is genuinely required, keep the command text constant,
define a typed `main`, and pass data separately:

```console
nu -c 'def main [value: external_arg] { $value | into string }' -- 0001
```

### Use row conditions with `any` and `all`

Simple predicates can now use the same row-condition syntax as `where`:

```nu
[9 8 7 6] | enumerate | any item == index * 2
[1sec 1min 1hr] | all ($it | describe) == duration
```

Keep a closure when the predicate needs local setup, destructuring, or reuse.
During review, verify that a direct column name is evaluated against a table
row and is not mistaken for an outer variable.

### Slice binary data with filesize counts

`chunks`, `first`, `last`, `take`, `skip`, and `drop` accept `filesize` counts;
`drop` now also accepts binary input. This makes byte intent visible:

```nu
open --raw archive.7z | chunks 10MiB
open --raw packet.bin | first 16b
open --raw packet.bin | skip 8b | take 4b
```

Use an integer for lists/tables unless a byte-sized count is genuinely clearer.
Do not assume a binary chunk is text; decode only after validating its encoding
or at a known character boundary.

### Compare and convert SemVer values directly

Nu 0.115 supports `==`, `!=`, `<`, `<=`, `>`, and `>=` on `semver` values. A
valid version string is accepted on the right-hand side:

```nu
let actual = ('2.0.1' | into semver)
$actual >= '2.0.0'
('1.0.0-alpha' | into semver) < '1.0.0'
```

`into semver` also accepts lists and cell paths. Use `--loose` only for the
documented `v`-style prefixes (`v1.2.3`, `v.1.2.3`, `v:1.2.3`, `v-1.2.3`, or
`v_1.2.3`); it should not replace validation of arbitrary version text. A
loose value converts successfully to the `semver` custom type but retains its
original prefix when converted back to a string; do not assume normalization.

Nu 0.115.0 has a parser inference edge case when a semver comparison is used in
a statically boolean context (for example, `assert (<comparison>)`): the parser
can report `expected bool, found semver`. Assigning it to `let` can instead
infer `semver` and then fail at runtime because the value is actually `bool`.
Until the supported Nu patch release fixes this, evaluate the comparison in an
unconstrained one-item list and extract it at the use site, for example
`assert equal ([($actual >= '2.0.0')] | first) true`. Keep this workaround
version-scoped; do not replace semantic version comparison with lexical string
comparison.

### Include the stopping boundary in stream prefixes

`take while` and `take until` accept `--include N`. `--include 1` commonly
includes the first item that would otherwise stop the command:

```nu
[1 2 3 4] | take until {|n| $n == 3 } --include 1  # [1 2 3]
[1 2 3 4] | take while {|n| $n < 3 } --include 1   # [1 2 3]
```

Review off-by-one behavior explicitly. Values greater than one include more
items after the original stopping point and may trigger additional upstream
side effects on a lazy stream.

### Preserve null groups deliberately

`group-by` now treats null consistently across direct values, cell paths, and
closures. Record output omits the null group because record keys must be
strings; null no longer collapses into the empty-string key. Use table output
when null is data:

```nu
[a '' null] | group-by --to-table
[{x: a} {x: null}] | group-by x --to-table
```

Optional cell paths such as `group-by x?` still skip missing and null values.
This is different from a required path with `--to-table`, which retains the
null group.

### Apply math commands to selected record columns

Reducing commands such as `math avg`, `math sum`, `math max`, and `math
variance`, plus element-wise commands such as `math abs`, `math floor`, and
`math sqrt`, now accept optional cell paths for records containing list-valued
columns:

```nu
{alice: [1 2 3], bob: [4 5 6]} | math avg alice
{alice: [-1 -2], bob: [-3 -4]} | math abs alice
```

Check whether unselected columns intentionally remain unchanged; selecting one
column is not a whole-record reduction.

## Correctness Fixes That Affect Reviews

- Nested `try/finally` no longer consumes an outer error handler. Do not retain
  control-flow workarounds solely for the pre-0.115 bug, but keep `finally`
  limited to cleanup side effects.
- `error make` rejects malformed labels. A spanned label is
  `{text: ..., span: {start: ..., end: ...}}`, not the old flat
  `{text: ..., start: ..., end: ...}` record.
- `scope variables`, `scope commands`, `scope aliases`, `scope modules`, and
  `scope externs` include active local scopes. `scope commands` also exposes
  `deprecation_info`, which review tooling can use instead of maintaining a
  hard-coded deprecated-command list.
- `source` can see current outer variables after a rebinding. Reassess
  pre-0.115 workarounds, but keep source targets trusted and parse-time known.
- `path type` on an empty string returns `null`, not `dir`. An empty or missing
  type must fail validation rather than being treated as a directory.
- Saving structured data to an unknown/no-extension file still requires an
  explicit serializer. Use `to json | save ...`, another `to ...` converter,
  or render a table intentionally.
- `seq` now errors on a zero increment and terminates safely at integer bounds.
  Validate a user-supplied step before calling it to provide domain-specific
  feedback.
- Quoted `#` values now pass correctly as script parameters. Remove shell-style
  escaping workarounds that alter values such as hex colors.
- Assigning `$env.config.keybindings = []` or `.menus = []` merges with defaults
  and no longer clears them. Use a matching binding with `event: null` to
  unbind a key.

## Secondary Additions and Performance

- `from kdl` and `to kdl` support `--spec 1|2` and default to KDL 2. Their
  default data models differ: `from kdl` uses `nodes`, while `to kdl` uses
  JSON-in-KDL (`jik`). Pin both spec and format at file/API boundaries.
- `lines` now produces a list stream lazily even for an in-memory string value.
  Avoid collecting it unless later code needs random access or reuse.
- Large binary slicing and repeated access to large lists/tables are much
  cheaper. Keep streaming for bounded memory; do not add manual caching solely
  to work around the old copy cost without re-measuring.
- `str replace --regex` and `--multiline` are substantially faster on nested
  string data, and built-in regex parameters use a cache. Prefer the built-in
  structured transform before introducing an external text-processing step.
- `date floor` and `date ceil` are available from `std-rfc/date` for duration
  boundary rounding.
- `idx watch` streams indexed filesystem changes and supports filtering,
  timeout, and maximum-event bounds.
- The new `matrix` custom value provides dedicated arithmetic, linear algebra,
  mapping, and reduction commands. Standard `each`, `par-each`, and `reduce`
  intentionally reject matrices; use `matrix map`, `matrix reduce --fold`, and
  `matrix into-nu` at ordinary Nu-data boundaries.

## Migration Review Checklist

1. Record the project's supported Nu range and reproduce on the lowest relevant
   version before recommending 0.115-only syntax.
2. Search YAML call sites and make spec, key, tag, multiple-document, and
   round-trip expectations explicit at external boundaries.
3. Search definitions/imports for parser-keyword names and bindings named
   `ans`.
4. Replace `nu --testbin`, `idx import`, and `idx export` dependencies.
5. Decide whether each script argument wants Nushell typing or raw-token
   preservation; do not apply `external_arg` mechanically.
6. Check `group-by` consumers for null-key loss and empty-string conflation.
7. Check `error make` labels and tests that compare rendered diagnostics.
8. Check `path type`, unknown-extension `save`, and keybinding-reset code for
   assumptions changed in 0.115.
9. Use `scope commands` deprecation metadata to identify active deprecated
   commands, including commands imported into local scopes.
10. Add focused tests for boundary values: YAML 1.1 scalars, multi-document
    inputs, null groups, SemVer prereleases, binary chunk sizes, and include
    counts of zero/one/many.

## Focused Validation

Run the repository smoke test when Nu 0.115 is the active target:

```console
nu --no-config-file tests/nu-0.115-smoke.nu
```

For a migrated script, start with parsing and a no-config execution seam:

```console
nu --no-config-file --ide-check 100 path/to/script.nu
nu --no-config-file path/to/test-script.nu
```

Remember that `--ide-check` requires parsing its JSON Lines output; exit status
alone is not proof that the script has no error diagnostics.
