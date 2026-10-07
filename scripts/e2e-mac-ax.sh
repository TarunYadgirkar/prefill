#!/bin/zsh
# Checks Prefill's own panel in another app, through Accessibility: builds a test copy of
# the Mac app with the Alex Rivera card (testbed/mac-e2e) and its own store, runs it watching
# only Chrome for Testing, opens the test page there without the extension, focuses the
# email field from Playwright and lets the test copy pick the first row, then empties the
# form, focuses the phone field and lets it press Fill form. Then it opens the page again
# with the extension loaded and checks the extension's list shows and the panel stays away.
# The process needs Accessibility:
# run from a terminal that has it. Screenshot: assets/generated/mac-ax-panel.png.
# PREFILL_E2E_AIRTABLE=1 also fills (never submits) the real Airtable form.
source ${0:A:h}/lib.sh

PORT=8848
E2E_DERIVED=$ROOT/build/DerivedData-MacE2E
APP=$E2E_DERIVED/Build/Products/Personal/Prefill.app
WORK=$(mktemp -d)
INSTALLED_ID=com.tarunyadgirkar.prefill.mac

# The test copy's host shares the real one's identifier and also answers Chrome for
# Testing, so it never stays on disk after the run, even when the build fails.
trap 'rm -rf ${E2E_DERIVED:?}' EXIT

step "Building extension scripts and a test copy of the Mac app"
pnpm --dir $ROOT/web build
xcodegen generate --spec $ROOT/project.yml --project $ROOT --quiet
xcodebuild -project $PROJECT -scheme PrefillMac -configuration Personal -destination 'platform=macOS' \
  -derivedDataPath $E2E_DERIVED 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) PREFILL_TEST_BROWSERS' \
  build >$LOGS/build-mac-e2e.log 2>&1 || fail_with_log $LOGS/build-mac-e2e.log

was_running=false
pgrep -qf "/Applications/Prefill.app/Contents/MacOS/Prefill" && was_running=true
cleanup() {
  kill ${app_pid:-} ${server_pid:-} 2>/dev/null || true
  sleep 1
  rm -rf $WORK
  rm -rf ${E2E_DERIVED:?}
  $was_running && open -b $INSTALLED_ID || true
}
trap cleanup EXIT
osascript -e "quit app id \"$INSTALLED_ID\"" 2>/dev/null || true
sleep 1

step "Starting the test app with the Alex Rivera card"
mkdir -p $WORK/store $WORK/profile-extension/NativeMessagingHosts
cat >$WORK/profile-extension/NativeMessagingHosts/com.tarunyadgirkar.prefill.json <<EOF2
{
  "name": "com.tarunyadgirkar.prefill",
  "description": "Prefill",
  "path": "$APP/Contents/MacOS/prefill-host",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://hnmpfjdamkhpfibdjpmdopohkcpfbfej/"]
}
EOF2
PREFILL_E2E_CARD=$ROOT/testbed/mac-e2e/card.json PREFILL_E2E_STORE=$WORK/store \
  PREFILL_E2E_AX_APP=com.google.chrome.for.testing PREFILL_E2E_AX_NO_GESTURE=1 PREFILL_E2E_AX_AUTOPICK=2.5 \
  PREFILL_E2E_AX_FILL_FORM=1 \
  $APP/Contents/MacOS/Prefill 2>$LOGS/e2e-mac-ax-app.log &
app_pid=$!
sleep 2

step "Serving testbed/mac-e2e on localhost:$PORT"
python3 -m http.server $PORT --bind 127.0.0.1 --directory $ROOT/testbed/mac-e2e >/dev/null 2>&1 &
server_pid=$!
sleep 1

step "Driving Chrome for Testing"
mkdir -p $ROOT/assets/generated
airtable=()
[[ ${PREFILL_E2E_AIRTABLE:-0} == 1 ]] && airtable=(airtable)
node $ROOT/web/src/e2e/macAx.ts $ROOT/web/dist-chrome $WORK/profile "http://localhost:$PORT/" $ROOT/assets/generated/mac-ax-panel.png $airtable \
  || { grep prefill-e2e $LOGS/e2e-mac-ax-app.log; exit 1 }
grep prefill-e2e $LOGS/e2e-mac-ax-app.log
