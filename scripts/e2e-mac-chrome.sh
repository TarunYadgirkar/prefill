#!/bin/zsh
# Checks Prefill in Chrome end to end on this Mac without touching the person's card,
# browsers or screen: builds a test copy of the Mac app that also answers Playwright's
# Chrome for Testing and uses the Alex Rivera card in testbed/mac-e2e, runs it with its own
# store, loads the extension into a headless Chrome for Testing profile whose native
# messaging host is that copy's, focuses an email field and submits a new email.
# Screenshots: assets/generated/mac-chrome-dropdown.png, and with PREFILL_E2E_AIRTABLE=1 also
# assets/generated/airtable-chrome.png from a real Airtable form (filled, never submitted).
source ${0:A:h}/lib.sh

PORT=8847
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
  rm -rf $WORK
  rm -rf ${E2E_DERIVED:?}
  $was_running && open -b $INSTALLED_ID || true
}
trap cleanup EXIT
osascript -e "quit app id \"$INSTALLED_ID\"" 2>/dev/null || true
sleep 1

step "Starting the test app with the Alex Rivera card"
mkdir -p $WORK/store $WORK/profile/NativeMessagingHosts
PREFILL_E2E_CARD=$ROOT/testbed/mac-e2e/card.json PREFILL_E2E_STORE=$WORK/store $APP/Contents/MacOS/Prefill &
app_pid=$!
sleep 2

cat >$WORK/profile/NativeMessagingHosts/com.tarunyadgirkar.prefill.json <<EOF
{
  "name": "com.tarunyadgirkar.prefill",
  "description": "Prefill",
  "path": "$APP/Contents/MacOS/prefill-host",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://hnmpfjdamkhpfibdjpmdopohkcpfbfej/"]
}
EOF

step "Serving testbed/mac-e2e on localhost:$PORT"
python3 -m http.server $PORT --bind 127.0.0.1 --directory $ROOT/testbed/mac-e2e >/dev/null 2>&1 &
server_pid=$!
sleep 1

step "Driving Chrome for Testing"
mkdir -p $ROOT/assets/generated
airtable=()
[[ ${PREFILL_E2E_AIRTABLE:-0} == 1 ]] && airtable=($ROOT/assets/generated/airtable-chrome.png)
node $ROOT/web/src/e2e/macChrome.ts $ROOT/web/dist-chrome $WORK/profile "http://localhost:$PORT/" \
  $ROOT/assets/generated/mac-chrome-dropdown.png $airtable

step "Checking that the typed email reached the card"
grep -q "alex.new@example.net" $WORK/store/* && print "ok  the submitted email was captured" || {
  print "the submitted email never reached the app"; exit 1
}
