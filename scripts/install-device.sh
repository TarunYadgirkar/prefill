#!/bin/zsh
# usage: install-device.sh [device-id]
# Builds the Personal configuration for a connected iPhone and installs it with
# devicectl. Free personal team builds expire after 7 days, so rerun it weekly
# (install-auto-reinstall.sh sets that up).
# Device IDs come from: xcrun devicectl list devices
source ${0:A:h}/lib.sh

device=${1:-${PREFILL_DEVICE:-}}
if [[ -z $device ]]; then
  xcrun devicectl list devices
  print "\nusage: install-device.sh <device-id>  (or set PREFILL_DEVICE)" >&2
  exit 64
fi

step "Building extension scripts and project"
pnpm --dir $ROOT/web build
xcodegen generate --spec $ROOT/project.yml --project $ROOT --quiet

step "Building Personal for iOS"
xcodebuild -project $PROJECT -scheme Prefill -configuration Personal \
  -destination 'generic/platform=iOS' -derivedDataPath $DERIVED \
  -allowProvisioningUpdates build >$LOGS/build-device.log 2>&1 || fail_with_log $LOGS/build-device.log

app=$DERIVED/Build/Products/Personal-iphoneos/Prefill.app

step "Installing on $device"
xcrun devicectl device install app --device $device $app
xcrun devicectl device process launch --device $device $PERSONAL_BUNDLE_ID
