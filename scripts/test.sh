#!/bin/zsh
# usage: test.sh [unit|e2e]
#   unit (default): PrefillKit on macOS and on the simulator, the app-hosted store and
#                   Contacts tests (grants the Personal app Contacts access on the
#                   simulator), web tests, lint, typecheck.
#   e2e: PrefillUITests on the simulator ($PREFILL_SIM, default Prefill Dev). Links the
#        Alex Rivera card through a host test, serves the test sites with
#        scripts/e2e-server.py, drives Settings and Safari, checks the recorded events
#        through another host test, then restores the card.
#        Screenshots land in assets/generated/e2e-ext-*.png. PREFILL_E2E_ONLY=<test class>
#        runs that class alone and skips the gift check.
source ${0:A:h}/lib.sh

E2E_PORT=8846

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

# usage: host_e2e_step <link|verify|restore>  Runs the gated E2ESetupHostTests inside Prefill.app.
# The pass pattern names the mode's own test, because a run where it was skipped passes too.
typeset -A E2E_STEP_TESTS=(link linkAlexCard verify verifyGiftCapture restore restoreAlexCard)
host_e2e_step() {
  export TEST_RUNNER_PREFILL_E2E=$1
  run_xcodebuild_test $LOGS/test-e2e-$1.log "✔ Test ${E2E_STEP_TESTS[$1]}\\(\\) passed" \
    test -project $PROJECT -scheme PrefillHostTests -configuration Personal \
    -destination "platform=iOS Simulator,id=$SIM_UDID" -derivedDataPath $DERIVED \
    -only-testing:PrefillHostTests/E2ESetupHostTests
  local result=$?
  unset TEST_RUNNER_PREFILL_E2E
  return $result
}

e2e() {
  step "Building extension scripts and project"
  pnpm --dir $ROOT/web build
  xcodegen generate --spec $ROOT/project.yml --project $ROOT --quiet
  boot_sim
  xcrun simctl privacy $SIM_UDID grant contacts $PERSONAL_BUNDLE_ID
  xcrun simctl terminate $SIM_UDID com.apple.mobilesafari 2>/dev/null || true

  step "Serving the test sites on localhost:$E2E_PORT and 127.0.0.1:$E2E_PORT"
  python3 $ROOT/scripts/e2e-server.py $E2E_PORT $SIM_UDID $ROOT/assets/generated &
  server=$!
  trap 'kill $server 2>/dev/null; shutdown_if_we_booted' EXIT

  step "Linking the Alex Rivera card in the shared store"
  host_e2e_step link

  step "PrefillUITests on $SIM_UDID"
  local failed=0 only=${PREFILL_E2E_ONLY:-}
  local selection=(${only:+-only-testing:PrefillUITests/$only})
  run_xcodebuild_test $LOGS/test-e2e.log "Test Suite '(All tests|Selected tests)' passed" \
    test -project $PROJECT -scheme Prefill -configuration Personal \
    -destination "platform=iOS Simulator,id=$SIM_UDID" -derivedDataPath $DERIVED $selection || failed=1

  if [[ -z $only ]]; then
    step "Checking that the gift capture reached the app"
    host_e2e_step verify || failed=1
  fi

  step "Restoring the card's emails and clearing the shared store"
  host_e2e_step restore
  return $failed
}

case ${1:-unit} in
  unit) unit ;;
  e2e) e2e ;;
  *) print "usage: test.sh [unit|e2e]"; exit 64 ;;
esac
