# PostgreSQL runs on the host, not in Kubernetes

- Status: accepted
- Date: 2026-11-25 (recording an earlier decision)

## Context

refinery, zero-cache, wger and PowerSync need PostgreSQL. olympus is a single
8 GB node, and its local-path volumes are tied to the node name.

## Decision

NixOS runs one PostgreSQL instance on olympus. Pods reach it on the k3s
bridge address (10.42.0.1) through a Service and EndpointSlice per namespace.
NixOS declares the databases, roles, passwords (from SOPS), logical
replication, and the steps only a superuser may take: the PowerSync
publication and zero-cache's event triggers.

## Consequences

- The data outlives the cluster: reinstalling k3s or losing its state leaves
  the databases alone.
- The apps never hold superuser rights.
- One instance serves every app, which fits 8 GB better than one per app,
  and there is no operator to run and upgrade.
- Major upgrades are deliberate: dependency automation never merges a
  PostgreSQL major.
- The database sits outside GitOps and is only as safe as the host, so it
  needs host backups of its own.
