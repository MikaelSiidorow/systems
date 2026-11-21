#!/usr/bin/env bash
set -euo pipefail
IP=$(cd tofu && sops exec-env ../infra/secrets/ci.yaml 'tofu output -raw k3s_ipv4_address')
exec ssh root@"$IP"