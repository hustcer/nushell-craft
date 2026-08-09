---
name: nushell-pro
description: |
  Comprehensive Nushell scripting best practices, idioms, security, and code review. Use when writing, reviewing, auditing, debugging, or refactoring Nushell (.nu) scripts, modules, custom commands, pipelines, and tests. Also use for Bash/POSIX-to-Nushell conversion and Nu 0.114+ migration issues such as stricter type checking, `run`, SemVer, optional `nothing`, subprocess diagnostics, and explicit submodule imports.
---

# Nushell Pro

Write secure, idiomatic, portable, and testable Nushell. Keep the main workflow
in this file; load detailed references only when the task needs them.

## Operating Workflow

1. Identify the task: new script, debugging, review, refactor, module design,
   migration, performance work, security audit, or Bash conversion.
2. Read the target `.nu` files, nearby tests, `AGENTS.md`, and existing project
   conventions before changing code.
3. Confirm the active version for version-sensitive behavior. From any shell,
   prefer the direct CLI check:

   ```console
   nu --version
   ```

   When already inside Nushell or when structured version data is needed, use:

   ```nu
   version | get version
   ```

4. Load the smallest relevant reference set:

   | Task                                                 | Reference                                                                                     |
   | ---------------------------------------------------- | --------------------------------------------------------------------------------------------- |
   | Nu 0.114+ migration and version compatibility        | [Nu 0.114 Migration](references/nu-0.114-migration.md)                                        |
   | String quoting, interpolation, regex, globs          | [String Formats](references/string-formats.md)                                                |
   | Security, paths, credentials, destructive operations | [Security](references/security.md)                                                            |
   | Script/code review                                   | [Script Review](references/script-review.md) and [Anti-Patterns](references/anti-patterns.md) |
   | Bash/POSIX conversion                                | [Bash to Nushell](references/bash-to-nushell.md)                                              |
   | Modules, exports, scripts, tests                     | [Modules & Scripts](references/modules-and-scripts.md)                                        |
   | Daemons, background jobs, E2E smoke tests            | [Daemon & E2E Smoke Tests](references/daemon-and-e2e-smoke-tests.md)                          |
   | Types, records, lists, conversions                   | [Data & Type System](references/data-and-types.md)                                            |
   | Streaming, closures, performance, diagnostics        | [Advanced Patterns](references/advanced-patterns.md)                                          |
   | Large columnar data                                  | [Dataframes](references/dataframes.md)                                                        |
   | Common mistakes                                      | [Anti-Patterns](references/anti-patterns.md)                                                  |

5. Apply the cross-cutting guardrails below before style or performance cleanup.
6. Validate with the narrowest safe command, then run the relevant tests.
7. Report security/correctness findings before style and performance notes.

If a referenced file is unavailable, say so and continue with this file rather
than inventing its contents.

## Cross-Cutting Guardrails

These rules apply across task types. Load the routed reference before relying
on syntax or behavior that changed between Nushell releases.

### Types and pipeline contracts

- Declare pipeline input in the I/O signature rather than as a positional
  parameter. Capture `$in` once when it must be reused because streams can be
  single-pass.
- Type exported command parameters and input/output signatures.
- Treat external/config records as untrusted; use optional access such as
  `$record.field?` and validate the resulting type/value.
- Remember that `default` evaluates its fallback argument eagerly. Make the
  fallback null-safe or branch explicitly when it can fail or is expensive.
- Keep return types consistent. Avoid `any` unless the function is genuinely
  polymorphic.
- Prefer `match` for several branches on one value; use `if` for one-off boolean
  predicates.

### External commands and errors

- Pass external arguments as separate values, never as an interpolated command
  string. Use `complete` and check `exit_code` when status matters.
- Prefer `try/catch` and `$err.details` for structured in-process errors.
- Treat rendered nested-Nu diagnostics as presentation text, not a stable
  protocol. For CLI tests, normalize ANSI styling, gutters, and PTY wrapping
  before matching a long, domain-specific phrase.

### Security stop checkpoint

Before approving code that executes commands, deletes files, reads credentials,
or accepts paths/patterns, confirm these boundaries:

- Never pass untrusted strings to `nu -c`, `source`, `run`, `^sh -c`,
  `^bash -c`, or `^cmd.exe /C`.
