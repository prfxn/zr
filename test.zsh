#!/usr/bin/env zsh

set -u

ROOT=${0:A:h}
ZR=$ROOT/zr
TMP=${TMPDIR:-/tmp}/zr-tests-$$
mkdir -p $TMP || exit 1
trap 'rm -rf $TMP' EXIT

pass=0
fail=0

record-pass() {
  (( pass++ ))
  print -r -- "ok - $1"
}

record-fail() {
  (( fail++ ))
  print -ru2 -- "not ok - $1"
  [[ $# -gt 1 ]] && print -ru2 -- "$2"
}

run-zr() {
  local name=$1
  shift
  local stdout=$TMP/$name.out
  local stderr=$TMP/$name.err
  zsh $ZR "$@" >$stdout 2>$stderr
  return $?
}

assert-success() {
  local name=$1
  shift
  if run-zr $name "$@"; then
    record-pass $name
  else
    record-fail $name "$(<$TMP/$name.err)"
  fi
}

assert-failure() {
  local name=$1 expected=$2
  shift 2
  if run-zr $name "$@"; then
    record-fail $name "expected failure containing: $expected"
  elif grep -Fq -- "$expected" $TMP/$name.err; then
    record-pass $name
  else
    record-fail $name "stderr did not contain $expected; got: $(<$TMP/$name.err)"
  fi
}

assert-output-contains() {
  local name=$1 expected=$2
  if grep -Fq -- "$expected" $TMP/$name.out; then
    record-pass "$name output contains $expected"
  else
    record-fail "$name output contains $expected" "stdout was: $(<$TMP/$name.out)"
  fi
}

cat >$TMP/basic.zsh <<'CONFIG'
configure() {
  zr::tag-group env prod dev
  zr::tag debug
  zr::prop region
  zr::values region us-east us-west
  zr::prop branch
  zr::pattern branch '^[A-Za-z0-9._/-]+$'
  zr::prop customer
  zr::validate customer validate_customer
  zr::prop anything
}

validate_customer() {
  [[ $1 =~ '^[a-z0-9-]+$' ]]
}

main() {
  print -r -- "tags=${ZR_TAGS[*]}"
  print -r -- "cli=${ZR_CLI_TAGS[*]}"
  print -r -- "known=${ZR_KNOWN_TAGS[*]}"
  print -r -- "branch=${ZR_PROPS[branch]-}"
  print -r -- "customer=${ZR_PROPS[customer]-}"
}
CONFIG

cat >$TMP/dollar-tag.zsh <<'CONFIG'
configure() {
  zr::tag "money\$tag"
  zr::tag plain
}
main() { :; }
CONFIG

cat >$TMP/args.zsh <<'CONFIG'
configure() {
  zr::tag-group env prod dev
  zr::tag debug
  zr::prop region
  zr::arg feature
  zr::arg build
  zr::path-arg config_file
}

main() {
  print -r -- "tags=${ZR_TAGS[*]}"
  print -r -- "cli=${ZR_CLI_TAGS[*]}"
  print -r -- "known=${ZR_KNOWN_TAGS[*]}"
  print -r -- "feature=$(zr::get-arg feature)"
  print -r -- "build=$(zr::get-arg build)"
  print -r -- "config_file=$(zr::get-arg config_file)"
  if zr::get-arg missing >/dev/null; then
    print -r -- "missing=yes"
  else
    print -r -- "missing=no"
  fi
}
CONFIG

cat >$TMP/group-query.zsh <<'CONFIG'
configure() {
  zr::tag-group env prod dev
  zr::tag-group shard shard1 shard2
}

main() {
  if zr::has-tag-for-group env; then
    print -r -- "has_env=yes"
  else
    print -r -- "has_env=no"
  fi

  if zr::has-tag-for-group shard; then
    print -r -- "has_shard=yes"
  else
    print -r -- "has_shard=no"
  fi
}
CONFIG

cat >$TMP/ready.zsh <<'CONFIG'
ready_state() {
  if zr::ready; then
    print -r -- "$1=ready"
  else
    print -r -- "$1=not-ready"
  fi
}

ready_state top

configure() {
  ready_state configure
  zr::tag prod
}

main() {
  ready_state main
}
CONFIG

cat >$TMP/conflict.zsh <<'CONFIG'
configure() {
  zr::prop branch
  zr::values branch main
  zr::pattern branch '^.*$'
}
main() { :; }
CONFIG

cat >$TMP/dynamic-args.zsh <<'CONFIG'
configure() {
  zr::tag prod
  zr::arg feature
  if [[ $(zr::get-arg feature) == feature-x ]]; then
    zr::prop feature_seen
  fi
}

main() {
  print -r -- "feature=$(zr::get-arg feature)"
  print -r -- "feature_seen=${ZR_PROPS[feature_seen]-}"
}
CONFIG

cat >$TMP/dynamic-default-entrypoints.zsh <<'CONFIG'
$(zr::configure)() {
  zr::tag prod
  zr::prop branch
}

$(zr::main)() {
  print -r -- "dynamic-default branch=${ZR_PROPS[branch]-}"
}
CONFIG

cat >$TMP/custom-entrypoints.zsh <<'CONFIG'
zr::set-configure setup
zr::set-main run

$(zr::configure)() {
  zr::tag prod
  zr::prop branch
}

$(zr::main)() {
  print -r -- "custom branch=${ZR_PROPS[branch]-} argv=$*"
}
CONFIG

cat >$TMP/custom-entrypoints-direct.zsh <<'CONFIG'
zr::set-configure setup
zr::set-main run

setup() {
  zr::tag prod
  zr::prop branch
}

run() {
  print -r -- "direct custom branch=${ZR_PROPS[branch]-}"
}
CONFIG

cat >$TMP/custom-entrypoints-vars.zsh <<'CONFIG'
ZR_CONFIGURE=setup
ZR_MAIN=run

setup() {
  zr::tag prod
  zr::prop branch
}

run() {
  print -r -- "vars custom branch=${ZR_PROPS[branch]-} argv=$*"
}
CONFIG

cat >$TMP/missing-custom-main.zsh <<'CONFIG'
zr::set-main run
main() { :; }
CONFIG

cat >$TMP/missing-custom-configure.zsh <<'CONFIG'
zr::set-configure setup
main() { :; }
CONFIG

cat >$TMP/reject-zr-main.zsh <<'CONFIG'
zr::set-main zr::run
zr::run() { :; }
CONFIG

cat >$TMP/reject-zr-configure.zsh <<'CONFIG'
zr::set-configure zr::setup
main() { :; }
CONFIG

cat >$TMP/duplicate-arg.zsh <<'CONFIG'
configure() {
  zr::arg value
  zr::path-arg value
}
main() { :; }
CONFIG

cat >$TMP/arg-prop-collision.zsh <<'CONFIG'
configure() {
  zr::arg target
  zr::prop target
}
main() { :; }
CONFIG

cat >$TMP/arg-group-collision.zsh <<'CONFIG'
configure() {
  zr::arg env
  zr::tag-group env prod dev
}
main() { :; }
CONFIG

assert-failure undeclared-bare-token-default "argument not accepted by config: feature-x" $TMP/basic.zsh prod feature-x

assert-success arg-capture $TMP/args.zsh prod feature-x build-17 ./config.yml debug
assert-output-contains arg-capture "tags=args zsh prod debug"
assert-output-contains arg-capture "cli=prod feature-x build-17 ./config.yml debug"
assert-output-contains arg-capture "known=args zsh prod debug"
assert-output-contains arg-capture "feature=feature-x"
assert-output-contains arg-capture "build=build-17"
assert-output-contains arg-capture "config_file=./config.yml"
assert-output-contains arg-capture "missing=no"

assert-success arg-optional $TMP/args.zsh prod feature-x
assert-output-contains arg-optional "feature=feature-x"
assert-output-contains arg-optional "build="
assert-output-contains arg-optional "config_file="

assert-success arg-tag-precedence $TMP/args.zsh debug feature-x prod
assert-output-contains arg-tag-precedence "tags=args zsh debug prod"
assert-output-contains arg-tag-precedence "feature=feature-x"
assert-output-contains arg-tag-precedence "build="

assert-success arg-duplicate-values $TMP/args.zsh feature-x feature-x
assert-output-contains arg-duplicate-values "feature=feature-x"
assert-output-contains arg-duplicate-values "build=feature-x"

assert-failure arg-extra "argument not accepted by config: too-much" $TMP/args.zsh one two three too-much
assert-failure duplicate-arg "duplicate argument: value" $TMP/duplicate-arg.zsh value
assert-failure arg-prop-collision "property collides with argument: target" $TMP/arg-prop-collision.zsh value
assert-failure arg-group-collision "tag group collides with argument: env" $TMP/arg-group-collision.zsh value

assert-success group-query $TMP/group-query.zsh prod
assert-output-contains group-query "has_env=yes"
assert-output-contains group-query "has_shard=no"

assert-success ready $TMP/ready.zsh prod
assert-output-contains ready "top=not-ready"
assert-output-contains ready "configure=not-ready"
assert-output-contains ready "main=ready"

assert-success configure-sees-arg $TMP/dynamic-args.zsh prod feature-x feature_seen=yes
assert-output-contains configure-sees-arg "feature=feature-x"
assert-output-contains configure-sees-arg "feature_seen=yes"

assert-success dynamic-default-entrypoints $TMP/dynamic-default-entrypoints.zsh prod branch=main
assert-output-contains dynamic-default-entrypoints "dynamic-default branch=main"

assert-success custom-entrypoints $TMP/custom-entrypoints.zsh prod branch=main -- alpha beta
assert-output-contains custom-entrypoints "custom branch=main argv=alpha beta"

assert-success custom-entrypoints-direct $TMP/custom-entrypoints-direct.zsh prod branch=main
assert-output-contains custom-entrypoints-direct "direct custom branch=main"

assert-success custom-entrypoints-vars $TMP/custom-entrypoints-vars.zsh prod branch=main -- alpha beta
assert-output-contains custom-entrypoints-vars "vars custom branch=main argv=alpha beta"

assert-failure missing-custom-main "config does not define run()" $TMP/missing-custom-main.zsh
assert-failure missing-custom-configure "config does not define setup()" $TMP/missing-custom-configure.zsh
assert-failure reject-zr-main "invalid main function name: zr::run" $TMP/reject-zr-main.zsh
assert-failure reject-zr-configure "invalid configure function name: zr::setup" $TMP/reject-zr-configure.zsh

assert-success pattern-valid $TMP/basic.zsh prod branch=feature/x
assert-output-contains pattern-valid "branch=feature/x"
assert-failure pattern-invalid "invalid value for property 'branch': bad space" $TMP/basic.zsh prod branch="bad space"

assert-success validator-valid $TMP/basic.zsh prod customer=acme-123
assert-output-contains validator-valid "customer=acme-123"
assert-failure validator-invalid "invalid value for property 'customer': Acme" $TMP/basic.zsh prod customer=Acme

assert-success unrestricted-prop $TMP/basic.zsh prod anything="bad space ok"
assert-failure values-invalid "invalid value for property 'region': eu" $TMP/basic.zsh prod region=eu
assert-failure mode-conflict "cannot combine zr::values with zr::pattern" $TMP/conflict.zsh

completion_values=$(zsh $ZR --_zr-complete $TMP/basic.zsh --current region=us prod)
if [[ $completion_values == *region=us-east* && $completion_values == *region=us-west* ]]; then
  record-pass completion-values
else
  record-fail completion-values "got: $completion_values"
fi

completion_pattern_name=$(zsh $ZR --_zr-complete $TMP/basic.zsh --current br prod)
if [[ $completion_pattern_name == branch= ]]; then
  record-pass completion-pattern-name
else
  record-fail completion-pattern-name "got: $completion_pattern_name"
fi

completion_custom_name=$(zsh $ZR --_zr-complete $TMP/custom-entrypoints.zsh --current br prod)
if [[ $completion_custom_name == branch= ]]; then
  record-pass completion-custom-name
else
  record-fail completion-custom-name "got: $completion_custom_name"
fi

completion_custom_vars_name=$(zsh $ZR --_zr-complete $TMP/custom-entrypoints-vars.zsh --current br prod)
if [[ $completion_custom_vars_name == branch= ]]; then
  record-pass completion-custom-vars-name
else
  record-fail completion-custom-vars-name "got: $completion_custom_vars_name"
fi

completion_pattern_value=$(zsh $ZR --_zr-complete $TMP/basic.zsh --current branch= prod)
if [[ -z $completion_pattern_value ]]; then
  record-pass completion-pattern-value-empty
else
  record-fail completion-pattern-value-empty "got: $completion_pattern_value"
fi

completion_path_marker=$(zsh $ZR --_zr-complete $TMP/args.zsh --current '' prod feature-x build-17)
if [[ $completion_path_marker == *__ZR_COMPLETE_FILES__* && $completion_path_marker == *debug* && $completion_path_marker == *region=* ]]; then
  record-pass completion-path-marker
else
  record-fail completion-path-marker "got: $completion_path_marker"
fi

completion_script=$TMP/completion.zsh
completion_driver=$TMP/completion-driver.zsh
zsh $ZR --completion >$completion_script
completion_source_body=$(<$completion_script)
if [[ $completion_source_body == *"compdef _zr zr"* && $completion_source_body != *"#compdef zr"* && $completion_source_body != *"typeset -g _zr_runner"* ]]; then
  record-pass completion-source-registers-zr
else
  record-fail completion-source-registers-zr "got: $completion_source_body"
fi

completion_autoload_script=$TMP/completion-autoload.zsh
zsh $ZR --completion-autoload >$completion_autoload_script
completion_autoload_body=$(<$completion_autoload_script)
if [[ $completion_autoload_body == *"#compdef zr"* && $completion_autoload_body == *"_zr()"* && $completion_autoload_body != *"compdef _zr zr"* && $completion_autoload_body != *"typeset -g _zr_runner"* ]]; then
  record-pass completion-autoload-no-register
else
  record-fail completion-autoload-no-register "got: $completion_autoload_body"
fi
cat >$completion_driver <<'DRIVER'
compdef() { :; }
compadd() {
  local arrname=${argv[-1]}
  print -rl -- "${(@P)arrname}"
}
_files() {
  print -r -- "_files_called"
}
source "$1"
if (( $# > 2 )); then
  words=(zr "$2" "${@:3}")
  CURRENT=${#words}
else
  words=(zr "$2" "money\\\$tag" "")
  CURRENT=4
fi
_zr
DRIVER
completion_dollar=$(zsh $completion_driver $completion_script $TMP/dollar-tag.zsh)
if [[ $completion_dollar == plain ]]; then
  record-pass completion-dollar-selected
else
  record-fail completion-dollar-selected "got: $completion_dollar"
fi

completion_path_driver=$(zsh $completion_driver $completion_script $TMP/args.zsh prod feature-x build-17 '')
if [[ $completion_path_driver == *_files_called* ]]; then
  record-pass completion-path-files
else
  record-fail completion-path-files "got: $completion_path_driver"
fi

cat >$TMP/embed-source.zsh <<'CONFIG'
ZR_CONFIGURE=setup
ZR_MAIN=run

setup() {
  zr::tag-group env prod dev
  zr::prop region
}

run() {
  print -r -- "embedded tags=${ZR_TAGS[*]}"
  print -r -- "embedded region=${ZR_PROPS[region]-}"
  print -r -- "embedded argv=$*"
}
CONFIG

embedded_script=$TMP/my-script
zsh $ZR --embed $TMP/embed-source.zsh >$embedded_script
chmod +x $embedded_script

if grep -Fq -- "# zr:embedded:begin version=" $embedded_script && grep -Fq -- "# zr:embedded:end" $embedded_script; then
  record-pass embed-markers
else
  record-fail embed-markers "embedded script was: $(<$embedded_script)"
fi

stdout=$TMP/embedded-run.out
stderr=$TMP/embedded-run.err
if zsh $embedded_script prod region=us-west -- alpha beta >$stdout 2>$stderr; then
  record-pass embedded-run
else
  record-fail embedded-run "$(<$stderr)"
fi
if grep -Fq -- "embedded tags=my-script prod" $stdout && grep -Fq -- "embedded region=us-west" $stdout && grep -Fq -- "embedded argv=alpha beta" $stdout; then
  record-pass embedded-output
else
  record-fail embedded-output "stdout was: $(<$stdout)"
fi

embedded_completion=$(zsh $embedded_script --_zr-complete --_zr-lexical my-script --current r prod)
if [[ $embedded_completion == region= ]]; then
  record-pass embedded-completion
else
  record-fail embedded-completion "got: $embedded_completion"
fi

embedded_source_completion=$(zsh $embedded_script --completion)
if [[ $embedded_source_completion == *"_my-script()"* && $embedded_source_completion == *"compdef _my-script my-script"* && $embedded_source_completion == *"compdef _my-script -p '*/my-script(|.*)'"* && $embedded_source_completion != *"#compdef my-script"* ]]; then
  record-pass embedded-completion-source-form
else
  record-fail embedded-completion-source-form "got: $embedded_source_completion"
fi
print -r -- "$embedded_source_completion" >$TMP/embedded-completion-source.zsh
if zsh -n $TMP/embedded-completion-source.zsh; then
  record-pass embedded-completion-source-syntax
else
  record-fail embedded-completion-source-syntax
fi

embedded_autoload_completion=$(zsh $embedded_script --completion-autoload)
if [[ $embedded_autoload_completion == *"#compdef my-script"* && $embedded_autoload_completion == *"_my-script()"* && $embedded_autoload_completion == *"compdef _my-script -p '*/my-script(|.*)'"* && $embedded_autoload_completion == *"_my-script \"\$@\""* && $embedded_autoload_completion != *"compdef _my-script my-script"* ]]; then
  record-pass embedded-completion-autoload-form
else
  record-fail embedded-completion-autoload-form "got: $embedded_autoload_completion"
fi
print -r -- "$embedded_autoload_completion" >$TMP/embedded-completion-autoload.zsh
if zsh -n $TMP/embedded-completion-autoload.zsh; then
  record-pass embedded-completion-autoload-syntax
else
  record-fail embedded-completion-autoload-syntax
fi

embedded_script_updated=$TMP/my-script-updated
zsh $ZR --embed $embedded_script >$embedded_script_updated
embedded_begin_count=$(grep -Ec -- "^# zr:embedded:begin" $embedded_script_updated)
if [[ $embedded_begin_count == 1 ]]; then
  record-pass embed-replaces-existing
else
  record-fail embed-replaces-existing "begin marker count: $embedded_begin_count"
fi

DIRECT_BIN=$TMP/direct-bin
mkdir -p $DIRECT_BIN || exit 1
chmod +x $TMP/basic.zsh
ln -s $TMP/basic.zsh $DIRECT_BIN/basic.prod

stdout=$TMP/direct-command-path.out
stderr=$TMP/direct-command-path.err
if env PATH="$DIRECT_BIN:$PATH" zsh $ZR basic.prod >$stdout 2>$stderr; then
  record-pass direct-command-path
else
  record-fail direct-command-path "$(<$stderr)"
fi

completion_direct=$(env PATH="$DIRECT_BIN:$PATH" zsh $ZR --_zr-complete basic.prod --current d)
if [[ $completion_direct == debug ]]; then
  record-pass completion-direct-command-path
else
  record-fail completion-direct-command-path "got: $completion_direct"
fi

direct_source_completion=$(env PATH="$DIRECT_BIN:$PATH" zsh $ZR basic.prod --completion)
if [[ $direct_source_completion == *"_basic.prod()"* && $direct_source_completion == *"compdef _basic.prod basic.prod"* && $direct_source_completion == *"compdef _basic.prod -p '*/basic.prod(|.*)'"* && $direct_source_completion == *"--_zr-complete \"\$config\""* && $direct_source_completion != *"#compdef basic.prod"* ]]; then
  record-pass direct-completion-source-form
else
  record-fail direct-completion-source-form "got: $direct_source_completion"
fi
print -r -- "$direct_source_completion" >$TMP/direct-completion-source.zsh
if zsh -n $TMP/direct-completion-source.zsh; then
  record-pass direct-completion-source-syntax
else
  record-fail direct-completion-source-syntax
fi

direct_autoload_completion=$(env PATH="$DIRECT_BIN:$PATH" zsh $ZR basic.prod --completion-autoload)
if [[ $direct_autoload_completion == *"#compdef basic.prod"* && $direct_autoload_completion == *"_basic.prod()"* && $direct_autoload_completion == *"compdef _basic.prod -p '*/basic.prod(|.*)'"* && $direct_autoload_completion == *"_basic.prod \"\$@\""* && $direct_autoload_completion != *"compdef _basic.prod basic.prod"* ]]; then
  record-pass direct-completion-autoload-form
else
  record-fail direct-completion-autoload-form "got: $direct_autoload_completion"
fi
print -r -- "$direct_autoload_completion" >$TMP/direct-completion-autoload.zsh
if zsh -n $TMP/direct-completion-autoload.zsh; then
  record-pass direct-completion-autoload-syntax
else
  record-fail direct-completion-autoload-syntax
fi

print -r -- ""
print -r -- "$pass passed, $fail failed"
(( fail == 0 ))
