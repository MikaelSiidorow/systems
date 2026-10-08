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
details_file=${6:-/dev/null}

mkdir -p "$RUNNER_TEMP/report"
# --rawfile, because details can exceed the size limit of one argument.
jq -n \
  --arg key "$key" \
  --argjson order "$order" \
  --arg title "$title" \
  --arg status "$status" \
  --arg summary "$summary" \
  --rawfile details "$details_file" \
  '{$key, $order, $title, $status, $summary, details: ($details | rtrimstr("\n"))}' >"$RUNNER_TEMP/report/$key.json"
