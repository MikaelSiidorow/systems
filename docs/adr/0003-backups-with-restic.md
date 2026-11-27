# Back up olympus with restic, to hestia and R2

- Status: accepted
- Date: 2026-11-27

## Context

olympus holds the only copy of the data that matters: the PostgreSQL databases
(ADR 0002), Headscale's database and keys, wger's uploaded media and Gatus's
history. Everything else comes back from Git. Nothing is backed up today, so a
lost disk or a bad migration loses data for good.

## Decision

restic backs up olympus every night. hestia keeps one repository and copies it
to an R2 bucket, so there is a copy at home and one off-site:

```
olympus ── restic backup ──▶ hestia rest-server (append-only, tailnet only)
                                │
                                └── restic copy ──▶ R2 bucket
```

- olympus writes only through hestia's rest-server, which runs append-only. A
  compromised olympus can add snapshots but not delete or rewrite them, and it
  holds no R2 credentials.
- hestia runs everything that deletes: it prunes both repositories as root,
  reading its repository from disk instead of through the rest-server.
  hestia is not reachable from the internet, which olympus is.
- The tailnet ACL lets only `tag:infra` (olympus) reach the rest-server, and the
  rest-server needs a login on top of that.
- olympus dumps each database with `pg_dump` and copies Headscale's SQLite
  database with `.backup` before restic runs, so every snapshot is consistent.
- Retention: 7 daily, 4 weekly and 6 monthly snapshots in both repositories.
- A weekly job on hestia restores the latest snapshot and loads the dumps into
  a throwaway PostgreSQL. Every job reports to Gatus, which alerts on Telegram
  when one fails or stops reporting.

Both repositories share one password. olympus needs it to encrypt, hestia to
copy, prune and test. It lives in `infra/secrets/olympus.yaml`,
`infra/secrets/hestia.yaml` and Bitwarden. The R2 credentials live only in
`hestia.yaml` and Bitwarden, so a restore from R2 needs nothing but Bitwarden
and a machine with restic.

restic encrypts on the machine that makes the backup, with AES-256 and
Poly1305. It uses no public-key cryptography, so the stored data does not
depend on anything a quantum computer breaks. Its key comes from the password
through scrypt, so the password is 32+ random characters, not a passphrase.

## Consequences

- R2 and hestia store only ciphertext.
- Losing olympus loses at most a day of data. Losing olympus and hestia
  together still leaves the R2 copy.
- The password can be read by anything that reads `olympus.yaml` on the host,
  including Flux's copy of the age key. Anything with that access can already
  read the databases.
- When hestia is offline, olympus's backup fails and alerts; the next night
  catches up.
- A compromised hestia can delete both copies. R2 bucket locks would stop
  that, but they conflict with pruning, so they are not used for now.
