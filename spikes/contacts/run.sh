#!/bin/zsh
# usage: run.sh probe <action> [id] | drive '<script>' <logname> | shot <name> | log
U=A53AB330-51D0-4F6A-88C2-83EDF2CA571D
B=com.tarunyadgirkar.prefill.spike.contacts.probe
HERE=${0:A:h}
[[ $1 == bg ]] || case $1 in
  install) xcrun simctl install $U $HERE/build/Build/Products/Debug-iphonesimulator/Probe.app ;;
  probe)
    xcrun simctl terminate $U $B 2>/dev/null
    extra=(); [[ -n $3 ]] && extra=(${=3})
    xcrun simctl launch --terminate-running-process $U $B -action $2 $extra >/dev/null
    sleep ${4:-3}
    cat "$(xcrun simctl get_app_container $U $B data)/Documents/probe.log" > $HERE/logs/probe.log
    tail -n ${5:-6} $HERE/logs/probe.log ;;
  drive)
    TEST_RUNNER_PROBE_SCRIPT="$2" xcodebuild test-without-building -project $HERE/ContactsProbe.xcodeproj -scheme Probe \
      -destination "platform=iOS Simulator,id=$U" -derivedDataPath $HERE/build > $HERE/logs/drive-$3.log 2>&1
    echo "exit=$?"; grep -E "\[driver\]|Test Case.*(passed|failed|skipped)|error" $HERE/logs/drive-$3.log | grep -v "tree$" | cut -c1-600 | head -${4:-40} ;;
  shot) xcrun simctl io $U screenshot $HERE/../../assets/generated/spike-contacts-$2.png >/dev/null 2>&1 && echo saved spike-contacts-$2.png ;;
esac
# bg <script> <name> <marker> <shotname>: run driver in background, screenshot when marker step starts, then wait for exit
if [[ $1 == bg ]]; then
  L=$HERE/logs/drive-$3.log
  TEST_RUNNER_PROBE_SCRIPT="$2" xcodebuild test-without-building -project $HERE/ContactsProbe.xcodeproj -scheme Probe \
    -destination "platform=iOS Simulator,id=$U" -derivedDataPath $HERE/build > $L 2>&1 &
  P=$!
  for i in $(seq 1 150); do grep -q "step $4" $L && break; kill -0 $P 2>/dev/null || break; sleep 1; done
  [[ -n $5 ]] && xcrun simctl io $U screenshot $HERE/../../assets/generated/spike-contacts-$5.png >/dev/null 2>&1 && echo "saved spike-contacts-$5.png at $(date +%s)"
  wait $P; echo "exit=$?"
  grep -E "\[driver\] (step|stamp|missing|maybe)|Test Case.*(passed|failed|skipped)" $L | cut -c1-200
fi
