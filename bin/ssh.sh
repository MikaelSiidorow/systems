#!/usr/bin/env bash
set -euo pipefail
IP=$(cd terraform && tofu output -raw k3s_ipv4_address)
exec ssh root@"$IP"