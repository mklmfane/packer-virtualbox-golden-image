#!/usr/bin/env bash
# Configuration values are shell-quoted by Python before evaluation.
eval "$(python3 - <<'PYTHON'
import json,shlex
c=json.load(open('/etc/lab-node.json'))
for k,v in c.items(): print('export '+k.upper()+'='+shlex.quote(str(v)))
PYTHON
)"
