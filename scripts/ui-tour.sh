#!/bin/zsh
# usage: ui-tour.sh [light|dark|large ...] [--motion]
# Seeds the simulator ($PREFILL_SIM) through SeedHostTests, then walks onboarding and every
# screen with AppTourTests, saving assets/generated/ui-<screen>-<variant>.png. "large" is
# the largest accessibility text size. --motion records the bar while values move
# (assets/generated/motion-*.mov) instead of taking screenshots.
source ${0:A:h}/lib.sh

OUT=$ROOT/assets/generated
PORT=${PREFILL_SNAP_PORT:-8834}
variants=()
motion=false
for arg in "$@"; do
  [[ $arg == --motion ]] && motion=true || variants+=$arg
done
(( ${#variants} )) || variants=(light dark large)

step "Building for testing"
pnpm --dir $ROOT/web build >/dev/null
xcodegen generate --spec $ROOT/project.yml --project $ROOT --quiet
for scheme in PrefillHostTests Prefill; do
  xcodebuild build-for-testing -project $PROJECT -scheme $scheme -configuration Personal \
    -destination "platform=iOS Simulator,id=$SIM_UDID" -derivedDataPath $DERIVED \
    >$LOGS/tour-build-$scheme.log 2>&1 || fail_with_log $LOGS/tour-build-$scheme.log
done

boot_sim
xcrun simctl privacy $SIM_UDID grant contacts $PERSONAL_BUNDLE_ID
python3 ${0:A:h}/snap-server.py $SIM_UDID $OUT $PORT &
server=$!
trap "kill $server 2>/dev/null; xcrun simctl ui $SIM_UDID appearance light; xcrun simctl ui $SIM_UDID content_size large" EXIT

seed() {
  export TEST_RUNNER_PREFILL_SEED=1
  run_xcodebuild_test $LOGS/tour-seed.log 'Test run with [0-9]+ tests? .*passed' \
    test-without-building -project $PROJECT -scheme PrefillHostTests -configuration Personal \
    -destination "platform=iOS Simulator,id=$SIM_UDID" -derivedDataPath $DERIVED \
    -only-testing:PrefillHostTests/SeedHostTests
  unset TEST_RUNNER_PREFILL_SEED
}

tour() {
  local test=$1 mode=$2 variant=$3
  export TEST_RUNNER_PREFILL_TOUR=$mode TEST_RUNNER_PREFILL_VARIANT=$variant TEST_RUNNER_PREFILL_SNAP_PORT=$PORT
  run_xcodebuild_test $LOGS/tour-$variant.log "Test Suite 'AppTourTests' passed" \
    test-without-building -project $PROJECT -scheme Prefill -configuration Personal \
    -destination "platform=iOS Simulator,id=$SIM_UDID" -derivedDataPath $DERIVED \
    -only-testing:PrefillUITests/AppTourTests/$test
  ! grep -q "Test skipped" $LOGS/tour-$variant.log || { print "skipped, log: $LOGS/tour-$variant.log"; return 1 }
}

for variant in $variants; do
  step "Tour: $variant"
  xcrun simctl ui $SIM_UDID appearance $([[ $variant == dark ]] && print dark || print light)
  xcrun simctl ui $SIM_UDID content_size $([[ $variant == large ]] && print accessibility-extra-extra-extra-large || print large)
  seed
  if $motion; then
    tour testTour tour $variant
    tour testBarMotion motion $variant
  else
    tour testTour tour $variant
  fi
done
