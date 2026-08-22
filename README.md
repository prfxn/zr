# zr

`zr` provides a lightweight execution harness for zsh scripts, with tags,
properties, named positional arguments, validation, and completion.

A `zr` config is a trusted zsh file that receives invocation context as tags,
named properties, named positional arguments, and optional main arguments. The
config can declare the interface it accepts with `configure()` and perform work
in `main()` by default.

See [SPEC.md](./SPEC.md) for the full behavior contract.

## Why

Shell scripts often grow ad hoc option parsing, environment setup, symlink
tricks, and completion logic. `zr` keeps that model small:

```text
single trusted zsh config
+ tags
+ properties
+ args
+ argv
-> configure()
-> validation
-> main()
```

The entrypoint names default to `configure` and `main`. Configs may define
those names directly or set `ZR_CONFIGURE` and `ZR_MAIN` before defining custom
entrypoint functions. `zr::set-configure NAME` and `zr::set-main NAME` remain
available as compatibility helpers for configs run by an external `zr`.

The config remains ordinary zsh. `zr` supplies a lightweight convention for
parsing invocation context, validating it, and completing it.

## Installation

With Homebrew:

```sh
brew tap prfxn/tap
brew install zr
```

Or install `zr` manually somewhere on your `PATH`:

```sh
mkdir -p ~/.local/bin
install -m 0755 zr ~/.local/bin/zr
```

Install the zsh completion function somewhere on `fpath`:

```sh
mkdir -p ~/.local/share/zsh/site-functions
~/.local/bin/zr --completion-autoload > ~/.local/share/zsh/site-functions/_zr
```

Then load completions from your zsh startup file:

```zsh
fpath=(~/.local/share/zsh/site-functions $fpath)
autoload -Uz compinit
compinit
```

Generate `_zr` from the installed `zr` path. The generated completion records
the runner path, so generating it from a checkout and then installing `zr`
elsewhere may leave completion pointing at the checkout copy.

This enables completion for explicit invocations:

```sh
zr ./curl-my-service prod shard1
```

Executable configs that use a `zr` shebang need their command names registered
with zsh completion too:

```zsh
. <(curl-my-service --completion)
```

The generated per-command completion registers the command name plus a pattern
for direct path invocations and tagged symlink names such as
`curl-my-service.prod` or `curl-my-service.prod.shard1`. For durable autoload
installation:

```sh
curl-my-service --completion-autoload > ~/.local/share/zsh/site-functions/_curl-my-service
```

For shebang configs, `--completion` and `--completion-autoload` are reserved
when they are the first argument after the config command.

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

Or generate a standalone embedded script:

```sh
zr --embed ./curl-my-service > ./curl-my-service.standalone
chmod +x ./curl-my-service.standalone
```

Embedded scripts use a zsh shebang and carry a generated `zr` runtime at the
bottom of the file between markers:

```zsh
# region: zr, version=..., license-url=https://github.com/prfxn/zr/blob/main/LICENSE
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 prfxn
# generated zr runtime
# endregion: zr
```

Running `zr --embed` on an already embedded script replaces the marked runtime
region in the emitted output instead of appending a second copy. The input file
is not modified.

Tagged symlink names can also supply invocation context:

```text
~/bin/curl-my-service.prod.shard1 -> ~/configs/curl-my-service
```

```sh
curl-my-service.prod.shard1 /v1/orders order_id=99 -- arg1 arg2
```

In that form, the lexical command name contributes the tags `curl-my-service`,
`prod`, and `shard1`, while the symlink target provides the config code.
Filename-derived tags are accepted automatically; configs declare accepted CLI
tags and any positional arg slots they want to capture.

## Arguments

Before `--`, `zr` parses each argument as either a bare token or a property:

```text
TAG_OR_ARG
NAME=value
```

Declared tags are string labels such as `prod`, `debug`, `shard1`, or
`/v1/orders`. Properties are named string values such as `order_id=99`. Bare
tokens that are not declared tags can be captured by declared `zr::arg` or
`zr::path-arg` slots in declaration order.

Arguments after `--` are passed to `main()` unchanged.

## Config Example

```zsh
#!/usr/bin/env zr

configure() {
  zr::tag-group env prod dev staging
  zr::tag-group shard shard1 shard2

  zr::tag debug
  zr::tag /v1/orders

  zr::arg branch_name
  zr::path-arg payload_file

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
  print -r -- "branch_name: $(zr::get-arg branch_name)"
  print -r -- "payload_file: $(zr::get-arg payload_file)"
  print -r -- "main argv: $*"
}
```

