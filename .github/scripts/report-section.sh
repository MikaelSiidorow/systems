#!/usr/bin/env bash
# Write one section of the pull request CI report that ci.yml's report job
# collects into a single comment.
#
# Usage: report-section.sh <key> <order> <title> <status> <summary> [details-file]
#   status: success | changes | failure | skipped
set -euo pipefail

key=$1
order=$2
title=$3
status=$4
summary=$5
details_file=${6:-}

details=""
if [ -n "$details_file" ]; then
  details=$(cat "$details_file")
fi

mkdir -p "$RUNNER_TEMP/report"
jq -n \
  --arg key "$key" \
  --argjson order "$order" \
  --arg title "$title" \
  --arg status "$status" \
  --arg summary "$summary" \
  --arg details "$details" \
  '{$key, $order, $title, $status, $summary, $details}' >"$RUNNER_TEMP/report/$key.json"
