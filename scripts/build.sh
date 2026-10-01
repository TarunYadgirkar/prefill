#!/bin/zsh
# Builds the extension scripts, regenerates the project, and builds the app for the
# iOS Simulator in both configurations.
source ${0:A:h}/lib.sh

step "Building extension scripts"
pnpm --dir $ROOT/web build

step "Generating Prefill.xcodeproj"
xcodegen generate --spec $ROOT/project.yml --project $ROOT --quiet

for config in Personal AppStore; do
  step "Building $config for the iOS Simulator"
  xcodebuild -project $PROJECT -scheme Prefill -configuration $config \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath $DERIVED \
    build >$LOGS/build-$config.log 2>&1 || fail_with_log $LOGS/build-$config.log
  print "built $DERIVED/Build/Products/$config-iphonesimulator/Prefill.app"
done
