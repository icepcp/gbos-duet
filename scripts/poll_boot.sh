#!/bin/bash
# poll_boot.sh [max_iter]: poll guest until SystemUI runs, boot completes, or system_server crashes
for i in $(seq 1 ${1:-40}); do
  r=$(python3 ~/gbos-duet/scripts/gsh.py 'echo "sui=$(pidof com.android.systemui || echo none) fatal=$(logcat -b crash -d | grep -c "FATAL EXCEPTION IN SYSTEM") bc=$(getprop sys.boot_completed) ss=$(pidof system_server)"' 110 2>/dev/null | tr '\n' ' ')
  echo "$(date +%T) $r"
  case "$r" in *sui=[0-9]*|*fatal=[1-9]*|*bc=1*) exit 0;; esac
  sleep ${INT:-30}
done
