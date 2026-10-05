#!/bin/zsh
# usage: install-auto-reinstall.sh [device-id]
#        install-auto-reinstall.sh --uninstall
# Sets up a launchd agent (com.tarunyadgirkar.prefill.reinstall) that runs auto-reinstall.sh
# every day at 12:15. That script does nothing unless the last install is 5.5+ days old or its
# profile expires within 36 hours, so in practice it reinstalls about every 6 days, and a day
# the phone was away or locked just moves the install to the next day.
#
# Why a daily check instead of StartInterval 518400 (6 days): launchd restarts an interval's
# clock whenever the agent loads, so a Mac that reboots or logs out more than weekly would never
# reach it. A calendar time is wall-clock: if the Mac slept through 12:15 it runs on wake, and if
# it was off it runs the next day.
#
# The job runs with your current PATH (for pnpm, xcodegen and Xcode tools), the repo's current
# location and PREFILL_DEVICE if given; rerun this after moving the repo or changing Node versions.
# Before relying on it, run `zsh scripts/auto-reinstall.sh --force` once in Terminal and click
# Always Allow on any keychain prompt, because codesign can't ask from launchd (details at the top
# of auto-reinstall.sh).
set -euo pipefail

SCRIPTS=${0:A:h}
ROOT=${SCRIPTS:h}
LABEL=com.tarunyadgirkar.prefill.reinstall
PLIST=$HOME/Library/LaunchAgents/$LABEL.plist
DOMAIN=gui/$(id -u)
HOUR=${PREFILL_REINSTALL_HOUR:-12}
MINUTE=${PREFILL_REINSTALL_MINUTE:-15}
LOG_DIR=$HOME/Library/Logs/Prefill

step() { print -P "%F{cyan}==>%f $*"; }

# usage: xml <text>  Escapes text for a plist <string>.
xml() {
  local s=${1//&/&amp;}
  s=${s//</&lt;}
  print -r -- ${s//>/&gt;}
}

unload() {
  launchctl bootout $DOMAIN/$LABEL 2>/dev/null || true
}

if [[ ${1:-} == --uninstall ]]; then
  step "Removing $LABEL"
  unload
  rm -f $PLIST
  print "Removed. Logs stay in $LOG_DIR and the last-install record in"
  print "~/Library/Application Support/Prefill/last-device-install."
  exit 0
fi
[[ ${1:-} == -* ]] && { print "usage: install-auto-reinstall.sh [device-id] | --uninstall" >&2; exit 64 }

device=${1:-${PREFILL_DEVICE:-}}

case $ROOT in
  $HOME/Desktop/*|$HOME/Documents/*|$HOME/Downloads/*|"$HOME/Library/Mobile Documents"/*)
    print -P "%F{yellow}warning:%f $ROOT is in a folder macOS guards (Desktop, Documents, Downloads"
    print "or iCloud Drive). Jobs launchd starts can't read it unless /bin/zsh has Full Disk Access;"
    print "move the repo (e.g. to ~/Developer) and rerun this, or grant that in System Settings."
    ;;
esac
for tool in pnpm xcodegen xcrun; do
  command -v $tool >/dev/null || print -P "%F{yellow}warning:%f $tool isn't on your PATH, so the job won't find it either"
done

step "Writing $PLIST"
mkdir -p ${PLIST:h} $LOG_DIR
{
  print '<?xml version="1.0" encoding="UTF-8"?>'
  print '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  print '<plist version="1.0">'
  print '<dict>'
  print "  <key>Label</key><string>$LABEL</string>"
  print '  <key>ProgramArguments</key>'
  print '  <array>'
  print '    <string>/bin/zsh</string>'
  print "    <string>$(xml $SCRIPTS/auto-reinstall.sh)</string>"
  print '  </array>'
  print '  <key>StartCalendarInterval</key>'
  print "  <dict><key>Hour</key><integer>$HOUR</integer><key>Minute</key><integer>$MINUTE</integer></dict>"
  print '  <key>RunAtLoad</key><false/>'
  print '  <key>EnvironmentVariables</key>'
  print '  <dict>'
  print "    <key>PATH</key><string>$(xml $PATH)</string>"
  [[ -n $device ]] && print "    <key>PREFILL_DEVICE</key><string>$(xml $device)</string>"
  print '  </dict>'
  print "  <key>StandardOutPath</key><string>$(xml $LOG_DIR/auto-reinstall.launchd.log)</string>"
  print "  <key>StandardErrorPath</key><string>$(xml $LOG_DIR/auto-reinstall.launchd.log)</string>"
  print '</dict>'
  print '</plist>'
} >$PLIST
plutil -lint -s $PLIST

step "Loading it into $DOMAIN"
unload
launchctl enable $DOMAIN/$LABEL
# bootstrap can fail with "Input/output error" while the old copy is still going away.
for try in 1 2 3 4 5; do
  launchctl bootstrap $DOMAIN $PLIST 2>/dev/null && break
  (( try == 5 )) && { launchctl bootstrap $DOMAIN $PLIST; exit 1 }
  sleep 1
done

print
print "Checks daily at $(printf '%02d:%02d' $HOUR $MINUTE) and reinstalls on ${device:-00008150-000A3C241108401C (iPhone 17 Pro)}"
print "when due. Log: $LOG_DIR/auto-reinstall.log"
print
print "Run it now (installs only if due; add --force by running the script directly):"
print "  launchctl kickstart $DOMAIN/$LABEL"
print "Remove it:"
print "  zsh scripts/install-auto-reinstall.sh --uninstall"
