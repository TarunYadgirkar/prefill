#!/bin/zsh
# usage: scripts/run.sh <logname> <only-testing ...>
cd "$(dirname $0)/.."
name=$1; shift
args=()
for t in "$@"; do args+=(-only-testing:TextInsertUITests/$t); done
xcodegen generate -q >/dev/null 2>&1
log=logs/test-$name.log
xcodebuild test -project TextInsertSpike.xcodeproj -scheme TextInsertSpike -destination 'platform=iOS Simulator,id=CF361191-F960-4212-9B76-7C41256A11C9' -derivedDataPath build $args > $log 2>&1 &
pid=$!
# xcodebuild sometimes hangs after the suite finishes; stop it 20s after the summary line
while kill -0 $pid 2>/dev/null; do
  if grep -q "Test Suite 'Selected tests' \(passed\|failed\)\|BUILD FAILED\|TEST FAILED\|TEST SUCCEEDED" $log; then
    sleep 20; kill $pid 2>/dev/null; break
  fi
  sleep 3
done
grep -E "error:|failed -|passed \(|failed \(" $log | grep -v "^20" | head -20
