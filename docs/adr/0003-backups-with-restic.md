# Back up olympus to hestia and R2 with restic

- Status: accepted
- Date: 2026-11-27

## Context

olympus holds the only copy of the PostgreSQL databases (ADR 0002), Headscale's
database and keys, wger's uploaded media, and Gatus's history. Everything else
comes from Git. None of it is backed up today, so a lost disk or a bad
migration loses that data permanently.

## Decision

restic backs up olympus every night to a repository on hestia. hestia copies
that repository to an R2 bucket, so there is one copy at home and one off-site:

```
olympus ── restic backup ──▶ hestia rest-server (append-only, tailnet only)
                                │
                                └── restic copy ──▶ R2 bucket
```

olympus writes only through hestia's rest-server, which runs in append-only
mode. A compromised olympus can add snapshots, but it cannot delete or rewrite
them, and it holds no R2 credentials. The tailnet ACL lets only `tag:infra`
(olympus) reach the rest-server, and the rest-server also requires a login.

hestia handles all deletions. It prunes both repositories as root, reading its
own repository from disk instead of through the rest-server. Unlike olympus,
hestia is not reachable from the internet. Both repositories keep 7 daily, 4
weekly, and 6 monthly snapshots.

Before restic runs, olympus dumps each database with `pg_dump` and copies
Headscale's SQLite database with `.backup` so every snapshot is consistent. A
weekly job on hestia restores the latest snapshot and loads the dumps into a
throwaway PostgreSQL instance. Every job reports to Gatus, which alerts on
Telegram when one fails or stops reporting.

Both repositories share one password. olympus uses it to encrypt backups, and
hestia uses it to copy, prune, and test them. It lives in
`infra/secrets/olympus.yaml`, `infra/secrets/hestia.yaml`, and Bitwarden. The
R2 credentials live only in `hestia.yaml` and Bitwarden, so restoring from R2
needs only Bitwarden and a machine with restic.

restic encrypts backups on the source machine with AES-256 and Poly1305. It
uses no public-key cryptography, so the stored data does not depend on
algorithms a quantum computer can break. The key comes from the password via
scrypt, so the password is 32+ random characters instead of a passphrase.

## Consequences

- R2 and hestia store only ciphertext.
- Losing olympus loses at most a day of data. If both olympus and hestia are
  lost, the R2 copy remains.
- Anything that reads `olympus.yaml` on the host, including Flux's copy of the
  age key, can read the repository password. The same access already covers the
  databases.
- If hestia is offline, olympus's backup fails and alerts. The next nightly run
  catches up.
- A compromised hestia can delete both copies. R2 bucket locks would stop that,
  but they conflict with pruning, so they are not used for now.
