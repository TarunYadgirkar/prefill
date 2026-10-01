# Shared by the scripts in this folder. Source it, don't run it.
set -euo pipefail

ROOT=${0:A:h:h}
PROJECT=$ROOT/Prefill.xcodeproj
DERIVED=$ROOT/build/DerivedData
LOGS=$ROOT/build/logs
SIM_UDID=${PREFILL_SIM:-3334F739-DEB2-486E-931E-7FD189B112CC}
TEST_TIMEOUT=${PREFILL_TEST_TIMEOUT:-900}
SUMMARY_GRACE=20
PERSONAL_BUNDLE_ID=$(sed -n 's/^PREFILL_BUNDLE_ID = //p' $ROOT/Config/Personal.xcconfig)

mkdir -p $LOGS

if ! command -v pnpm >/dev/null; then
  source ${NVM_DIR:-$HOME/.nvm}/nvm.sh >/dev/null
fi

step() { print -P "%F{cyan}==>%f $*"; }

sim_is_booted() {
  xcrun simctl list devices | grep -q "($SIM_UDID) (Booted)"
}

boot_sim() {
  sim_is_booted || xcrun simctl boot $SIM_UDID
  xcrun simctl bootstatus $SIM_UDID -b >/dev/null
}

# usage: fail_with_log <log>  Prints the log's error lines (if any) and where the log is.
fail_with_log() {
  grep -E "✘|error:" $1 | cut -c1-300 || true
  print "failed, log: $1"
  exit 1
}

# xcodebuild test can hang after the suite has finished. Wait for a summary line,
# give xcodebuild a grace period to exit by itself, then kill it and judge the log.
# usage: run_xcodebuild_test <log> <pass-pattern> <xcodebuild args...>
run_xcodebuild_test() {
  local log=$1 pass=$2
  shift 2
  local fail='\*\* (TEST|BUILD) FAILED \*\*|Test run with .* failed|Test Suite .* failed|Testing failed:'
  local summary="\\*\\* TEST (SUCCEEDED|FAILED) \\*\\*|$pass|$fail"
  xcodebuild "$@" >$log 2>&1 &
  local pid=$! waited=0 grace=0
  while kill -0 $pid 2>/dev/null; do
    if grep -qE "$summary" $log; then
      (( grace++ >= SUMMARY_GRACE )) && { kill $pid 2>/dev/null; break }
    fi
    (( waited++ >= TEST_TIMEOUT )) && { kill $pid 2>/dev/null; print "timed out after ${TEST_TIMEOUT}s, log: $log"; return 1 }
    sleep 1
  done
  wait $pid 2>/dev/null || true
  grep -E "$pass|$fail|error:" $log | cut -c1-300 || true
  if grep -qE "$fail" $log || ! grep -qE "$pass" $log; then
    print "failed, log: $log"
    return 1
  fi
}
