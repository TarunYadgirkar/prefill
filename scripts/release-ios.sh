#!/bin/zsh
# Archives the iPhone app (AppStore configuration) and, with --upload, sends it to App Store
# Connect for TestFlight using the Apple ID signed in to Xcode. Without --upload it exports the
# .ipa to build/release/ios/export so it can be checked first.
# The App Store Connect app record for com.tarunyadgirkar.prefill must exist before an upload.
#
# usage: release-ios.sh [--upload]
#   VERSION  marketing version (default: MARKETING_VERSION in project.yml)
#   BUILD    build number (default: date +%Y%m%d%H%M)
source ${0:A:h}/lib.sh

REL=$ROOT/build/release/ios
ARCHIVE=$REL/Prefill.xcarchive
VERSION=${VERSION:-$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' $ROOT/project.yml | head -1)}
BUILD=${BUILD:-$(date +%Y%m%d%H%M)}
UPLOAD=0
[[ ${1:-} == --upload ]] && UPLOAD=1

mkdir -p $REL

step "Building extension scripts"
pnpm --dir $ROOT/web build

step "Generating Prefill.xcodeproj"
xcodegen generate --spec $ROOT/project.yml --project $ROOT --quiet

step "Archiving Prefill $VERSION ($BUILD)"
rm -rf $ARCHIVE
xcodebuild -project $PROJECT -scheme Prefill -configuration AppStore -destination 'generic/platform=iOS' \
  -derivedDataPath $REL/DerivedData -archivePath $ARCHIVE -allowProvisioningUpdates \
  MARKETING_VERSION=$VERSION CURRENT_PROJECT_VERSION=$BUILD \
  archive >$LOGS/release-ios-archive.log 2>&1 || fail_with_log $LOGS/release-ios-archive.log

OPTIONS=$ROOT/Config/ExportiOS.plist
if (( ! UPLOAD )); then
  OPTIONS=$REL/ExportiOSLocal.plist
  cp $ROOT/Config/ExportiOS.plist $OPTIONS
  plutil -replace destination -string export $OPTIONS
fi

step $( (( UPLOAD )) && print "Uploading to App Store Connect" || print "Exporting the .ipa")
rm -rf $REL/export
xcodebuild -exportArchive -archivePath $ARCHIVE -exportOptionsPlist $OPTIONS -exportPath $REL/export \
  -allowProvisioningUpdates >$LOGS/release-ios-export.log 2>&1 || fail_with_log $LOGS/release-ios-export.log

if (( UPLOAD )); then
  print "Uploaded $VERSION ($BUILD). It shows in TestFlight once App Store Connect finishes processing."
else
  print "Exported $REL/export. Run again with --upload to send it to TestFlight."
fi
