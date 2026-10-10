#!/bin/zsh
# usage: sync-applications.sh [device-id]
# Copies the iPhone app's list of sent job applications to this Mac over USB, where the Prefill
# menu bar app merges it into its own on the next refresh (Imports/, by id, so a repeat adds
# nothing). Works for the Personal build because it's development-signed. Nothing goes over
# the network. auto-reinstall.sh runs it every day before checking for a reinstall.
source ${0:A:h}/lib.sh

device=${1:-${PREFILL_DEVICE:-00008150-000A3C241108401C}}
imports="$HOME/Library/Application Support/Prefill/Imports"
mkdir -p $imports
tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT

xcrun devicectl device copy from --device $device \
  --domain-type appDataContainer --domain-identifier $PERSONAL_BUNDLE_ID \
  --source "Library/Application Support/Prefill/applications.json" \
  --destination $tmp/applications.json >$tmp/copy.log 2>&1 || {
  cat $tmp/copy.log >&2
  print "couldn't copy the applications from $device (is it connected and unlocked?)" >&2
  exit 1
}
mv $tmp/applications.json "$imports/iphone-$(date +%Y%m%d%H%M%S).json"
print "copied the iPhone's applications; the Mac app merges them on its next refresh"
