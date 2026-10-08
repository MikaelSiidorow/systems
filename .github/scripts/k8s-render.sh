#!/usr/bin/env bash
# Render every Argo CD app the way Argo CD does, and every k3s HelmChart the
# way the k3s helm controller does, into one file per app in <out-dir>.
#
# Usage: k8s-render.sh <out-dir>   (run from inside the checkout to render)
set -euo pipefail
shopt -s nullglob

out="$(realpath "$1")"
cd "$(git rev-parse --show-toplevel)"

readonly kube_version=1.35.0

render_chart() {
  local name=$1 chart=$2 repo=$3 version=$4 namespace=$5 values=$6
  printf '%s\n' "$values" >"$out/$name.values"
  helm template "$name" "$chart" \
    --repo "$repo" \
    --version "$version" \
    --namespace "$namespace" \
    --kube-version "$kube_version" \
    --include-crds \
    --values "$out/$name.values" >"$out/$name.yaml"
  rm "$out/$name.values"
}

for app in k8s/apps/*.yaml; do
  name="$(yq '.metadata.name' "$app")"
  chart="$(yq '.spec.source.chart // ""' "$app")"
  path="$(yq '.spec.source.path // ""' "$app")"

  if [[ -n "$chart" ]]; then
    render_chart "$name" "$chart" \
      "$(yq '.spec.source.repoURL' "$app")" \
      "$(yq '.spec.source.targetRevision' "$app")" \
      "$(yq '.spec.destination.namespace' "$app")" \
      "$(yq '.spec.source.helm.values // ""' "$app")"
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

# k8s-server's NixOS config hands these to k3s, which installs them before
# Argo CD exists.
for file in infra/nixos/hosts/k8s-server/*-helmchart.yaml; do
  render_chart "k3s-$(yq '.metadata.name' "$file")" \
    "$(yq '.spec.chart' "$file")" \
    "$(yq '.spec.repo' "$file")" \
    "$(yq '.spec.version' "$file")" \
    "$(yq '.spec.targetNamespace' "$file")" \
    "$(yq '.spec.valuesContent // ""' "$file")"
done
