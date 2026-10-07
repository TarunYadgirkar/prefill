#!/bin/zsh
# Builds and installs the two Phase 11 device spikes (text insert, keyboard) on a phone.
# usage: zsh spikes/install-device-spikes.sh <device-udid>
set -e
device=${1:?device udid}
here=${0:A:h}
for spike in textinsert:TextInsertSpike keyboard:KeyboardSpike; do
  dir=$here/${spike%%:*}; name=${spike##*:}
  (cd $dir && xcodegen generate --spec project.yml --quiet)
  xcodebuild -project $dir/$name.xcodeproj -scheme $name -configuration Debug -destination 'generic/platform=iOS' \
    -derivedDataPath $dir/build/device -allowProvisioningUpdates build >$dir/build/device-build.log 2>&1 \
    || { grep -E "error:" $dir/build/device-build.log | head -5; exit 1 }
  xcrun devicectl device install app --device $device $dir/build/device/Build/Products/Debug-iphoneos/$name.app
done
