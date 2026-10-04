#!/usr/bin/env bash
set -euo pipefail
IP=$(cd terraform && terraform output -raw k3s_ipv4_address)
exec ssh root@"$IP"