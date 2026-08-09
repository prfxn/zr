# zr Specification

## Purpose

`zr` is a zsh configuration-script runner.

A `zr` config is a single trusted zsh file. The config receives a set of tags,
a set of named properties, and an optional argument vector. It may describe its
accepted tags and properties through `configure()`, and performs its work through
`main()`.

`zr` does not interpret the arguments passed to `main()`, and it does not build a
secondary command language. Config files are executable zsh programs: they may
contain ordinary top-level zsh code, define variables and helper functions, and
invoke commands directly. They are trusted by the user and are not sandboxed.

The same config may be invoked explicitly through `zr` or executed directly when
it uses `zr` as its shebang interpreter.


## Terminology

**Configuration**
: The single trusted zsh file loaded for an invocation.

**Invocation name**
: The lexical file or command name by which the configuration was invoked. If
  that name is a symlink, it is the symlink name, not the final target's name.

**Tag**
: A string label describing an active invocation context, such as `prod` or
  `shard1`. Tags may come from the invocation filename or from `+TAG`
  command-line arguments.

**Property**
: A named string value supplied as `NAME=value` before `--`.

**Main argument**
: An argument after `--`. Main arguments are not interpreted by `zr` and are
  passed to `main()` verbatim.

**Schema**
: The tags, tag groups, properties, and property values declared by
  `configure()` for the current invocation context.

## Invocation Forms

The explicit form is:

```text
zr CONFIG [ZR_ARG...] [-- MAIN_ARG...]
```

The direct executable form is:

```text
CONFIG_COMMAND [ZR_ARG...] [-- MAIN_ARG...]
```

where `CONFIG_COMMAND` is an executable config whose shebang invokes `zr`, for
example:

```zsh
#!/usr/bin/env zr
```

A direct command will commonly be a stable symlink on `PATH` pointing at the
actual config file:

```text
~/bin/my-service.prod.shard1 -> ~/configs/my-service
```

Both invocation forms are normalized to the same internal model:

```text
config + tags + properties + main arguments
```

After normalization, execution semantics are identical.

## Command Grammar

Before `--`, every argument after the config is consumed by `zr` and must have
one of these forms:

```text
+TAG
NAME=value
```

`+TAG` supplies a tag.

`NAME=value` supplies a property. `NAME` must be a valid zsh parameter name
matching `[A-Za-z_][A-Za-z0-9_]*`. The value is everything after the first `=`;
it may be empty and may contain additional `=` characters.

The optional `--` token terminates `zr` arguments. Every subsequent token is
passed to `main()` unchanged.

Examples:

```sh
zr ./my-service +prod +shard1 endpoint=/foo/bar
zr ./my-service +prod endpoint=/foo/bar -- arg1 arg2
my-service.prod.shard1 endpoint=/foo/bar -- arg1 arg2
```

The last two examples may normalize to the same invocation state when
`my-service.prod.shard1` is a symlink to `my-service`.

There are no named methods. `main()` is always the execution entry point.

## Tags

Tags are string labels describing the invocation context.

Tags come from two sources:

1. components of the lexical config filename; and
2. `+TAG` command-line arguments.

The two sources are additive.

### Filename Tags

The basename of the config path as invoked is split on `.`. Every non-empty
component is registered as a tag.

For example:

```text
my-service.prod.shard1
```

produces:

```text
my-service
prod
shard1
```

There is no required config filename suffix or extension. A suffix such as
`.zsh` has no special meaning; if present, it is simply another dot-separated
filename component and therefore another tag.

Filename tags are derived from the lexical path used for the invocation, before
resolving symlinks. This permits symlink names to add invocation context while
all symlinks source the same physical config file.

For example:

```text
~/configs/service
~/bin/service.prod.shard1 -> ~/configs/service
```

invoking:

```sh
service.prod.shard1 endpoint=/foo
```

adds the filename tags `service`, `prod`, and `shard1`, while the sourced config
is the physical target `~/configs/service`.

### CLI Tags

A command-line token beginning with `+` adds the remainder of the token as a
tag:

