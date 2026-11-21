#!/usr/bin/env bash
# Decrypts infra/secrets/ci.yaml and hands every key in it to the job's later
# steps as an environment variable, masked in the logs. Needs SOPS_AGE_KEY.
# Values must be single-line: GITHUB_ENV and log masking both work per line.
# They must not contain '%' either, which the runner decodes in a mask, so the
# real value would go unmasked.
set -euo pipefail

SOPS_VERSION=v3.13.3
SOPS_SHA256=e5bec3346a873ae91d871550f3e698c1aad962aff462a080e40f25fde17fef6b

sops="$RUNNER_TEMP/sops"
curl -fsSL -o "$sops" \
  "https://github.com/getsops/sops/releases/download/$SOPS_VERSION/sops-$SOPS_VERSION.linux.amd64"
echo "$SOPS_SHA256  $sops" | sha256sum --check --quiet
chmod +x "$sops"

"$sops" decrypt --output-type json "$GITHUB_WORKSPACE/infra/secrets/ci.yaml" |
  jq -r 'to_entries[] |
    if (.key | test("^[A-Za-z_][A-Za-z0-9_]*$") | not) then error("bad key name: \(.key)")
    elif (.value | tostring | test("[\n\r%]")) then error("\(.key) has a newline or %")
    else "\(.key)=\(.value)" end' |
  while IFS= read -r line; do
    echo "::add-mask::${line#*=}"
    echo "$line" >>"$GITHUB_ENV"
  done
