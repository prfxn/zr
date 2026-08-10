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
  print -r -- "unknown=${ZR_UNKNOWN_TAGS[*]}"
  print -r -- "branch=${ZR_PROPS[branch]-}"
  print -r -- "customer=${ZR_PROPS[customer]-}"
}
CONFIG

cat >$TMP/unknown.zsh <<'CONFIG'
configure() {
  zr::allow-unknown-tags
  zr::tag-group env prod dev
  zr::tag debug
}

main() {
  print -r -- "tags=${ZR_TAGS[*]}"
  print -r -- "cli=${ZR_CLI_TAGS[*]}"
  print -r -- "known=${ZR_KNOWN_TAGS[*]}"
  print -r -- "unknown=${ZR_UNKNOWN_TAGS[*]}"
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

cat >$TMP/configure-unknown.zsh <<'CONFIG'
configure() {
  zr::allow-unknown-tags
  zr::tag prod
  if (( ${#ZR_UNKNOWN_TAGS[@]} )); then
    zr::prop seen_unknown
  fi
}

main() {
  print -r -- "unknown=${ZR_UNKNOWN_TAGS[*]}"
  print -r -- "seen_unknown=${ZR_PROPS[seen_unknown]-}"
}
CONFIG

assert-failure unknown-tag-default "tag not accepted by config: feature-x" $TMP/basic.zsh prod feature-x

assert-success unknown-tag-allowed $TMP/unknown.zsh prod feature-x feature-x debug
assert-output-contains unknown-tag-allowed "tags=unknown zsh prod feature-x debug"
assert-output-contains unknown-tag-allowed "cli=prod feature-x feature-x debug"
assert-output-contains unknown-tag-allowed "known=unknown zsh prod debug"
assert-output-contains unknown-tag-allowed "unknown=feature-x feature-x"

assert-success configure-sees-unknown $TMP/configure-unknown.zsh prod feature-x seen_unknown=yes
assert-output-contains configure-sees-unknown "unknown=feature-x"
assert-output-contains configure-sees-unknown "seen_unknown=yes"

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

completion_pattern_value=$(zsh $ZR --_zr-complete $TMP/basic.zsh --current branch= prod)
if [[ -z $completion_pattern_value ]]; then
  record-pass completion-pattern-value-empty
else
  record-fail completion-pattern-value-empty "got: $completion_pattern_value"
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

print -r -- ""
print -r -- "$pass passed, $fail failed"
(( fail == 0 ))