```sh
zr ./service +prod +shard1
```

The leading `+` is command-line syntax only. The semantic tag names are `prod`
and `shard1`; config APIs never include the leading `+`.

A tag supplied by more than one source is represented once in the effective tag
set. Tag matching is exact and case-sensitive.

When represented in `ZR_TAGS`, effective tags preserve first-occurrence order:
filename-derived tags appear first in left-to-right filename order, followed by
CLI tags in command-line order. A duplicate occurrence does not add a second
array element or change the first occurrence's position.

### `ZR_TAGS`

Before the config's interface is evaluated, `zr` exposes the effective tags as
the zsh array:

```zsh
ZR_TAGS=(service prod shard1)
```

Configs should treat `ZR_TAGS` as the canonical representation of invocation
tags.

## Properties

Properties are named string values supplied before `--`:

```sh
endpoint=/foo/bar
region=us-west
```

Before the config's interface is evaluated, `zr` exposes supplied properties as
the zsh associative array `ZR_PROPS`:

```zsh
typeset -A ZR_PROPS
ZR_PROPS=(
  endpoint /foo/bar
  region   us-west
)
```

Configs should treat `ZR_PROPS` as the canonical representation of invocation
properties.

A property name may occur at most once in an invocation. Repeated assignments to
the same property are an error rather than an implicit precedence rule.

Properties are not automatically converted into ordinary shell parameters and
are not automatically exported to child processes.

## Config Contract

A config may provide two framework entry points:

```zsh
configure() {
  ...
}

main() {
  ...
}
```

`main()` is required for normal execution.

`configure()` is optional. When present, it declares the valid invocation
interface for the current tag/property context. Its declarations are used for
both validation and shell completion.

The config owns the plain function names `main` and `configure`. The `zr::`
namespace is reserved for APIs supplied by `zr`.

Top-level code in the config is ordinary initialization code and runs whenever
`zr` sources the config, including when the config is sourced for completion.
Config authors should therefore avoid unnecessary top-level side effects.

## Execution Lifecycle

For normal execution, `zr` performs the following steps:

```text
identify lexical config path
-> derive filename tags
-> resolve physical config file
-> parse CLI tags and properties
-> populate ZR_TAGS and ZR_PROPS
-> source the config
-> invoke configure(), if defined
-> validate the invocation against the declared interface
-> invoke main() with arguments after --
```

`configure()` sees the already-parsed `ZR_TAGS` and `ZR_PROPS`. This is
intentional: the valid interface may depend on tags or properties already
present in the invocation.

If validation fails, `main()` is not invoked.

If `main()` returns, `zr` returns the same status. A config that wants a final
external command to replace the runner process may use normal zsh `exec`.

## The `zr::` Configuration API

Public framework functions use the `zr::` namespace and hyphenated names.
Hyphens are preferred for the public DSL because they read naturally in zsh;
underscores may be used internally by the implementation.

The initial public API consists of declaration, query, and materialization
helpers.

### Declaring Tags

An ungrouped valid tag is declared with:

```zsh
zr::tag TAG
```

For example:

```zsh
zr::tag debug
zr::tag canary
```

### Declaring Tag Groups

A mutually exclusive set of tags is declared with:

```zsh
zr::tag-group GROUP TAG...
```

For example:

```zsh
zr::tag-group env prod dev staging
zr::tag-group shard shard1 shard2 shard3
```

Every member of a tag group is also a declared valid tag.

At most one tag from a group may be active in a valid invocation. For example,
`+prod +dev` is invalid when both belong to the `env` group.

A group also gives semantic meaning to the active member as `GROUP=TAG`; this is
used by `zr::tags-to-env`.

Group names must be valid zsh parameter names. Group names must be unique and
must not collide with declared property names.

### Declaring Properties

A valid property is declared with:

```zsh
zr::prop NAME
```

For example:

```zsh
zr::prop endpoint
zr::prop region
```

Property names must be valid zsh parameter names.

A property name must not collide with a tag-group name.

### Declaring Property Values

A finite set of accepted values for a property may be declared with:

