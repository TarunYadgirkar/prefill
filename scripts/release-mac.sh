#!/bin/zsh
# Builds a Developer ID signed, notarized and stapled Prefill.app and puts it in a DMG at
# build/release/Prefill-<version>.dmg, plus appcast.xml when Sparkle's generate_appcast is
# around. Publishes nothing: it prints the gh release command to run by hand.
#
# Notarization uses the Apple ID signed in to Xcode (Settings › Accounts), no app-specific
# password. If that path fails, it falls back to notarytool with a keychain profile:
#   xcrun notarytool store-credentials prefill-notary --apple-id <id> --team-id 5AKJYZ7USP
# (asks for an app-specific password from account.apple.com). NOTARY_PROFILE picks another name.
#
# usage: release-mac.sh [--archive-only]
#   VERSION  marketing version (default: MARKETING_VERSION in project.yml)
#   BUILD    build number (default: date +%Y%m%d%H%M)
source ${0:A:h}/lib.sh

REL=$ROOT/build/release
ARCHIVE=$REL/Prefill.xcarchive
NOTARY_PROFILE=${NOTARY_PROFILE:-prefill-notary}
FEED_URL=https://github.com/TarunYadgirkar/prefill/releases/latest/download/appcast.xml
POLL_SECONDS=30
POLL_TRIES=60
VERSION=${VERSION:-$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' $ROOT/project.yml | head -1)}
BUILD=${BUILD:-$(date +%Y%m%d%H%M)}
ARCHIVE_ONLY=0
[[ ${1:-} == --archive-only ]] && ARCHIVE_ONLY=1

has_notary_profile() {
  xcrun notarytool history --keychain-profile $NOTARY_PROFILE >/dev/null 2>&1
}

notarize_with_xcode() {
  step "Uploading for notarization with Xcode's account"
  xcodebuild -exportArchive -archivePath $ARCHIVE -exportOptionsPlist $ROOT/Config/ExportMac.plist \
    -exportPath $REL/upload -allowProvisioningUpdates >$LOGS/release-mac-upload.log 2>&1 || return 1

  step "Waiting for notarization (up to $(( POLL_SECONDS * POLL_TRIES / 60 )) min)"
  local try
  for try in {1..$POLL_TRIES}; do
    rm -rf $REL/notarized
    if xcodebuild -exportNotarizedApp -archivePath $ARCHIVE -exportPath $REL/notarized \
        >$LOGS/release-mac-notarized.log 2>&1; then
      APP=$REL/notarized/Prefill.app
      return 0
    fi
    grep -qiE "rejected|invalid" $LOGS/release-mac-notarized.log && fail_with_log $LOGS/release-mac-notarized.log
    print "  not ready yet ($try/$POLL_TRIES)"
    sleep $POLL_SECONDS
  done
  print "notarization didn't finish in time, log: $LOGS/release-mac-notarized.log"
  exit 1
}

notarize_with_notarytool() {
  has_notary_profile || { print "no notarytool profile '$NOTARY_PROFILE'; see this script's header"; exit 1 }
  step "Exporting the Developer ID app"
  cp $ROOT/Config/ExportMac.plist $REL/ExportMacLocal.plist
  plutil -replace destination -string export $REL/ExportMacLocal.plist
  rm -rf $REL/export
  xcodebuild -exportArchive -archivePath $ARCHIVE -exportOptionsPlist $REL/ExportMacLocal.plist \
    -exportPath $REL/export -allowProvisioningUpdates >$LOGS/release-mac-export.log 2>&1 \
    || fail_with_log $LOGS/release-mac-export.log
  APP=$REL/export/Prefill.app

  step "Notarizing with notarytool"
  ditto -c -k --keepParent $APP $REL/Prefill.zip
  xcrun notarytool submit $REL/Prefill.zip --keychain-profile $NOTARY_PROFILE --wait \
    | tee $LOGS/release-mac-notarytool.log
  grep -q "status: Accepted" $LOGS/release-mac-notarytool.log || fail_with_log $LOGS/release-mac-notarytool.log
  xcrun stapler staple $APP
  rm $REL/Prefill.zip
}

mkdir -p $REL

step "Building extension scripts"
pnpm --dir $ROOT/web build

step "Generating Prefill.xcodeproj"
xcodegen generate --spec $ROOT/project.yml --project $ROOT --quiet

# AppStore, the optimized config; the Mac's bundle IDs are the same in both configs.
# PREFILL_FEED_URL turns on Sparkle's self-updates; builds without it never check.
step "Archiving Prefill $VERSION ($BUILD)"
rm -rf $ARCHIVE
xcodebuild -project $PROJECT -scheme PrefillMac -configuration AppStore -destination 'generic/platform=macOS' \
  -derivedDataPath $REL/DerivedData -archivePath $ARCHIVE -allowProvisioningUpdates \
  MARKETING_VERSION=$VERSION CURRENT_PROJECT_VERSION=$BUILD ONLY_ACTIVE_ARCH=NO \
  PREFILL_FEED_URL=$FEED_URL PREFILL_CLOUD_FLAGS=PREFILL_PRODUCTION_CLOUD \
  archive >$LOGS/release-mac-archive.log 2>&1 || fail_with_log $LOGS/release-mac-archive.log
print "archived $ARCHIVE"
(( ARCHIVE_ONLY )) && exit 0

# Developer ID builds must sync in CloudKit's Production database (export refuses
# Development), apart from Xcode builds, which use Development. PREFILL_PRODUCTION_CLOUD gives
# the release its own sync state, so it uploads this Mac's files there and never reads the
# other database's zone as deleted.
APP=
rm -f $LOGS/release-mac-upload.log
if ! xcodebuild -help 2>&1 | grep -q -- -exportNotarizedApp || ! notarize_with_xcode; then
  [[ -f $LOGS/release-mac-upload.log ]] && { print "Xcode's notarization path failed:"; grep -E "error:" $LOGS/release-mac-upload.log | cut -c1-300 || true }
  notarize_with_notarytool
fi

step "Checking the signature and Gatekeeper"
codesign --verify --deep --strict --verbose=2 $APP
spctl -a -vv -t exec $APP

step "Making the DMG"
DMG=$REL/Prefill-$VERSION.dmg
STAGE=$REL/dmg
rm -rf $STAGE $DMG
mkdir -p $STAGE
ditto $APP $STAGE/Prefill.app
ln -s /Applications $STAGE/Applications
hdiutil create -volname Prefill -srcfolder $STAGE -format UDZO -ov $DMG >/dev/null
rm -rf $STAGE
codesign -s "Developer ID Application" --timestamp $DMG

# The stapled app inside is what Gatekeeper checks after the copy; notarizing the DMG only
# spares the first-open check on the disk image itself, so it's skipped without a profile.
if has_notary_profile; then
  step "Notarizing the DMG"
  xcrun notarytool submit $DMG --keychain-profile $NOTARY_PROFILE --wait | tee $LOGS/release-mac-dmg.log
  grep -q "status: Accepted" $LOGS/release-mac-dmg.log || fail_with_log $LOGS/release-mac-dmg.log
  xcrun stapler staple $DMG
else
  print "DMG not notarized (no notarytool profile '$NOTARY_PROFILE'); the app inside is stapled."
fi

# The EdDSA signing key is in the login keychain under the account "prefill".
# SPARKLE_BIN is Sparkle's bin folder; otherwise the one the package resolve left in DerivedData.
FOUND=(${SPARKLE_BIN:+$SPARKLE_BIN/generate_appcast} $REL/DerivedData/SourcePackages/artifacts/*/Sparkle/bin/generate_appcast(N))
GENERATE_APPCAST=${FOUND[1]:-}
UPLOADS=($DMG)
if [[ -x $GENERATE_APPCAST ]]; then
  step "Writing appcast.xml"
  $GENERATE_APPCAST --account prefill --download-url-prefix https://github.com/TarunYadgirkar/prefill/releases/download/v$VERSION/ $REL
  UPLOADS+=($REL/appcast.xml)
else
  print "Sparkle's generate_appcast not found; no appcast.xml (set SPARKLE_BIN to its path)."
fi

print
print "Built $DMG. To publish:"
print
print "  gh release create v$VERSION ${UPLOADS[*]} --title 'Prefill $VERSION' --generate-notes"