Custom entrypoints may be selected with variables:

```zsh
ZR_CONFIGURE=setup
ZR_MAIN=run

setup() {
  zr::tag prod
}

run() {
  print -r -- "tags: ${ZR_TAGS[*]}"
}
```

A larger runnable example lives at
[examples/curl-order-service](./examples/curl-order-service). It demonstrates
ordinary zsh arrays, associative arrays, helper functions, context-sensitive
declarations, tag groups, arbitrary string tags such as `/v1/orders`,
named args, path args, constrained and pattern-validated property values, and
runtime-state dumping:

```sh
./zr ./examples/curl-order-service dev /v1/orders REQ-42 ./payload.json region=us-west format=text -- alpha beta
./zr ./examples/curl-order-service prod /v1/invoices debug region=us-east format=json ticket=CHG-123 trace_id=abc -- deploy
```

## Runtime State

Configs read invocation state through:

```zsh
ZR_TAGS
ZR_CLI_TAGS
ZR_KNOWN_TAGS
ZR_PROPS
ZR_ARGS
```

`ZR_TAGS` is a zsh array containing effective active tags: filename-derived
tags first, then declared CLI tags, with duplicates removed. `ZR_CLI_TAGS`
contains bare CLI tokens before `--` in command-line order and preserves
duplicates; after schema classification, those tokens may be tags or captured
args. `ZR_KNOWN_TAGS` contains filename-derived tags and declared CLI tags.
`ZR_PROPS` is a zsh associative array containing supplied properties. `ZR_ARGS`
is a zsh associative array containing supplied `zr::arg` and `zr::path-arg`
values.

`zr::ready` returns success only after the config has been sourced, any
configured `configure()` entrypoint has run, validation has passed, and `main()`
is being invoked. It returns failure during top-level config loading, completion,
and `configure()`.

Convenience helpers are also available:

```zsh
zr::has-tag TAG
zr::has-tag-for-group GROUP
zr::has-prop NAME
zr::get NAME
zr::get-arg NAME
zr::ready
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

`zr --completion` prints and registers the `_zr` completion function for the
current shell. `zr --completion-autoload` prints the autoloadable `_zr`
completion function, so it can be saved anywhere on `fpath`.

For explicit invocations of the form `zr path/to/config ...`, load the
completion function and ensure `zr` itself is registered:

```zsh
autoload -Uz compinit
compinit

. <(zr --completion)
```

After that, `_zr` completes:

```zsh
zr path/to/config ...
```

For direct path invocations of an executable config whose shebang invokes `zr`,
the config can print its own per-command completion installer:

```zsh
. <(examples/curl-order-service --completion)
```

This registers completion for commands such as:

```zsh
examples/curl-order-service ...
/absolute/path/to/curl-order-service ...
```

The `-p` form registers a zsh pattern completion. Because zsh tests pattern
completions against both the typed command and its resolved command path,
`*/curl-order-service` also matches PATH-style invocations when
`curl-order-service` is executable on `PATH`.

For durable autoload installation:

```sh
curl-order-service --completion-autoload > ~/.local/share/zsh/site-functions/_curl-order-service
```

For shebang configs, `--completion` and `--completion-autoload` are reserved
when they are the first argument after the config command. The generated
function uses the installed `zr` runner and evaluates the config in a subshell
so shell state does not leak back into the interactive shell.

Embedded scripts provide the same two completion installation forms:

```zsh
. <(my-script --completion)
```

prints a function such as `_my-script`, plus `compdef` registrations for the
current shell. For durable autoload installation:

```sh
my-script --completion-autoload > ~/.local/share/zsh/site-functions/_my-script
```

The autoload form includes `#compdef my-script`, the `_my-script` function,
the tagged/path pattern registration, and a tail call for the completion request
that caused zsh to load the file.

## Security

`zr` configs are trusted executable zsh. Sourcing a config runs its top-level
code with the permissions of the `zr` process.

Completion provides shell-state isolation, not a security sandbox. Config code
evaluated for completion can still run external commands or cause side effects,
so irreversible work should live in `main()` rather than at top level or in
`configure()`.

## Specification

The detailed grammar, lifecycle, validation rules, completion model, errors, 
and currently unspecified behavior are defined in [SPEC.md](./SPEC.md).


## License

Licensed under the [MIT License](./LICENSE).
