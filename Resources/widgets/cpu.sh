#!/bin/bash
set -e
source "$STABLEBAR_SCRIPTS/environment.sh"
processes=$(ps -Aco pid=,pcpu=,rss=,comm= -r)
percentage=$(echo "$processes" | awk -v cores="$(sysctl -n hw.logicalcpu)" '{sum+=$2} END {printf "%d",sum/cores}')
load=$(sysctl -n vm.loadavg)
rows=$(echo "$processes" | head -5 | awk '{pid=$1; cpu=$2; rss=$3; $1=$2=$3=""; sub(/^[[:space:]]+/, ""); printf "%s\t%s\t%s\t%s\n",pid,cpu,rss,$0}' | jq -Rn '[inputs | split("\t") | {pid:.[0],cpu:(.[1]+"%"),memory:(((.[2]|tonumber)/1024|floor|tostring)+" MB"),name:.[3]}]')
jq -cn --argjson percent "$percentage" --arg load "$load" --argjson rows "$rows" '
  {text:(($percent|tostring)+"%"),value:($percent/100),tooltip:"CPU usage",
   fields:{usage:(($percent|tostring)+"%"),load:$load},lists:{processes:$rows},
   menu:([{title:"CPU usage",detail:(($percent|tostring)+"%")},{title:"Load average",detail:$load}]+
     ($rows|map({title:.name,detail:("PID "+.pid+" · "+.cpu+" · "+.memory),onClick:"open -a \u0027Activity Monitor\u0027"})))}'
