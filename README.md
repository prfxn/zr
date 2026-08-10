# zr

`zr` provides a lightweight execution harness for zsh scripts, with tags,
properties, validation, and completion.

A `zr` config is a trusted zsh file that receives invocation context as tags,
named properties, and optional positional arguments. The config can declare the
interface it accepts with `configure()` and perform work in `main()`.

See [SPEC.md](./SPEC.md) for the full behavior contract.

## Why

Shell scripts often grow ad hoc option parsing, environment setup, symlink
tricks, and completion logic. `zr` keeps that model small:

```text
single trusted zsh config
+ tags
+ properties
+ argv
-> configure()
-> validation
-> main()
```

The config remains ordinary zsh. `zr` supplies a lightweight convention for
parsing invocation context, validating it, and completing it.

## Invocation

Run a config explicitly:

```sh
zr ./curl-my-service prod shard1 /v1/orders order_id=99 -- arg1 arg2
```

Or make the config executable with a `zr` shebang:

```zsh
#!/usr/bin/env zr
```

Then run it directly:

```sh
./curl-my-service prod shard1 /v1/orders order_id=99 -- arg1 arg2
```

Tagged symlink names can also supply invocation context:

```text
~/bin/curl-my-service.prod.shard1 -> ~/configs/curl-my-service
```

```sh
curl-my-service.prod.shard1 /v1/orders order_id=99 -- arg1 arg2
```

In that form, the lexical command name contributes the tags `curl-my-service`,
`prod`, and `shard1`, while the symlink target provides the config code.
Filename-derived tags are accepted automatically; configs only need to declare
CLI tags they want to validate. A config can also opt into accepting undeclared
CLI tags with `zr::allow-unknown-tags`.

## Arguments

Before `--`, `zr` parses each argument as either a tag or a property:

```text
TAG
NAME=value
```

Tags are string labels such as `prod`, `debug`, `shard1`, or `/v1/orders`.
Properties are named string values such as `order_id=99`.

Arguments after `--` are passed to `main()` unchanged.

## Config Example

```zsh
#!/usr/bin/env zr

configure() {
  zr::allow-unknown-tags

  zr::tag-group env prod dev staging
  zr::tag-group shard shard1 shard2

  zr::tag debug
  zr::tag /v1/orders

  zr::prop order_id
  zr::values order_id 99 100

  zr::prop branch
  zr::pattern branch '^[A-Za-z0-9._/-]+$'

  if zr::has-tag prod; then
    zr::prop timeout
  fi
}

main() {
  if zr::has-tag debug; then
    print -r -- "debug enabled"
  fi

  print -r -- "tags: ${ZR_TAGS[*]}"
  print -r -- "order_id: ${ZR_PROPS[order_id]-}"
  print -r -- "main argv: $*"
}
```

A larger runnable example lives at
[examples/curl-order-service](./examples/curl-order-service). It demonstrates
ordinary zsh arrays, associative arrays, helper functions, context-sensitive
declarations, tag groups, arbitrary string tags such as `/v1/orders`,
constrained and pattern-validated property values, unknown CLI tags, and
runtime-state dumping:

```sh
./zr ./examples/curl-order-service dev /v1/orders region=us-west format=text -- alpha beta
./zr ./examples/curl-order-service prod /v1/invoices debug region=us-east format=json ticket=CHG-123 trace_id=abc -- deploy
```

## Runtime State

Configs read invocation state through:

```zsh
ZR_TAGS
ZR_CLI_TAGS
ZR_KNOWN_TAGS
ZR_UNKNOWN_TAGS
ZR_PROPS
```

`ZR_TAGS` is a zsh array containing effective active tags: filename-derived
tags first, then CLI tags, with duplicates removed. `ZR_CLI_TAGS` contains CLI
tag tokens in command-line order and preserves duplicates. `ZR_KNOWN_TAGS`
contains filename-derived tags and declared CLI tags. `ZR_UNKNOWN_TAGS` contains
undeclared CLI tag occurrences accepted by `zr::allow-unknown-tags`. `ZR_PROPS`
is a zsh associative array containing supplied properties.

Convenience helpers are also available:

```zsh
zr::has-tag TAG
zr::has-prop NAME
zr::get NAME
```

Properties and tag groups are not automatically turned into ordinary shell
parameters. Configs can opt into that with:

```zsh
zr::props-to-env [NAME...]
zr::tag-groups-to-env [GROUP...]
```

These helpers create shell parameters only; they do not automatically export
values to child processes.

## Completion

`zr` is designed so the same `configure()` declarations power validation and
zsh completion.

`zr --completion` prints the `_zr` completion function, so it can be loaded
from your zsh startup files or saved anywhere on `fpath`.

For explicit invocations, `_zr` completes `zr CONFIG ...`.

For direct config commands, register the command with:

```zsh
compdef _zr curl-my-service
compdef _zr curl-my-service.prod
```

Completion evaluates the config in a subshell so shell state does not leak back
into the interactive shell.

## Security

`zr` configs are trusted executable zsh. Sourcing a config runs its top-level
code with the permissions of the `zr` process.

Completion provides shell-state isolation, not a security sandbox. Config code
evaluated for completion can still run external commands or cause side effects,
so irreversible work should live in `main()` rather than at top level or in
`configure()`.

## Specification

The README is intentionally introductory. The detailed grammar, lifecycle,
validation rules, completion model, errors, and currently unspecified behavior
are defined in [SPEC.md](./SPEC.md).
