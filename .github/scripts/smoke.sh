#!/usr/bin/env bash
# Post-deploy smoke test for olympus: the host is up, Argo CD has synced
# the deployed commit, every workload has rolled out and stays up, and every
# Ingress host answers.
set -euo pipefail

readonly k3s_host="${1:?usage: smoke.sh K3S_HOST SHA}"
readonly sha="${2:?usage: smoke.sh K3S_HOST SHA}"
readonly -a ssh_options=(-o ServerAliveInterval=30 -o ServerAliveCountMax=20)
# Argo CD polls the repository every 120 s.
readonly host_timeout=300
readonly sync_timeout=600
readonly rollout_timeout=600
# Crash-looping containers restart within this window.
readonly watch_seconds=120
# Prints the keys of a Secret whose value is empty or still SOPS ciphertext.
readonly secret_template='{{range $k, $v := .data}}{{$d := base64decode $v}}{{if or (eq (len $d) 0) (eq (printf "%.4s" $d) "ENC[")}}{{$k}}{{"\n"}}{{end}}{{end}}'

if [[ ! "$k3s_host" =~ ^[A-Za-z0-9.:-]+$ ]]; then
  echo "K3S_HOST contains unsupported characters." >&2
  exit 1
fi

kubectl() {
  # shellcheck disable=SC2029
  ssh "${ssh_options[@]}" "root@$k3s_host" k3s kubectl "$@"
}

wait_for() {
  local timeout=$1 what=$2
  shift 2
  local deadline=$((SECONDS + timeout))
  until "$@"; do
    if ((SECONDS >= deadline)); then
      echo "::error::Timed out after ${timeout}s waiting for $what."
      return 1
    fi
    sleep 15
  done
}

# Functions run as `until` conditions, where set -e is off, so they check
# their queries themselves and retry on failure.

# Another run's switch may be restarting units or k3s.
host_ready() {
  local state
  # shellcheck disable=SC2029
  state=$(ssh "${ssh_options[@]}" "root@$k3s_host" systemctl is-system-running)
  if [ "$state" != running ]; then
    echo "olympus is ${state:-unreachable}."
    ssh "${ssh_options[@]}" "root@$k3s_host" systemctl --failed --no-legend
    return 1
  fi
  kubectl wait --for=condition=Ready node --all --timeout=30s
}

echo "::group::Host"
wait_for "$host_timeout" "olympus to be up" host_ready
if [ "${NIXOS_DEPLOYED:-}" = true ]; then
  # A later run may already have deployed a newer commit.
  # shellcheck disable=SC2029
  running=$(ssh "${ssh_options[@]}" "root@$k3s_host" nixos-version --configuration-revision) || running=
  git cat-file -e "$running^{commit}" 2>/dev/null || git fetch -q origin main || true
  if ! git merge-base --is-ancestor "$sha" "$running" 2>/dev/null; then
    echo "::error::olympus runs ${running:-an unknown revision}, not $sha or newer."
    exit 1
  fi
  echo "olympus runs $running."
fi
echo "::endgroup::"

# Apps that track the repository must reach this commit or a newer one. Chart
# apps report their chart version; the bootstrap app syncs their pins.
argo_synced() {
  local apps bad=0
  apps=$(kubectl -n argocd get applications -o json |
    jq -r '.items[] | [.metadata.name, .status.sync.status, .status.health.status, (.status.sync.revision // "")] | @tsv') || return 1
  while IFS=$'\t' read -r name sync health revision; do
    if [ "$sync" != Synced ]; then
      echo "$name: $sync"
      bad=1
    elif [[ "$revision" =~ ^[0-9a-f]{40}$ ]]; then
      # Argo CD may have synced a commit pushed after the checkout.
      git cat-file -e "$revision^{commit}" 2>/dev/null || git fetch -q origin main || true
      if ! git merge-base --is-ancestor "$sha" "$revision" 2>/dev/null; then
        echo "$name: at ${revision:0:7}"
        bad=1
      fi
    fi
    # Progressing is left to the rollout check below. Missing and Degraded
    # can flicker while a sync applies.
    case "$health" in
      Degraded | Missing | Unknown)
        echo "$name: $health"
        bad=1
        ;;
    esac
  done <<<"$apps"
  return "$bad"
}

echo "::group::Argo CD"
wait_for "$sync_timeout" "Argo CD to sync $sha" argo_synced
kubectl -n argocd get applications
echo "::endgroup::"

