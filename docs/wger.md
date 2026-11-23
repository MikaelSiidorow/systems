# wger deployment

wger runs at `https://wger.miksu.app`, deployed by Flux from `k8s/wger` and
`k8s/wger-ingress`. The web app, nginx, Celery, Redis, and PowerSync run in
K3s. The existing PostgreSQL 18 service on the host stores both wger and
PowerSync data; there is no PostgreSQL pod or database PVC. `k8s/wger/db.yaml`
publishes the host database as `db.wger.svc`.

The deployment deliberately keeps exercise videos disabled and requests only
7.25 GiB of local-path storage. The database stays on the server's main disk.
A Hetzner volume is therefore not required for the initial deployment.

## Secrets

Flux decrypts three SOPS files, encrypted to your post-quantum age key and
olympus's. Edit them with `sops <file>`:

- `k8s/wger/wger-secrets.sops.yaml` (`wger-secrets`): `SECRET_KEY`,
  `JWT_PUBLIC_KEY`, `JWT_PRIVATE_KEY`, and the `PS_DATABASE_URI` and
  `PS_STORAGE_PG_URI` connection strings, which embed the `wger` and
  `powersync_storage` role passwords. The `wger` password must match
  `postgres-wger-password` in `infra/secrets/olympus.yaml`; olympus sets the
  role's password from it.
- `k8s/wger/wger-admin-bootstrap.sops.yaml` (`wger-admin-bootstrap`): the
  initial administrator password the bootstrap Job sets.
- `k8s/wger/wger-email.sops.yaml` (`wger-email`): SMTP settings. They were
  copied from the main OpenTofu root's `wger_email` output; if Scaleway's SMTP
  credentials change there, update this file too.

Pods read these Secrets as environment variables, so a change needs a
restart. After changing `wger-secrets`, rerun the PowerSync setup first, which
applies the new `powersync_storage` credentials and which Flux otherwise runs
only when the Job's spec changes, then restart PowerSync:

```bash
kubectl -n wger rollout restart deployment/wger-web deployment/wger-celery-worker deployment/wger-celery-beat
kubectl -n wger delete job wger-powersync-setup
flux reconcile kustomization wger   # recreates and reruns the Job
kubectl -n wger wait --for=condition=complete job/wger-powersync-setup --timeout=10m
kubectl -n wger rollout restart deployment/wger-powersync
```

After changing only `wger-email`, restart `wger-web`, `wger-celery-worker` and
`wger-celery-beat`.

For a new deployment, generate the passwords and Django key locally:

```bash
openssl rand -hex 32
openssl rand -hex 32
openssl rand -hex 50
```

Generate the JWK pair using the pinned wger image:

```bash
docker run --rm --entrypoint ./manage.py \
  docker.io/wger/server:2.6.0 generate-jwt-keys
```

Copy the command's `JWT_PUBLIC_KEY` and `JWT_PRIVATE_KEY` values without
decoding them into `wger-secrets`.

## Rollout

Pushing to `main` brings wger up in this order:

1. The deploy workflow's Terraform creates the DNS record.
2. Its NixOS deploy creates the `wger` database and role and sets the role's
   password.
3. Flux, independently, applies `k8s/wger`; its Jobs keep retrying until step 2
   is done: the namespace, database Service, Secrets and
   workloads, plus two Jobs that wait for wger-web's migrations, then configure
   PowerSync and replace wger's known bootstrap administrator password. The
   `wger` Kustomization is Ready only once both Jobs have completed.
4. Flux applies `k8s/wger-ingress`, which depends on `wger`, so the public
   Ingress appears only after the administrator password is replaced.

Kustomize adds a content hash to `wger-config`. Any environment, nginx, Redis,
or PowerSync configuration change therefore updates pod templates and rolls
all consumers automatically, and makes Flux recreate and rerun both Jobs.

If a Job fails for good (its retries or its hour run out), `wger` stays not
Ready and Flux leaves the Job alone. Fix the cause, then
`kubectl -n wger delete job <name>` and Flux runs it again.

The first sync can take several minutes while wger runs migrations, collects
static files, and schedules reference-data imports.

## Verification and first login

```bash
kubectl -n wger get pods,pvc,ingress
kubectl -n wger logs deployment/wger-web -c web --tail=100
kubectl -n wger logs deployment/wger-powersync --tail=100
curl -fsS https://wger.miksu.app/
```

The initial administrator password is in `wger-admin-bootstrap`. Retrieve it over
the trusted SSH connection after the application becomes healthy:

```bash
ssh root@<IP> \
  "kubectl -n wger get secret wger-admin-bootstrap -o jsonpath='{.data.ADMIN_PASSWORD}'" \
  | base64 -d
echo
```

Log in as `admin`, replace the generated password with a password from your
password manager, and enable MFA. The bootstrap Job changes the password only
when it is still wger's factory default, so later syncs do not overwrite your
choice. Registration and guest access are disabled by default.

## Data and backups

- PostgreSQL: back up the `wger` database with the existing host database
  backup process or `pg_dump`.
- User uploads: back up the `wger-media` PVC.
- Redis, collected static files, and the Celery beat schedule are reproducible
  and do not need durable backups.

Pod logs are collected automatically by Alloy and are available in Loki with
`{namespace="wger"}`. Prometheus collects Kubernetes workload health and
PowerSync's `/metrics` endpoint through `wger-powersync` ServiceMonitor.

If media later outgrows the main disk, move only the media storage to an object
store or Hetzner volume. Keep PostgreSQL on the main SSD unless database growth
or measured I/O makes a separate volume worthwhile.
