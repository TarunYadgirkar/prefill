#!/bin/zsh
# usage: run-test.sh Class/testName  -> logs/test-<testName>.log ; kills xcodebuild once the suite finishes (it lingers otherwise)
cd "$(dirname $0)/.."
name=${1##*/}
log=logs/test-$name${TEST_RUNNER_TAG:+-$TEST_RUNNER_TAG}.log
xcrun simctl terminate 7395317A-E54F-4CA6-8E64-6D8D22109587 com.apple.mobilesafari 2>/dev/null
xcodebuild test-without-building -project PrefillCapture.xcodeproj -scheme PrefillCapture \
  -destination 'platform=iOS Simulator,id=7395317A-E54F-4CA6-8E64-6D8D22109587' -derivedDataPath build \
  -only-testing:CaptureUITests/$1 > $log 2>&1 &
pid=$!
for i in {1..${2:-500}}; do
  grep -qE "Test Suite 'Selected tests' (passed|failed)" $log && break
  kill -0 $pid 2>/dev/null || break
  sleep 1
done
sleep 2; kill $pid 2>/dev/null
grep -E "error:|Test Case .*(passed|failed)|NOTE" $log | cut -c1-400
