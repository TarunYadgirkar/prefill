#!/bin/bash
# usage: run-safari.sh STEP QUERY FIELD [extra drive args]
D=/Users/tarunyadgirkar/TarunsCode/prefill/spikes/datalist; U=47A4C2A7-9518-49BF-92C1-D602AAE4E6D9
STEP=$1; Q=$2; FIELD=$3; shift 3
xcrun simctl terminate $U com.apple.mobilesafari 2>/dev/null
sleep 1
xcrun simctl openurl $U "http://127.0.0.1:8801/page.html?run=$STEP&$Q"
sleep 4
$D/drive.sh $STEP testSafariField "FIELD=$FIELD" HOLD=30 "$@" | grep -E "^shot|exit|no "
python3 - "$STEP" <<'PY'
import json,sys
step=sys.argv[1]
for line in open('/Users/tarunyadgirkar/TarunsCode/prefill/spikes/datalist/logs/events.jsonl'):
    d=json.loads(line)['data']
    if d.get('src')=='uitest' and d.get('step')==step and 'tree' in d:
        open(f"/Users/tarunyadgirkar/TarunsCode/prefill/spikes/datalist/logs/tree-{step}-{d['event']}.txt",'w').write(d['tree'])
PY
