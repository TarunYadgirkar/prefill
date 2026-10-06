#!/bin/zsh
# usage: auto-reinstall.sh [--force] [device-id]
# Reinstalls the Personal build on the iPhone before its free-team signature runs out, so the
# 7-day expiry never bites. scripts/install-auto-reinstall.sh runs it daily from launchd; it is
# also safe to run by hand. Each run:
#   1. skips unless the checkout has commits the phone doesn't, the last success was 5.5+ days
#      ago, or the installed profile expires within 36 hours (--force always installs),
#   2. moves aside cached provisioning profiles for Prefill that expire within 36 hours, so Xcode
#      signs with a fresh 7-day one instead of reusing one about to lapse (put back on failure),
#   3. checks the phone is reachable with `xcrun devicectl list devices`, runs install-device.sh,
#      and retries every 10 minutes for up to 3 hours while the phone is locked (CoreDevice
#      error 4016 or 10002) or out of reach,
#   4. posts a notification on success or final failure and records the install in
#      ~/Library/Application Support/Prefill/last-device-install.
# Log: ~/Library/Logs/Prefill/auto-reinstall.log (the previous one is kept as .log.1).
#
# The device defaults to the iPhone 17 Pro; pass another one or set PREFILL_DEVICE. Any form
# devicectl accepts works (UDID, CoreDevice identifier or name).
# Tunables (seconds): PREFILL_RETRY_INTERVAL (600), PREFILL_RETRY_WINDOW (10800),
# PREFILL_ATTEMPT_TIMEOUT (2700).
#
# Keychain caveat: codesign run from launchd can't show the "codesign wants to use your
# keychain" prompt, so the build hangs or fails with errSecInternalComponent. Allow it once:
#   - run `zsh scripts/auto-reinstall.sh --force` in Terminal and click Always Allow on each
#     keychain prompt, or
#   - Keychain Access → login keychain → My Certificates → expand "Apple Development: …" →
#     double-click its private key → Access Control → add /usr/bin/codesign (or allow all
#     applications) → Save Changes.
# The login keychain must also be unlocked, which it is while you're logged in unless it's set
# to lock on sleep. Notifications come from Script Editor; allow them in System Settings →
# Notifications if none appear.
set -euo pipefail
zmodload zsh/datetime

SCRIPTS=${0:A:h}
ROOT=${SCRIPTS:h}
DEVICE=${PREFILL_DEVICE:-00008150-000A3C241108401C}
BUNDLE_ID=$(sed -n 's/^PREFILL_BUNDLE_ID = //p' $ROOT/Config/Personal.xcconfig)
APP=$ROOT/build/DerivedData/Build/Products/Personal-iphoneos/Prefill.app
BUILD_LOG=$ROOT/build/logs/build-device.log

LOG_DIR=$HOME/Library/Logs/Prefill
LOG=$LOG_DIR/auto-reinstall.log
LOG_MAX_BYTES=524288
STATE_DIR="$HOME/Library/Application Support/Prefill"
STATE_FILE=$STATE_DIR/last-device-install
RETIRED_DIR=$STATE_DIR/retired-profiles
LOCK=$STATE_DIR/auto-reinstall.lock
PROFILE_DIRS=(
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  "$HOME/Library/MobileDevice/Provisioning Profiles"
)

MIN_AGE=475200          # 5.5 days: reinstall once the last success is this old
REFRESH_BEFORE=129600   # 36 hours: or once the installed profile expires this soon
RETRY_INTERVAL=${PREFILL_RETRY_INTERVAL:-600}
RETRY_WINDOW=${PREFILL_RETRY_WINDOW:-10800}
ATTEMPT_TIMEOUT=${PREFILL_ATTEMPT_TIMEOUT:-2700}

# launchd starts jobs with a bare PATH. The installer copies yours into the job; these cover
# the usual Homebrew locations in case it didn't.
path=(/opt/homebrew/bin /usr/local/bin $path)

force=false
while (( $# )); do
  case $1 in
    --force) force=true ;;
    -h|--help) sed -n '2,/^set -euo/p' $0 | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    -*) print "unknown option: $1" >&2; exit 64 ;;
    *) DEVICE=$1 ;;
  esac
  shift
done

mkdir -p $LOG_DIR $STATE_DIR
if [[ -f $LOG ]] && (( $(wc -c <$LOG) > LOG_MAX_BYTES )); then
  mv -f $LOG $LOG.1
fi
if [[ -t 1 ]]; then
  exec > >(tee -a $LOG) 2>&1
else
  exec >>$LOG 2>&1
fi

WORK=$(mktemp -d)
child=
retired=()

log() { print "$(strftime '%Y-%m-%d %H:%M:%S' $EPOCHSECONDS)  $*"; }
when() { strftime '%a %b %f, %H:%M' $1; }

# usage: notify <message>
notify() {
  osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' \
    -e 'end run' "Prefill" "$1" >/dev/null 2>&1 || true
}

