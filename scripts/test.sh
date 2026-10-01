#!/bin/zsh
# usage: test.sh [unit|e2e]
#   unit (default): PrefillKit on macOS and on the simulator, the app-hosted store and
#                   Contacts tests (grants the Personal app Contacts access on the
#                   simulator), web tests, lint, typecheck.
#   e2e: PrefillUITests on the simulator ($PREFILL_SIM, default Prefill Dev).
source ${0:A:h}/lib.sh

was_booted=false
sim_is_booted && was_booted=true
shutdown_if_we_booted() {
  $was_booted || xcrun simctl shutdown $SIM_UDID 2>/dev/null || true
}
trap shutdown_if_we_booted EXIT

unit() {
  step "PrefillKit on macOS"
  local log=$LOGS/test-prefillkit-macos.log
  swift test --package-path $ROOT/Packages/PrefillKit >$log 2>&1 || fail_with_log $log
  grep -E "Test run with" $log

  step "PrefillKit on the iOS Simulator"
  (cd $ROOT/Packages/PrefillKit && run_xcodebuild_test $LOGS/test-prefillkit-ios.log 'Test run with [0-9]+ tests? .*passed' \
    test -scheme PrefillKit -destination "platform=iOS Simulator,id=$SIM_UDID" -derivedDataPath $ROOT/build/DerivedData-PrefillKit)

  step "App-hosted store and Contacts tests on the iOS Simulator"
  xcodegen generate --spec $ROOT/project.yml --project $ROOT --quiet
  boot_sim
  xcrun simctl privacy $SIM_UDID grant contacts $PERSONAL_BUNDLE_ID
  run_xcodebuild_test $LOGS/test-host.log 'Test run with [0-9]+ tests? .*passed' \
    test -project $PROJECT -scheme PrefillHostTests -configuration Personal \
    -destination "platform=iOS Simulator,id=$SIM_UDID" -derivedDataPath $DERIVED

  step "Web tests, typecheck, lint"
  pnpm --dir $ROOT/web test
  pnpm --dir $ROOT/web typecheck
  pnpm --dir $ROOT/web lint

  step "SwiftLint"
  (cd $ROOT && swiftlint lint --strict --quiet)
}

e2e() {
  step "Building extension scripts and project"
  pnpm --dir $ROOT/web build
  xcodegen generate --spec $ROOT/project.yml --project $ROOT --quiet
  xcrun simctl terminate $SIM_UDID com.apple.mobilesafari 2>/dev/null || true

  step "PrefillUITests on $SIM_UDID"
  run_xcodebuild_test $LOGS/test-e2e.log "Test Suite 'All tests' passed" \
    test -project $PROJECT -scheme Prefill -configuration Personal \
    -destination "platform=iOS Simulator,id=$SIM_UDID" -derivedDataPath $DERIVED
}

case ${1:-unit} in
  unit) unit ;;
  e2e) e2e ;;
  *) print "usage: test.sh [unit|e2e]"; exit 64 ;;
esac