# FluxInstance and every expected Flux Kustomization must be Ready at this
# commit or newer (including SOPS decryption).
flux_synced() {
  local flux_ready ks_json ks root_rev expected name ready revision message rev secret_ids ns secret_name secret_problems helm_problems bad=0
  flux_ready=$(kubectl -n flux-system get fluxinstance flux -o json 2>/dev/null |
    jq -r '(.status.conditions // [] | map(select(.type == "Ready")) | .[0].status) // "Unknown"') || return 1
  if [ "$flux_ready" != True ]; then
    echo "FluxInstance/flux: Ready=$flux_ready"
    return 1
  fi
  ks_json=$(kubectl -n flux-system get kustomizations.kustomize.toolkit.fluxcd.io -o json 2>/dev/null) || return 1
  ks=$(jq -r '.items[] | [
      .metadata.name,
      ((.status.conditions // [] | map(select(.type == "Ready")) | .[0].status) // "Unknown"),
      (.status.lastAppliedRevision // ""),
      ((.status.conditions // [] | map(select(.type == "Ready")) | .[0].message) // "")
    ] | @tsv' <<<"$ks_json") || return 1
  if [ -z "$ks" ]; then
    echo "Flux: no Kustomizations yet"
    return 1
  fi
  root_rev=$(awk -F '\t' '$1 == "flux-system" && $2 == "True" { sub(/^.*@sha1:/, "", $3); print $3 }' <<<"$ks")
  if [[ ! "$root_rev" =~ ^[0-9a-f]{40}$ ]]; then
    echo "flux-system: not ready at a commit revision yet"
    return 1
  fi
  git cat-file -e "$root_rev^{commit}" 2>/dev/null || git fetch -q origin main || true
  if ! git merge-base --is-ancestor "$sha" "$root_rev" 2>/dev/null; then
    echo "flux-system: at ${root_rev:0:7}"
    return 1
  fi
  # Every child Kustomization in flux-system's reconciled inventory must exist
  # and be Ready at this commit or newer.
  expected=$(jq -r '
    .items[]
    | select(.metadata.name == "flux-system")
    | .status.inventory.entries[]?.id
    | select(startswith("flux-system_") and endswith("_kustomize.toolkit.fluxcd.io_Kustomization"))
    | ltrimstr("flux-system_")
    | rtrimstr("_kustomize.toolkit.fluxcd.io_Kustomization")' <<<"$ks_json") || return 1
  if [ -z "$expected" ]; then
    echo "flux-system: inventory lists no child Kustomizations"
    return 1
  fi
  while read -r name; do
    [ -n "$name" ] || continue
    if ! awk -F '\t' -v n="$name" '$1 == n { found = 1 } END { exit !found }' <<<"$ks"; then
      echo "$name: missing from cluster"
      bad=1
    fi
  done <<<"$expected"
  while IFS=$'\t' read -r name ready revision message; do
    rev=${revision##*@sha1:}
    if [ "$ready" != True ]; then
      echo "$name: Ready=$ready ($message)"
      bad=1
    elif [[ "$rev" =~ ^[0-9a-f]{40}$ ]]; then
      git cat-file -e "$rev^{commit}" 2>/dev/null || git fetch -q origin main || true
      if ! git merge-base --is-ancestor "$sha" "$rev" 2>/dev/null; then
        echo "$name: at ${rev:0:7}"
        bad=1
      fi
    else
      echo "$name: unexpected revision ${revision:-empty}"
      bad=1
    fi
  done <<<"$ks"
  # Every Secret a Kustomization applied must exist with every value set and
  # decrypted. olympus checks the values itself, so they never leave the host;
  # only names and keys are printed.
  secret_ids=$(jq -r '
    .items[].status.inventory.entries[]?.id
    | select(endswith("__Secret"))
    | rtrimstr("__Secret")' <<<"$ks_json") || return 1
  while IFS=_ read -r ns secret_name; do
    [ -n "$ns" ] || continue
    # Kubernetes names hold no spaces or quotes, but quote them for the remote
    # shell anyway.
    # shellcheck disable=SC2029
    if ! secret_problems=$(ssh "${ssh_options[@]}" "root@$k3s_host" \
      "k3s kubectl -n $(printf %q "$ns") get secret $(printf %q "$secret_name") -o go-template=$(printf %q "$secret_template")"); then
      echo "$ns/$secret_name: missing"
      bad=1
    elif [ -n "$secret_problems" ]; then
      echo "$secret_problems" | sed "s|^|$ns/$secret_name: |; s|\$| is empty or still encrypted|"
      bad=1
    fi
  done <<<"$secret_ids"
  # Every HelmRelease must be Ready at its current spec.
  helm_problems=$(kubectl get helmreleases.helm.toolkit.fluxcd.io -A -o json 2>/dev/null | jq -r '
    .items[]
    | ((.status.conditions // []) | map(select(.type == "Ready")) | .[0]) as $ready
    | select(($ready.status // "Unknown") != "True" or ($ready.observedGeneration // 0) < .metadata.generation)
    | "HelmRelease/\(.metadata.namespace)/\(.metadata.name): Ready=\($ready.status // "Unknown") (\($ready.message // ""))"') || return 1
  if [ -n "$helm_problems" ]; then
    echo "$helm_problems"
    bad=1
  fi
  return "$bad"
}

echo "::group::Flux"
wait_for "$sync_timeout" "Flux to sync $sha" flux_synced
kubectl -n flux-system get fluxinstance,gitrepository,kustomizations.kustomize.toolkit.fluxcd.io,helmreleases.helm.toolkit.fluxcd.io
echo "::endgroup::"

rolled_out() {
  local pending
  pending=$(kubectl get deployments,statefulsets,daemonsets -A -o json | jq -r '
    .items[]
    | select(
        if .kind == "DaemonSet" then
          (.status.observedGeneration // 0) < .metadata.generation or
          (.status.updatedNumberScheduled // 0) != .status.desiredNumberScheduled or
          (.status.numberAvailable // 0) != .status.desiredNumberScheduled
        else
          (.status.observedGeneration // 0) < .metadata.generation or
          (.status.updatedReplicas // 0) != .spec.replicas or
          (.status.availableReplicas // 0) != .spec.replicas
        end)
    | "\(.kind)/\(.metadata.namespace)/\(.metadata.name)"') || return 1
  [ -z "$pending" ] || {
    echo "Waiting for: $pending" | tr '\n' ' '
    echo
    return 1
  }
}

echo "::group::Rollouts"
wait_for "$rollout_timeout" "workloads to roll out" rolled_out
echo "::endgroup::"

restarts() {
  kubectl get pods -A -o json | jq -r '
    .items[]
    | "\(.metadata.namespace)/\(.metadata.name) \([.status.containerStatuses[]?.restartCount] | add // 0)"' |
    sort
}

echo "::group::Pods"
before=$(restarts)
sleep "$watch_seconds"
after=$(restarts)
failed=0
# Pods present in both snapshots whose restart count went up.
crashed=$(join <(echo "$before") <(echo "$after") | awk '$3 > $2 { print $1 " restarted " $3 - $2 " times" }')
if [ -n "$crashed" ]; then
  echo "$crashed"
  echo "::error::Containers restarted after the rollout."
  failed=1
fi
stuck=$(kubectl get pods -A -o json | jq -r '
  .items[]
  | .metadata as $m
  | .status.containerStatuses[]?, .status.initContainerStatuses[]?
  | select(.state.waiting.reason // "" | test("BackOff|Err|Invalid|CreateContainer"))
  | "\($m.namespace)/\($m.name) \(.name): \(.state.waiting.reason)"')
if [ -n "$stuck" ]; then
  echo "$stuck"
  echo "::error::Containers are stuck."
  failed=1
fi
echo "::endgroup::"

status() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 20 --resolve "$2:$3:$1" "$4://$2/" || true
}

up() {
  [ "$1" != 000 ] && (($1 < 500))
}

echo "::group::Ingress"
# Some hosts resolve to the tailnet only, so connect to olympus directly.
# Hosts behind the tailnet-only middleware must refuse the public address;
# with TAILNET_IP set (the runner joined the tailnet) they must answer there.
hosts=$(kubectl get ingress -A -o json | jq -r '
  [.items[]
    | (.metadata.annotations["traefik.ingress.kubernetes.io/router.middlewares"] // "" | test("tailnet-only")) as $tailnet
    | .spec.rules[]?.host // empty
    | "\(.) \($tailnet)"]
  | unique[]')
while read -r host tailnet_only; do
  https=$(status "$k3s_host" "$host" 443 https)
  http=$(status "$k3s_host" "$host" 80 http)
  if [ "$tailnet_only" = true ]; then
    if [ -n "${TAILNET_IP:-}" ]; then
      tailnet=$(status "$TAILNET_IP" "$host" 443 https)
    else
      tailnet=skipped
    fi
    echo "$host: public https $https, http $http, tailnet https $tailnet"
    if [ "$https" != 403 ]; then
      echo "::error::https://$host/ returned $https on the public address, not 403."
      failed=1
    fi
    if [ "$tailnet" != skipped ] && { [ "$tailnet" = 403 ] || ! up "$tailnet"; }; then
      echo "::error::https://$host/ returned $tailnet over the tailnet."
      failed=1
    fi
  else
    echo "$host: https $https, http $http"
    if ! up "$https"; then
      echo "::error::https://$host/ returned $https."
      failed=1
    fi
  fi
  if [ "$http" != 301 ] && [ "$http" != 308 ]; then
    echo "::error::http://$host/ returned $http, not a redirect."
    failed=1
  fi
done <<<"$hosts"
echo "::endgroup::"

exit "$failed"
