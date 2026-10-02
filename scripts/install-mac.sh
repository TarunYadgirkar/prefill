#!/bin/zsh
# Builds Prefill for this Mac (the menu bar app, its native messaging host and the Chrome
# extension), installs it in /Applications, opens it, and prints the folder to load in
# chrome://extensions and arc://extensions.
source ${0:A:h}/lib.sh

MAC_DERIVED=$ROOT/build/DerivedData-Mac
INSTALLED=${PREFILL_MAC_APP:-/Applications/Prefill.app}

step "Building extension scripts"
pnpm --dir $ROOT/web build

step "Generating Prefill.xcodeproj"
xcodegen generate --spec $ROOT/project.yml --project $ROOT --quiet

step "Building Prefill for this Mac"
xcodebuild -project $PROJECT -scheme PrefillMac -configuration Personal -destination 'platform=macOS' \
  -derivedDataPath $MAC_DERIVED build >$LOGS/build-mac.log 2>&1 || fail_with_log $LOGS/build-mac.log

step "Installing in $INSTALLED"
osascript -e 'quit app id "com.tarunyadgirkar.prefill.mac"' 2>/dev/null || true
sleep 1
rm -rf $INSTALLED
ditto $MAC_DERIVED/Build/Products/Personal/Prefill.app $INSTALLED
open $INSTALLED

print
print "Prefill is in the menu bar. Allow Contacts access from its menu the first time."
print "Add the extension in Chrome and in Arc: open chrome://extensions (arc://extensions in Arc),"
print "turn on Developer mode, choose Load unpacked, press Command-Shift-G and paste:"
print
print "  $INSTALLED/Contents/Resources/ChromeExtension"
