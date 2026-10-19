#!/usr/bin/env bash
# Post-deploy smoke test for k8s-server: the host is up, Argo CD has synced
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
    echo "k8s-server is ${state:-unreachable}."
    ssh "${ssh_options[@]}" "root@$k3s_host" systemctl --failed --no-legend
    return 1
  fi
  kubectl wait --for=condition=Ready node --all --timeout=30s
}

echo "::group::Host"
wait_for "$host_timeout" "k8s-server to be up" host_ready
if [ "${NIXOS_DEPLOYED:-}" = true ]; then
  # A later run may already have deployed a newer commit.
  # shellcheck disable=SC2029
  running=$(ssh "${ssh_options[@]}" "root@$k3s_host" nixos-version --configuration-revision)
  git cat-file -e "$running^{commit}" 2>/dev/null || git fetch -q origin main || true
  if ! git merge-base --is-ancestor "$sha" "$running" 2>/dev/null; then
    echo "::error::k8s-server runs ${running:-an unknown revision}, not $sha or newer."
    exit 1
  fi
  echo "k8s-server runs $running."
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
# Some hosts resolve to the tailnet only, so connect to k8s-server directly.
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
