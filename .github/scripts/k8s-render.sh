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

# Usage: render_chart <file> <release> <chart> <repo> <version> <namespace> <values>
render_chart() {
  local file=$1 name=$2 chart=$3 repo=$4 version=$5 namespace=$6 values=$7
  printf '%s\n' "$values" >"$out/$file.values"
  helm template "$name" "$chart" \
    --repo "$repo" \
    --version "$version" \
    --namespace "$namespace" \
    --kube-version "$kube_version" \
    --include-crds \
    --values "$out/$file.values" >"$out/$file.yaml"
  rm "$out/$file.values"
}

for app in k8s/apps/*.yaml; do
  name="$(yq '.metadata.name' "$app")"
  chart="$(yq '.spec.source.chart // ""' "$app")"
  path="$(yq '.spec.source.path // ""' "$app")"

  if [[ -n "$chart" ]]; then
    render_chart "$name" "$name" "$chart" \
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
  name="$(yq '.metadata.name' "$file")"
  render_chart "k3s-$name" "$name" \
    "$(yq '.spec.chart' "$file")" \
    "$(yq '.spec.repo' "$file")" \
    "$(yq '.spec.version' "$file")" \
    "$(yq '.spec.targetNamespace' "$file")" \
    "$(yq '.spec.valuesContent // ""' "$file")"
done