```zsh
zr::values NAME VALUE...
```

For example:

```zsh
zr::prop region
zr::values region us-east us-west
```

When values are declared, a supplied value for that property must exactly match
one of them. When no values are declared, any string value is accepted.

The declared values are also used for completion of `NAME=<TAB>`.

### Querying Current Invocation State

Configs may query the current parsed invocation through `ZR_TAGS` and
`ZR_PROPS` directly. Convenience APIs are also provided:

```zsh
zr::has-tag TAG
zr::has-prop NAME
zr::get NAME
```

`zr::has-tag TAG` succeeds when `TAG` is present in `ZR_TAGS`.

`zr::has-prop NAME` succeeds when `NAME` is present in `ZR_PROPS`, including when
its value is empty.

`zr::get NAME` writes the property's value to stdout. A missing property is
distinct from an explicitly supplied empty value and should produce a non-zero
status.

The query APIs read invocation state; they do not declare interface elements.

## Context-Sensitive Configuration

`configure()` is evaluated after current tags and properties have been parsed.
It may therefore use arbitrary zsh logic to declare different valid interface
elements for different invocation states.

For example:

```zsh
configure() {
  zr::tag-group env prod dev
  zr::prop endpoint

  if zr::has-tag prod; then
    zr::prop region
    zr::values region us-east us-west
  fi

  if [[ $(zr::get region 2>/dev/null) == us-west ]]; then
    zr::tag-group shard shard1 shard2
  fi
}
```

This mechanism is intentionally ordinary zsh rather than a separate condition
language.

The declarations produced by the current call to `configure()` are
authoritative for that invocation state. A tag or property that is not declared
by the resulting interface is invalid when `configure()` is present.

This same rule makes completion naturally context-sensitive: only interface
elements declared for the command line as currently typed are candidates.

## Validation

When `configure()` is defined, `zr` validates the parsed invocation after it
returns.

Validation includes at least:

- every active tag is declared by `zr::tag` or `zr::tag-group`;
- every supplied property is declared by `zr::prop`;
- at most one active tag belongs to each tag group;
- supplied property values satisfy any `zr::values` declaration;
- property names are unique in the invocation;
- tag-group names are unique;
- a property name does not collide with a tag-group name.

Filename-derived tags participate in validation exactly like CLI tags.

When `configure()` is absent, `zr` has no declared schema against which to
validate tags or properties. Parsing rules still apply.

## Materializing Properties as Shell Parameters

`ZR_PROPS` remains the canonical representation of properties. A config may
explicitly materialize properties into ordinary shell parameters when that is
more convenient:

```zsh
zr::props-to-env [NAME...]
```

With no arguments, all supplied properties are materialized. With names, only
those properties are materialized.

For example, given:

```zsh
ZR_PROPS=(
  endpoint /foo
  region   us-west
)
```

then:

```zsh
zr::props-to-env
```

creates ordinary shell parameters equivalent to:

```zsh
endpoint=/foo
region=us-west
```

Despite the `-to-env` name, these parameters are **not** given the zsh export
attribute automatically. Child processes do not inherit them unless the config
explicitly exports them.

Materialization intentionally happens only when requested; `zr` never creates
bare property parameters automatically.

## Materializing Tags as Shell Parameters

A config may explicitly materialize active tags with:

```zsh
zr::tags-to-env [TAG...]
```

With no arguments, all active tags are materialized. With names, only the
selected active tags are materialized.

Each materialized tag produces a namespaced boolean-style parameter. Tag names
are normalized to a valid uppercase shell identifier for this purpose. For
example:

```text
prod       -> ZR_TAG_PROD=1
shard1     -> ZR_TAG_SHARD1=1
my-service -> ZR_TAG_MY_SERVICE=1
```

When a materialized tag belongs to a tag group, the active group value is also
materialized using the group name itself:

```zsh
zr::tag-group env prod dev staging
zr::tag-group shard shard1 shard2
```

with active tags `prod` and `shard1` produces:

```zsh
ZR_TAG_PROD=1
ZR_TAG_SHARD1=1
env=prod
shard=shard1
```