- Pass external command arguments as separate values, not an interpolated shell
  command string.
- For existing paths restricted to a base directory, expand both paths and use
  `path relative-to` to prove containment. A string `starts-with` check is
  unsafe because `/safe/base2` starts with `/safe/base`.
- Prefer Nu's built-in `mktemp`/`mktemp --directory`; it is portable and returns
  a path directly. Do not use predictable temp names.
- Scope secrets with `with-env`; do not log them or pass them in argv when a
  stdin/config-file mechanism exists.
- Guard destructive paths against root, `$nu.home-dir`, unexpected types, and
  untrusted globs. Consider TOCTOU and partial-success behavior.

For output paths that do not exist yet, validate the existing parent directory
with the same containment rule, then join only a validated leaf name.

### Strings and formatting

- Prefer simple literals and raw regex strings; use double quotes only when
  actual escapes are required.
- Remember that `$'...'` interpolates but does not process escape sequences.
- **A literal `(` forces `$"..."`.** Since `$'...'` does no escape processing,
  every `(` inside it opens an interpolation expression and `\(` cannot prevent
  that. Write `$"\(abc)($var)"`, never `$'\(abc)($var)'`. The failure is often
  silent rather than an error: `$'(1 + 1) items'` evaluates to `2 items`. See
  [String Formats](references/string-formats.md).
- Never build command strings for execution.
- Use kebab-case for commands/flags, snake_case for variables/parameters, and
  SCREAMING_SNAKE_CASE for environment variables.

### Data flow and performance

- Prefer pipelines and immutable `let` bindings.
- Use `where`, `select`, `update`, `insert`, `items`, `transpose`, `reduce`, and
  `enumerate` instead of manual parsing and mutable accumulation.
- Do not capture `mut` variables in closures.
- `for` is appropriate for sequential side effects but is not a transforming
  expression; use `each` when a list result is required.
- Use `par-each` only when concurrency is safe and beneficial; preserve `each`
  when order or sequential side effects matter.
- Add `lines` before `parse` when line-by-line stream parsing is intended.
- Use native tables for small interactive data and Polars for large columnar
  group-by/join/aggregation workloads.

### Modules and scripts

- Export only the intended API; keep helpers private.
- Use `export def main` when the command should match the module name.
- Use `def --env`/`export def --env` for caller-visible environment changes.
- `source`, `use`, and `run` targets must be trusted and available at parse time.
- Test at the correct seam: direct functions for stable structured errors, CLI
  subprocesses for argument parsing/process boundaries, and both when needed.

## Review Order

When reviewing code, report findings in this order:

1. Security: injection, traversal, credentials, destructive operations, temp
   files, environment poisoning.
2. Correctness: types, null handling, parse-time constraints, exit codes,
   cleanup/rollback, platform behavior, stable tests.
3. Maintainability: naming, module boundaries, duplication, documentation.
4. Performance: streaming, unnecessary collection, safe parallelism, Polars.

Skip issues already enforced by the project's formatter/linter unless the tool
output shows they are currently failing.

## Validation

Use the narrowest safe commands first:

```bash
nu --no-config-file --ide-check 100 path/to/script.nu
nu -c 'source path/to/module.nu'
nu path/to/test-script.nu
```

- `--ide-check` emits JSON Lines on stdout and may still exit with code `0`
  when a record has `type: "diagnostic"` and `severity: "Error"`. It also
  exits `0` with empty output when the target file does not exist, so verify
  the path exists before treating an empty result as a pass. Parse every
  non-empty line with `from json`; do not use the process exit code alone.
  Treat `severity: "Error"` diagnostics as blockers, surface other severities
  such as `Warning` without blocking, and ignore `type: "hint"` records.
  Handle a non-zero exit code or stderr separately as a CLI startup or I/O
  failure.
- Prefer `--no-config-file` for reproducible standalone checks. Omit it when
  the script intentionally depends on commands or environment from user
  configuration, and document that dependency.
- For scripts with side effects, source/parse-check them or run against a temp
  fixture.
- Reproduce terminal-sensitive tests under a narrow PTY when diagnostics or
  tables are involved, for example `stty cols 24 && nu tests/example.nu`.
- Check diffs for debug markers and accidental changes before finishing.
- If validation fails, fix the smallest reproducible issue and rerun the exact
  failing command before broadening the test suite.
