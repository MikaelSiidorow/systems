#!/usr/bin/env bash

set -euo pipefail

readonly k3s_host="${1:?usage: reconcile-wger.sh K3S_HOST}"
readonly ssh_target="root@${k3s_host}"
readonly -a ssh_options=(-o ServerAliveInterval=30 -o ServerAliveCountMax=20)

if [[ ! "$k3s_host" =~ ^[A-Za-z0-9.:-]+$ ]]; then
  echo "K3S_HOST contains unsupported characters." >&2
  exit 1
fi

if [[ ! "${WGER_POSTGRES_PASSWORD:-}" =~ ^[A-Za-z0-9_-]{32,}$ ]]; then
  echo "WGER_POSTGRES_PASSWORD must be at least 32 URL-safe characters." >&2
  exit 1
fi

remote() {
  # All remote arguments are fixed below or validated above.
  # shellcheck disable=SC2029
  ssh "${ssh_options[@]}" "$ssh_target" "$@"
}

remote_kubectl() {
  remote k3s kubectl "$@"
}

if remote_kubectl -n wger get secret wger-email >/dev/null 2>&1; then
  readonly -a required_email_keys=(
    ENABLE_EMAIL
    EMAIL_HOST
    EMAIL_PORT
    EMAIL_HOST_USER
    EMAIL_HOST_PASSWORD
    EMAIL_USE_TLS
    EMAIL_USE_SSL
    FROM_EMAIL
  )

  for key in "${required_email_keys[@]}"; do
    # Test the value remotely so credential contents never enter CI output.
    if ! remote "test -n \"\$(k3s kubectl -n wger get secret wger-email -o 'jsonpath={.data.${key}}')\""; then
      echo "wger-email is missing or has an empty $key; refusing to restart consumers." >&2
      exit 1
    fi
  done
fi

printf "ALTER ROLE wger PASSWORD '%s';\n" "$WGER_POSTGRES_PASSWORD" |
  remote sudo -u postgres psql --set=ON_ERROR_STOP=1

# Terraform has installed the replacement Endpoints resource, so the
# EndpointSlice left by the old static manifest can now be removed safely.
remote_kubectl -n wger delete endpointslice db --ignore-not-found

if ! remote_kubectl -n wger get deployment wger-web >/dev/null 2>&1; then
  echo "wger has not been bootstrapped by Argo CD yet; its sync hooks will configure PowerSync."
  exit 0
fi

for deployment in wger-web wger-celery-worker wger-celery-beat; do
  if remote_kubectl -n wger get deployment "$deployment" >/dev/null 2>&1; then
    remote_kubectl -n wger rollout restart deployment/"$deployment"
  fi
done
remote_kubectl -n wger rollout status deployment/wger-web --timeout=10m

remote_kubectl -n wger delete job wger-powersync-credentials \
  --ignore-not-found --wait=true
remote k3s kubectl apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: wger-powersync-credentials
  namespace: wger
spec:
  backoffLimit: 3
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: setup
          image: ghcr.io/mikaelsiidorow/wger:production
          imagePullPolicy: Always
          command: [./manage.py, setup-powersync-storage]
          envFrom:
            - secretRef:
                name: wger-secrets
EOF

if ! remote_kubectl -n wger wait --for=condition=complete \
  job/wger-powersync-credentials --timeout=5m; then
  remote_kubectl -n wger logs job/wger-powersync-credentials \
    --all-containers --tail=-1 || true
  exit 1
fi
remote_kubectl -n wger logs job/wger-powersync-credentials \
  --all-containers --tail=-1
remote_kubectl -n wger delete job wger-powersync-credentials --wait=true

if remote_kubectl -n wger get deployment wger-powersync >/dev/null 2>&1; then
  remote_kubectl -n wger rollout restart deployment/wger-powersync
  remote_kubectl -n wger rollout status deployment/wger-powersync --timeout=5m
fi