# usage: state_value <key>  Prints a value from the last-install record, or nothing.
state_value() {
  [[ -f $STATE_FILE ]] && sed -n "s/^$1=//p" $STATE_FILE | tail -1 || true
}

# usage: profile_expiry <file>  Prints when a provisioning profile (or an app's embedded one)
# expires, in epoch seconds. Fails if it can't tell.
profile_expiry() {
  local date
  security cms -D -i $1 >$WORK/profile.plist 2>/dev/null || return 1
  date=$(plutil -extract ExpirationDate raw -o - $WORK/profile.plist 2>/dev/null) || return 1
  date -j -u -f '%Y-%m-%dT%H:%M:%SZ' $date +%s 2>/dev/null
}

# usage: profile_app_id <file>  Prints a profile's application-identifier (TEAM.bundle.id).
profile_app_id() {
  security cms -D -i $1 >$WORK/profile.plist 2>/dev/null || return 1
  plutil -extract Entitlements.application-identifier raw -o - $WORK/profile.plist 2>/dev/null
}

# Moves Prefill's cached profiles that expire within REFRESH_BEFORE out of Xcode's folders, so
# -allowProvisioningUpdates fetches fresh 7-day ones. restore_profiles puts them back.
retire_stale_profiles() {
  local dir file app expires
  for dir in $PROFILE_DIRS; do
    for file in $dir/*.mobileprovision(N); do
      app=$(profile_app_id $file) || continue
      [[ $app == *."$BUNDLE_ID" || $app == *."$BUNDLE_ID".safari ]] || continue
      expires=$(profile_expiry $file) || continue
      (( expires - EPOCHSECONDS < REFRESH_BEFORE )) || continue
      mkdir -p $RETIRED_DIR
      mv -f $file $RETIRED_DIR/ || continue
      retired+=($file)
      log "moved aside $app profile expiring $(when $expires): ${file:t}"
    done
  done
}

restore_profiles() {
  local file
  for file in $retired; do
    [[ -e $file ]] || mv -f $RETIRED_DIR/${file:t} $file 2>/dev/null || true
  done
  (( ${#retired} )) && log "put ${#retired} moved-aside profile(s) back"
  retired=()
}

# Prints reachable, unavailable, missing (not paired with this Mac) or unknown (couldn't tell).
device_state() {
  local json=$WORK/devices.json key i tunnel line wanted=${(L)DEVICE}
  if xcrun devicectl list devices --json-output $json >/dev/null 2>&1; then
    for (( i = 0; ; i++ )); do
      plutil -extract result.devices.$i json -o - $json >/dev/null 2>&1 || break
      for key in hardwareProperties.udid identifier deviceProperties.name; do
        if [[ ${(L)$(plutil -extract result.devices.$i.$key raw -o - $json 2>/dev/null)} == "$wanted" ]]; then
          tunnel=$(plutil -extract result.devices.$i.connectionProperties.tunnelState raw -o - $json 2>/dev/null) || tunnel=
          [[ $tunnel == unavailable ]] && print unavailable || print reachable
          return
        fi
      done
    done
    (( i > 0 )) && { print missing; return }
  fi
  # No JSON (older Xcode) or no devices in it: the table shows names and identifiers but not UDIDs.
  line=$(xcrun devicectl list devices 2>/dev/null | grep -iF -- $DEVICE | head -1) || true
  if [[ -z $line ]]; then print unknown
  elif [[ $line == *unavailable* ]]; then print unavailable
  else print reachable
  fi
}

# usage: run_install <output-file>  Runs install-device.sh with a time limit. Returns its status,
# or 124 if it ran out of time (usually a keychain prompt nobody can answer).
run_install() {
  local waited=0 rc=0
  zsh $SCRIPTS/install-device.sh $DEVICE >$1 2>&1 &
  child=$!
  while kill -0 $child 2>/dev/null; do
    if (( waited >= ATTEMPT_TIMEOUT )); then
      pkill -TERM -P $child 2>/dev/null || true
      kill -TERM $child 2>/dev/null || true
      wait $child 2>/dev/null || true
      child=
      return 124
    fi
    sleep 5
    (( waited += 5 ))
  done
  wait $child || rc=$?
  child=
  return $rc
}

record_success() {
  local expires=$1
  {
    print "# Written by scripts/auto-reinstall.sh after each successful install."
    print "installed_at=$EPOCHSECONDS"
    print "installed=$(strftime '%Y-%m-%d %H:%M:%S %z' $EPOCHSECONDS)"
    print "device=$DEVICE"
    print "profile_expires=$expires"
    print "commit=$(git -C $ROOT rev-parse HEAD 2>/dev/null)"
  } >$STATE_FILE.tmp
  mv -f $STATE_FILE.tmp $STATE_FILE
}

# Succeeds when an install is due; logs why not otherwise.
install_due() {
  $force && { log "forced"; return 0 }
  local at=$(state_value installed_at) expires=$(state_value profile_expires) last=$(state_value device)
  [[ -z $at ]] && { log "no earlier install recorded"; return 0 }
  [[ ${(L)last} != "${(L)DEVICE}" ]] && { log "last install went to $last"; return 0 }
  local built=$(state_value commit) head=$(git -C $ROOT rev-parse HEAD 2>/dev/null)
  [[ -n $head && $built != $head ]] && { log "the phone runs ${built:0:7}, the checkout is at ${head:0:7}"; return 0 }
  if [[ -n $expires ]] && (( expires - EPOCHSECONDS < REFRESH_BEFORE )); then
    log "installed profile expires $(when $expires)"
    return 0
  fi
  (( EPOCHSECONDS - at >= MIN_AGE )) && { log "last install was $(when $at)"; return 0 }
  log "skipping: installed $(when $at)${expires:+, signed until $(when $expires)}"
  return 1
}

# usage: give_up <reason>
give_up() {
  local expires=$(state_value profile_expires)
  restore_profiles
  log "FAILED: $1"
  notify "Couldn't reinstall on the iPhone: $1.${expires:+ The app stops working $(when $expires).} Log: ~/Library/Logs/Prefill"
  exit 1
}

cleanup() {
  [[ -n $child ]] && { pkill -TERM -P $child 2>/dev/null; kill -TERM $child 2>/dev/null } || true
  (( ${#retired} )) && restore_profiles
  rm -rf $WORK
  [[ -f $LOCK/pid && $(<$LOCK/pid) == $$ ]] && rm -rf $LOCK
  return 0
}
trap cleanup EXIT
trap 'log "stopped by signal"; exit 143' INT TERM HUP

if ! mkdir $LOCK 2>/dev/null; then
  if [[ -f $LOCK/pid ]] && kill -0 $(<$LOCK/pid) 2>/dev/null; then
    log "another run (pid $(<$LOCK/pid)) is still going; leaving it"
    exit 0
  fi
  rm -rf $LOCK
  mkdir $LOCK
fi
print $$ >$LOCK/pid

log "checking $DEVICE"
install_due || exit 0
[[ -n $BUNDLE_ID ]] || give_up "no PREFILL_BUNDLE_ID in Config/Personal.xcconfig"

retire_stale_profiles
deadline=$(( EPOCHSECONDS + RETRY_WINDOW ))
attempt=0
while true; do
  (( ++attempt ))
  out=$WORK/attempt-$attempt.log
  state=$(device_state)
  log "attempt $attempt: iPhone $state"
  [[ $state == missing ]] && give_up "$DEVICE isn't paired with this Mac (see xcrun devicectl list devices)"

  if [[ $state == unavailable ]]; then
    reason="the iPhone isn't connected"
  else
    rc=0
    : >$WORK/started
    run_install $out || rc=$?
    cat $out
    installed=false
    grep -q "App installed" $out && installed=true
    if (( rc == 0 )) || { $installed && grep -qiE '(^|[^0-9])(4016|10002)([^0-9]|$)|locked' $out }; then
      expires=$(profile_expiry $APP/embedded.mobileprovision) || expires=
      record_success $expires
      retired=()
      rm -rf $RETIRED_DIR
      (( rc == 0 )) || log "installed; launching failed because the phone is locked"
      if [[ -n $expires ]] && (( expires - EPOCHSECONDS < REFRESH_BEFORE )); then
        log "installed, but Xcode signed with a profile expiring $(when $expires); trying again tomorrow"
        notify "Reinstalled on the iPhone, but it's only signed until $(when $expires). Trying again tomorrow."
      else
        log "installed${expires:+, signed until $(when $expires)}"
        notify "Reinstalled on the iPhone.${expires:+ Signed until $(when $expires).}"
      fi
      exit 0
    fi

    if grep -qiE '(^|[^0-9])(4016|10002)([^0-9]|$)|locked' $out; then
      reason="the iPhone is locked"
    elif (( rc == 124 )); then
      give_up "the build took over $(( ATTEMPT_TIMEOUT / 60 )) minutes, probably waiting on a keychain prompt (see the top of scripts/auto-reinstall.sh)"
    elif [[ $BUILD_LOG -nt $WORK/started ]] && grep -qE 'errSecInternalComponent|User interaction is not allowed' $BUILD_LOG; then
      give_up "codesign couldn't use the signing key (see the keychain note in scripts/auto-reinstall.sh)"
    elif [[ $(device_state) == unavailable ]]; then
      reason="the iPhone went out of reach"
    else
      give_up "install-device.sh exited with $rc"
    fi
  fi

  if (( EPOCHSECONDS + RETRY_INTERVAL > deadline )); then
    give_up "$reason, tried for $(( RETRY_WINDOW / 60 )) minutes"
  fi
  log "$reason; trying again in $(( RETRY_INTERVAL / 60 )) minutes"
  sleep $RETRY_INTERVAL
done