As with `zr::props-to-env`, these are ordinary shell parameters and are not
exported automatically.

Because group names become parameter names, collisions between tag-group names
and property names are configuration errors.

## Completion Model

`zr` provides native zsh completion for both explicit `zr` invocations and
registered direct config commands.

The completion implementation normalizes both forms to the same internal
state:

```text
config path + current tags + current properties + completion position
```

It then uses the config's `configure()` declarations to determine valid
candidates.

### Completion for `zr CONFIG ...`

A normal zsh completion function, conventionally `_zr`, is registered for
`zr`:

```zsh
#compdef zr
```

Before the config argument has been identified, `_zr` completes config paths.
After a config has been identified, it parses the command line typed so far,
derives filename tags, and evaluates the config interface.

### Completion for Direct Config Commands

Zsh does not infer completion behavior from a command's shebang. Direct config
commands must therefore be explicitly associated with `_zr`.

A stable command symlink on `PATH` is the recommended form:

```text
~/bin/my-service -> ~/configs/my-service
```

and may be associated with the same completion implementation using `compdef`:

```zsh
compdef _zr my-service
```

A tagged symlink may likewise be registered:

```text
~/bin/my-service.prod -> ~/configs/my-service
```

```zsh
compdef _zr my-service.prod
```

`_zr` recognizes that it was invoked for a direct config command and treats the
command itself as the config path rather than expecting a separate config
argument.

`zr` does not attempt to inspect arbitrary commands' shebangs during generic
shell completion.

### Completion Isolation

Completion must not source a config directly into the user's interactive shell.
The config and its `configure()` function are evaluated in a zsh subshell.

Conceptually:

```zsh
completion_state=$(
  source "$config"
  configure
  zr::internal-dump-completion-state
)
```

Command substitution already supplies the required subshell isolation; an
additional nested subshell is unnecessary.

This prevents config code from permanently changing the interactive shell's
parameters, functions, options, aliases, current directory, or other mutable
state during `<TAB>`.

Top-level config code still executes inside the isolated completion subshell,
so config authors should keep it suitable for repeated evaluation.

### Completion Rules

Completion uses the currently declared interface and the already-typed
invocation state.

At minimum:

- an already-active tag is not suggested again;
- when one member of a tag group is active, the other members of that group are
  not suggested;
- an already-supplied property is not suggested again;
- only tags and properties declared by the current `configure()` evaluation are
  suggested;
- when completing `NAME=...`, values declared through `zr::values` are
  suggested;
- context-sensitive declarations are reevaluated against the command line as
  currently typed.

The config does not emit raw zsh completion primitives such as `_describe` or
`_values`. It declares its interface through the `zr::` API; `_zr` owns the zsh
completion mechanics.

## Example Config

A complete config may look like:

```zsh
#!/usr/bin/env zr

configure() {
  zr::tag-group env prod dev staging
  zr::tag-group shard shard1 shard2

  zr::tag debug

  zr::prop endpoint
  zr::prop region
  zr::values region us-east us-west

  if zr::has-tag prod; then
    zr::prop timeout
  fi
}

main() {
  if zr::has-tag debug; then
    print -r -- "debug enabled"
  fi

  print -r -- "tags: ${ZR_TAGS[*]}"
  print -r -- "endpoint: ${ZR_PROPS[endpoint]-}"
  print -r -- "main argv: $*"
}
```

It may be invoked explicitly:

```sh
zr ./my-service +prod +shard1 endpoint=/foo region=us-west -- arg1 arg2
```

or directly when executable:

```sh
./my-service +prod +shard1 endpoint=/foo region=us-west -- arg1 arg2
```

or through a filename-tagged symlink:

```text
~/bin/my-service.prod.shard1 -> ~/configs/my-service
```

```sh
my-service.prod.shard1 endpoint=/foo region=us-west -- arg1 arg2
```

In the final form, the lexical command filename supplies the tags
`my-service`, `prod`, and `shard1`; the symlink target supplies the config code;
and `endpoint` and `region` are supplied properties.


## Security Model

