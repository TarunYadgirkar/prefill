#!/bin/zsh
# usage: mac-showcase.sh [light|dark ...]
# Builds a test copy of the Mac app and runs it on the Alex Rivera card with its own store,
# socket folder and archive, so the installed Prefill and the person's card stay untouched.
# It opens the menu and settings as ordinary windows, draws each to
# assets/generated/mac-showcase-<menu|settings>-<variant>.png and quits. No Screen Recording
# permission is needed: the windows draw themselves.
source ${0:A:h}/lib.sh

SHOW_DERIVED=$ROOT/build/DerivedData-MacShowcase
APP=$SHOW_DERIVED/Build/Products/Personal/Prefill.app
OUT=$ROOT/assets/generated
variants=("$@")
(( ${#variants} )) || variants=(light dark)

step "Building a test copy of the Mac app"
xcodegen generate --spec $ROOT/project.yml --project $ROOT --quiet
xcodebuild -project $PROJECT -scheme PrefillMac -configuration Personal -destination 'platform=macOS' \
  -derivedDataPath $SHOW_DERIVED 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) PREFILL_TEST_BROWSERS' \
  CODE_SIGNING_ALLOWED=NO build >$LOGS/build-mac-showcase.log 2>&1 || fail_with_log $LOGS/build-mac-showcase.log

for variant in $variants; do
  step "Showcase: $variant"
  work=$(mktemp -d)
  mkdir -p $work/store $work/dir $work/snap
  PREFILL_E2E_SHOWCASE=1 PREFILL_E2E_APPEARANCE=$variant PREFILL_E2E_SNAP=$work/snap \
    PREFILL_E2E_CARD=$ROOT/testbed/mac-e2e/showcase-card.json PREFILL_E2E_STORE=$work/store \
    PREFILL_E2E_DIR=$work/dir $APP/Contents/MacOS/Prefill >$LOGS/mac-showcase.log 2>&1 &
  pid=$!
  sleep 6
  kill $pid 2>/dev/null || true
  for name in menu settings; do
    # The frame view includes the title bar of the stand-in window; the real menu has none.
    ffmpeg -y -loglevel error -i $work/snap/prefill-$name.png -vf "crop=iw:ih-64:0:64" \
      $OUT/mac-showcase-$name-$variant.png
  done
  rm -rf $work
done
print "saved to $OUT/mac-showcase-*.png"
