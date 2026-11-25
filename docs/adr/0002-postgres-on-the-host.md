# PostgreSQL runs on the host, not in Kubernetes

- Status: accepted
- Date: 2026-11-25 (recording an earlier decision)

## Context

refinery, zero-cache, wger, and PowerSync need PostgreSQL. olympus is a single
8 GB node. Its local-path volumes are tied to the node name.

## Decision

NixOS runs one PostgreSQL instance on olympus. Pods reach it on the k3s bridge
address (10.42.0.1) through a Service and EndpointSlice per namespace. NixOS
declares the databases, roles, passwords (from SOPS), and logical replication.
It also sets up the PowerSync publication and zero-cache's event triggers,
which require superuser rights.

## Consequences

- Data outlives the cluster. Reinstalling k3s or losing cluster state leaves the
  databases untouched.
- Apps never hold superuser rights.
- One instance serves every app, which fits 8 GB better than running one per
  app. There is also no operator to run or upgrade.
- Major upgrades are deliberate. Dependency automation never merges a
  PostgreSQL major version.
- PostgreSQL sits outside GitOps and is only as safe as the host. It needs its
  own host backups.
