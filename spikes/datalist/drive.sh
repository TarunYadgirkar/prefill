#!/bin/bash
# usage: drive.sh STEP TEST [KEY=VALUE ...]   (KEY=VALUE become TEST_RUNNER_KEY env for the UI test)
set -u
D=/Users/tarunyadgirkar/TarunsCode/prefill/spikes/datalist
UDID=47A4C2A7-9518-49BF-92C1-D602AAE4E6D9
SHOTS=/Users/tarunyadgirkar/TarunsCode/prefill/assets/generated
STEP=$1; TEST=$2; shift 2
EV=$D/logs/events.jsonl
rm -f $D/www/signal/$STEP-*
ENVS=(TEST_RUNNER_STEP=$STEP)
TAP=""
for kv in "$@"; do ENVS+=("TEST_RUNNER_$kv"); [[ $kv == TAP=* ]] && TAP=${kv#TAP=}; done
start=$(wc -l < $EV)
env "${ENVS[@]}" xcodebuild test-without-building -project $D/DatalistSpike.xcodeproj -scheme DatalistSpike \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath $D/build \
  -only-testing:DatalistUITests/DriverTests/$TEST > $D/logs/xcb-$STEP.log 2>&1 &
XPID=$!
waitev() { for i in $(seq 1 150); do tail -n +$((start+1)) $EV | grep -q "\"step\": \"$STEP\".*\"event\": \"$1\"\|\"event\": \"$1\".*\"step\": \"$STEP\"" && return 0; kill -0 $XPID 2>/dev/null || return 1; sleep 1; done; return 1; }
first=focused; [[ $TEST == testEnableExtension ]] && first=extension-page; [[ $TEST == testTapLabels ]] && first=after-labels; [[ $TEST == testDump ]] && first=dump
if waitev $first; then
  sleep 1
  [[ $TEST != testDump ]] && xcrun simctl io $UDID screenshot $SHOTS/spike-datalist-$STEP.png >/dev/null 2>&1 && echo "shot $STEP"
  touch $D/www/signal/$STEP-1
  if [[ -n $TAP ]] && waitev after-tap; then
    sleep 1; xcrun simctl io $UDID screenshot $SHOTS/spike-datalist-$STEP-tapped.png >/dev/null 2>&1 && echo "shot $STEP-tapped"
    touch $D/www/signal/$STEP-2
  fi
else
  echo "no $first event for $STEP"
fi
wait $XPID; echo "xcodebuild exit $?"
grep -E "error:|failed|passed" $D/logs/xcb-$STEP.log | grep -v "^$" | tail -5
