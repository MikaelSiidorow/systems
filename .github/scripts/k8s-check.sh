#!/usr/bin/env bash
# Render every Argo CD app the way Argo CD does and validate the result, plus
# the Application manifests themselves, against the Kubernetes and CRD schemas.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

readonly crd_schemas='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
readonly kube_version=1.35.0

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

for app in k8s/apps/*.yaml; do
  name="$(yq '.metadata.name' "$app")"
  chart="$(yq '.spec.source.chart // ""' "$app")"
  path="$(yq '.spec.source.path // ""' "$app")"

  if [[ -n "$chart" ]]; then
    yq '.spec.source.helm.values // ""' "$app" >"$out/$name.values"
    helm template "$name" "$chart" \
      --repo "$(yq '.spec.source.repoURL' "$app")" \
      --version "$(yq '.spec.source.targetRevision' "$app")" \
      --namespace "$(yq '.spec.destination.namespace' "$app")" \
      --kube-version "$kube_version" \
      --include-crds \
      --values "$out/$name.values" >"$out/$name.yaml"
  elif [[ -f "$path/kustomization.yaml" ]]; then
    kustomize build "$path" >"$out/$name.yaml"
  else
    # Argo CD reads only the tracked top-level manifests of a directory app.
    git ls-files -- "$path" | grep -E "^$path/[^/]+\.(ya?ml|json)$" |
      while read -r file; do
        printf -- '---\n'
        cat "$file"
      done >"$out/$name.yaml"
  fi
done

# Charts' own CRD definitions have no published schema; their custom
# resources are still checked against the CRD catalog.
kubeconform -strict -summary \
  -kubernetes-version "$kube_version" \
  -skip CustomResourceDefinition \
  -schema-location default \
  -schema-location "$crd_schemas" \
  k8s/apps "$out"/*.yaml