Config files are trusted executable zsh. Sourcing a config runs its top-level
code with the permissions of the `zr` process. Normal execution does not sandbox
that code.

Completion evaluates the config in a subshell so that shell state does not leak
back into the user's interactive shell. This is state isolation, not a security
sandbox: config code evaluated for completion can still run external commands or
cause other external side effects with the user's permissions. Work with
irreversible or user-visible side effects should therefore live in `main()`
rather than at top level or in `configure()`.

Command-line tags, property names, property values, and main arguments are data.
An implementation must not reconstruct them as unquoted shell program text or
`eval` them as zsh code. Main arguments must be passed to `main()` as distinct
arguments, and any internal completion metadata representation must preserve
names and values as data rather than executable shell syntax.


## Errors

`zr` should fail with a descriptive diagnostic for at least:

- a missing config operand in explicit `zr CONFIG ...` form;
- a config path that cannot be resolved or sourced;
- malformed arguments before `--`;
- a property name that is not a valid zsh parameter name;
- a repeated property assignment in one invocation;
- a missing `main()` callback during normal execution;
- a source error or non-zero `configure()` result;
- a tag or property not accepted by the current schema when `configure()` is
  present;
- multiple active members of one mutually exclusive tag group;
- a property value outside its declared allowed values;
- duplicate tag-group names;
- a property/tag-group name collision; and
- other contradictory schema declarations once their conflict semantics are
  defined.

Validation errors must prevent `main()` from running. If `main()` runs and
returns normally, its status becomes the `zr` invocation status.


## Unspecified Behavior and Implementation Freedom

The following details are not fully specified by this document. An
implementation should not silently present one choice as part of the public
contract unless the choice is intentionally standardized.

### Tag Identifier Grammar

Property names and tag-group names are valid zsh parameter names, but the full
permitted character set for tag names is not otherwise specified. Existing
examples establish that tags such as `my-service` are valid.

### Tag Materialization Normalization

`zr::tags-to-env` normalizes tag names to uppercase shell identifiers, with the
examples establishing at least that `-` becomes `_`. Handling of other
punctuation, non-ASCII text, leading digits, and collisions between distinct
tags that normalize to the same parameter name is not specified.

### Selective Materialization of Missing Names

`zr::props-to-env NAME...` and `zr::tags-to-env TAG...` select only the named
supplied properties or active tags. The behavior when a requested property was
not supplied or a requested tag is not active is not specified here.

### Declaration Conflicts Beyond Named Groups

The behavior of duplicate declarations of the same tag or property, membership
of one tag in multiple groups, repeated `zr::values` calls for the same
property, and other declaration conflicts not covered by the validation section
is not specified here.

### Error Formatting and Numeric Exit Codes

The exact wording and formatting of diagnostics, and the numeric exit statuses
for parsing, loading, schema, validation, and missing-callback failures, are not
specified. The status propagation rule for `main()` is specified above.

### Config Discovery and Shebang Portability

Exact path-search rules for `CONFIG`, executable requirements, symlink-loop
handling, and portability beyond the shown `#!/usr/bin/env zr` form are not
specified.

### Completion Serialization

The representation used internally to transfer schema/completion metadata out
of the completion subshell is an implementation detail. It must preserve valid
names and values as data and must not evaluate them as zsh code.

## Design Principles

The design intentionally keeps a small programming model:

```text
single trusted zsh config
+ tags
+ properties
+ argv
-> configure()
-> validation
-> main()
```

The key principles are:

- the config file is the unit of configuration and execution;
- filename tags and CLI tags are the same semantic concept after parsing;
- `ZR_TAGS` and `ZR_PROPS` are the canonical invocation state;
- conversion to ordinary shell parameters is explicit and opt-in;
- `configure()` describes the invocation interface rather than implementing zsh
  completion itself;
- the same context-sensitive interface powers both validation and completion;
- `main()` is the only execution entry point;
- direct shebang execution and explicit `zr CONFIG` execution normalize to the
  same runtime model;
- arbitrary config logic remains ordinary zsh rather than a separate expression
  or condition language.
