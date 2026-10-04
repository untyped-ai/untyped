#!/bin/sh
# Every check must do exactly what its name says.
#   ./check.sh protocol  one-step configs: correct.cfg holds, each bug_*.cfg breaks the
#                        invariant it names, vacuity.cfg shows an effect is reachable
#   ./check.sh big       the same on three steps
#   ./check.sh trace     runs A-D in trace/ validated against the unmodified spec
#   ./check.sh all       everything above
#   ./check.sh run F     verdict for one recorded run F (accepted / violated / rejected)
set -u
cd "$(dirname "$0")" || exit 2
CP=tools/tla2tools.jar:tools/CommunityModules-deps.jar
tlc() { java -XX:+UseSerialGC -DTLA-Library="$PWD" -cp "$CP" tlc2.TLC -workers 1 -metadir "${TMPDIR:-/tmp}/harness-states" -nowarning "$@" 2>&1; }

rc=0
expect() { # $1 label, $2 expected: clean | <Invariant> | rejected, then TLC args
  label=$1; want=$2; shift 2
  out=$(tlc "$@"); code=$?
  case $want in
    clean)    [ $code -eq 0 ]  && echo "ok    $label: no violation ($(echo "$out" | sed -n 's/.* \([0-9][0-9,]*\) distinct states found.*/\1/p' | head -1) distinct states)" && return 0 ;;
    rejected) [ $code -eq 10 ] && echo "ok    $label: rejected, the run is outside the protocol" && return 0 ;;
    *)        [ $code -eq 12 ] && echo "$out" | grep -q "Invariant $want is violated" \
                && echo "ok    $label: $want violated ($(echo "$out" | grep -c '^State ') states)" && return 0 ;;
  esac
  echo "FAIL  $label (tlc exit $code)"; echo "$out" | grep -E "Error|violated" | head -3; rc=1
}

protocol() {
  expect correct                 clean                -config correct.cfg -deadlock harness.tla
  expect bug_key_per_attempt     AtMostOnce           -config bug_key_per_attempt.cfg -deadlock harness.tla
  expect bug_no_key              AtMostOnce           -config bug_no_key.cfg -deadlock harness.tla
  expect bug_approval_proceeds   ApprovalBeforeEffect -config bug_approval_proceeds.cfg -deadlock harness.tla
  expect bug_budget_per_attempt  BudgetHeld           -config bug_budget_per_attempt.cfg -deadlock harness.tla
  expect vacuity                 NoEffect             -config vacuity.cfg -deadlock harness.tla
}
big() {
  expect big_correct             clean                -config big/big_correct.cfg -deadlock harness.tla
  expect big_bug_key             AtMostOnce           -config big/big_bug_key.cfg -deadlock harness.tla
  expect big_bug_budget          BudgetHeld           -config big/big_bug_budget.cfg -deadlock harness.tla
}
trace() {
  for r in A:clean B:AtMostOnce C:rejected D:clean; do
    run=${r%%:*}; want=${r#*:}
    TRACE=trace/run$run.jsonl expect "run $run" "$want" -config trace/harnessTrace.cfg trace/harnessTrace.tla
  done
}

one() { # verdict for a single run file, with the states TLC matched
  [ -f "${1:-}" ] || { echo "usage: $0 run path/to/run.jsonl"; exit 2; }
  out=$(TRACE=$1 tlc -config trace/harnessTrace.cfg trace/harnessTrace.tla); code=$?
  echo "$out" | grep -E '^State [0-9]|^/\\ (effects|attempt|calls) =|^Error: (Invariant|Postcondition)|Trace rejected|^ *\[event'
  case $code in
    0)  echo "$1: accepted" ;;
    12) echo "$1: violated" ;;
    10) echo "$1: rejected (the run is outside the protocol)" ;;
    *)  echo "$1: tlc exit $code"; echo "$out" | tail -5 ;;
  esac
  exit 0
}

case ${1:-protocol} in
  protocol) protocol ;;
  big)      big ;;
  trace)    trace ;;
  all)      protocol; big; trace ;;
  run)      one "${2:-}" ;;
  *) echo "usage: $0 [protocol|big|trace|all|run FILE]"; exit 2 ;;
esac
exit $rc
