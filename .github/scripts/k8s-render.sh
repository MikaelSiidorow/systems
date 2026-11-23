#!/usr/bin/env bash
# Render every Argo CD app the way Argo CD does, every Flux Kustomization and
# HelmRelease the way Flux does, and every k3s HelmChart the
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
  local -a repo_args=()
  if [[ -n "$repo" ]]; then
    repo_args=(--repo "$repo")
  fi
  printf '%s\n' "$values" >"$out/$file.values"
  helm template "$name" "$chart" \
    "${repo_args[@]}" \
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

# olympus's NixOS config hands these to k3s, which installs them before
# Argo CD and Flux exist.
for file in infra/nixos/hosts/olympus/*-helmchart.yaml; do
  name="$(yq '.metadata.name' "$file")"
  render_chart "k3s-$name" "$name" \
    "$(yq '.spec.chart' "$file")" \
    "$(yq '.spec.repo // ""' "$file")" \
    "$(yq '.spec.version' "$file")" \
    "$(yq '.spec.targetNamespace' "$file")" \
    "$(yq '.spec.valuesContent // ""' "$file")"
done

# Render Flux cluster kustomizations and each path they reconcile, applying
# any spec.patches declared on the Flux Kustomization. SOPS metadata is
# stripped because Flux removes it when decrypting Secrets.
if [[ -d k8s/clusters/olympus ]]; then
  kustomize build k8s/clusters/olympus | yq 'del(.sops)' >"$out/flux-cluster.yaml"
  overlay="$(mktemp -d)"
  trap 'rm -rf "$overlay"' EXIT
  while IFS=$'\t' read -r name path; do
    [[ -n "$name" ]] || continue
    path="${path#./}"
    if [[ ! -f "$path/kustomization.yaml" ]]; then
      echo "Flux Kustomization '$name' references missing kustomization: $path/kustomization.yaml" >&2
      exit 1
    fi
    rm -f "$overlay/base.yaml" "$overlay/kustomization.yaml"
    kustomize build "$path" >"$overlay/base.yaml"
    if [[ "$(NAME="$name" yq 'select(.kind == "Kustomization" and .apiVersion == "kustomize.toolkit.fluxcd.io/v1" and .metadata.name == strenv(NAME)) | (.spec.patches // []) | length' "$out/flux-cluster.yaml")" != 0 ]]; then
      NAME="$name" yq 'select(.kind == "Kustomization" and .apiVersion == "kustomize.toolkit.fluxcd.io/v1" and .metadata.name == strenv(NAME)) | {"apiVersion": "kustomize.config.k8s.io/v1beta1", "kind": "Kustomization", "resources": ["base.yaml"], "patches": .spec.patches}' "$out/flux-cluster.yaml" >"$overlay/kustomization.yaml"
      kustomize build "$overlay" | yq 'del(.sops)' >"$out/flux-$name.yaml"
    else
      yq 'del(.sops)' "$overlay/base.yaml" >"$out/flux-$name.yaml"
    fi
  done < <(yq -r 'select(.kind == "Kustomization" and .apiVersion == "kustomize.toolkit.fluxcd.io/v1") | [.metadata.name, .spec.path] | @tsv' "$out/flux-cluster.yaml")

  # Render each Flux HelmRelease's chart with its values, the way
  # helm-controller installs it.
  flux_files=("$out"/flux-*.yaml)
  # A separate assignment, so a yq failure stops the script instead of
  # silently rendering nothing.
  releases="$(yq -r 'select(.kind == "HelmRelease") | [.metadata.name, (.spec.releaseName // ""), .spec.chart.spec.chart, .spec.chart.spec.version, .spec.chart.spec.sourceRef.kind, .spec.chart.spec.sourceRef.name, (.spec.targetNamespace // ""), .metadata.namespace] | @tsv' "${flux_files[@]}")"
  while IFS=$'\t' read -r name release chart version repo_kind repo target_ns own_ns; do
    [[ -n "$name" ]] || continue
    if [[ "$repo_kind" != HelmRepository ]]; then
      echo "HelmRelease '$name' uses a $repo_kind source, which this script cannot render" >&2
      exit 1
    fi
    # Flux's default release name is <targetNamespace>-<name>.
    release="${release:-${target_ns:+$target_ns-}$name}"
    url="$(REPO="$repo" yq -r 'select(.kind == "HelmRepository" and .metadata.name == strenv(REPO)) | .spec.url' "${flux_files[@]}" | head -n 1)"
    if [[ -z "$url" ]]; then
      echo "HelmRelease '$name' references missing HelmRepository: $repo" >&2
      exit 1
    fi
    render_chart "helm-$name" "$release" "$chart" "$url" "$version" "${target_ns:-$own_ns}" \
      "$(NAME="$name" yq 'select(.kind == "HelmRelease" and .metadata.name == strenv(NAME)) | .spec.values // {}' "${flux_files[@]}")"
  done <<<"$releases"
fi
