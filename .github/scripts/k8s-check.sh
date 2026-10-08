#!/usr/bin/env bash
# Validate the rendered Argo CD apps and k3s HelmCharts, plus the Application
# and HelmChart manifests themselves, against the Kubernetes and CRD schemas.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

readonly crd_schemas='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

.github/scripts/k8s-render.sh "$out"

# The Kubernetes version matches k8s-render.sh. Charts' own CRD definitions
# have no published schema; their custom resources are still checked against
# the CRD catalog.
kubeconform -strict -summary \
  -kubernetes-version 1.35.0 \
  -skip CustomResourceDefinition \
  -schema-location default \
  -schema-location "$crd_schemas" \
  k8s/apps infra/nixos/hosts/k8s-server/*-helmchart.yaml "$out"/*.yaml
