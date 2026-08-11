<!--
SPDX-FileCopyrightText: Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
SPDX-License-Identifier: Apache-2.0
-->

# Mooncake Master on Kubernetes (no rebuild)

Deploy the Mooncake store **master** for PD-disaggregated serving on Kubernetes
using the **stock** `mx-vllm-runtime` image — no custom image build required.

## TL;DR

- The `k8s` HA backend (`--ha_backend_type=k8s`) is a **non-functional, unmerged
  upstream RFC**. It is listed in `mooncake_master --help` but aborts at runtime
  ("k8s backend does not exist"). **Rebuilding the image cannot fix this** — the
  code is not present.
- You do **not** need it. **etcd** and **redis** HA are already compiled into the
  stock `mooncake_master` binary. HA is wired up entirely through the container
  `command`/`args` — **no rebuild, ever**, for single or HA mode.
- Dynamo's `--discovery-backend kubernetes` is a **separate** codebase from
  Mooncake's HA backend; Dynamo being k8s-native does not give Mooncake k8s-native
  HA. Mooncake HA still uses etcd or redis.

## Which manifest

| File | Mode | HA | etcd/redis | Client `MOONCAKE_MASTER` |
|------|------|----|------------|--------------------------|
| [`mooncake-master-single.yaml`](./mooncake-master-single.yaml) | Single (`--enable_ha=false`) | No — K8s restarts the pod | Not needed | `mooncake-master:50051` |
| [`mooncake-master.yaml`](./mooncake-master.yaml) | HA (`--enable_ha=true`) | Yes — 3 masters, etcd/redis lease | Required | `etcd://<svc>.<ns>.svc.cluster.local:2379` |
| [`etcd-statefulset.yaml`](./etcd-statefulset.yaml) | Optional dedicated etcd | — | Provides etcd | — |

## Single master (simplest)

```bash
kubectl apply -f mooncake-master-single.yaml
```

Client (mooncake store) env — static address, **not** `etcd://`:

```bash
export MOONCAKE_MASTER="mooncake-master:50051"
export MOONCAKE_TE_META_DATA_SERVER="P2PHANDSHAKE"
```

## HA master (reuse the cluster's existing etcd)

If Dynamo/LMCache already run etcd at `<svc>.<namespace>.svc.cluster.local:2379`,
reuse it — do **not** stand up a new etcd, and do **not** use the control-plane
(kube-system) etcd. Set `--etcd_endpoints` to that DNS and give Mooncake a
distinct `--cluster_id` so its keyspace is isolated from the other tenants.

Edit `mooncake-master.yaml` `--etcd_endpoints` to your real etcd Service, then:

```bash
kubectl apply -f mooncake-master.yaml
```

Client env in HA mode:

```bash
export MOONCAKE_MASTER="etcd://<svc>.<namespace>.svc.cluster.local:2379"
export MOONCAKE_TE_META_DATA_SERVER="etcd://<svc>.<namespace>.svc.cluster.local:2379"   # or P2PHANDSHAKE
```

Verify etcd reachability (optional):

```bash
etcdctl --endpoints=<svc>.<namespace>.svc.cluster.local:2379 endpoint health
```

If you have **no** reusable etcd, apply `etcd-statefulset.yaml` first and point
`--etcd_endpoints=mooncake-etcd:2379`.

Redis instead of etcd — swap the etcd args in `mooncake-master.yaml` for:

```yaml
- "--ha_backend_type=redis"
- "--ha_backend_connstring=redis://dynamo-redis:6379"
```

## Master flag reference

| Flag | Meaning | Default |
|------|---------|---------|
| `--enable_ha` | Enable HA (etcd/redis lease election) | `false` |
| `--etcd_endpoints` | `;`-separated `host:port` etcd endpoints | — |
| `--rpc_address` | Address advertised to clients via etcd (use pod IP in HA) | `0.0.0.0` |
| `--ha_backend_type` | `etcd` \| `redis` \| ~~`k8s`~~ (k8s is non-functional) | `etcd` |
| `--ha_backend_connstring` | Backend connection string (falls back to `etcd_endpoints`) | — |
| `--cluster_id` | Keyspace isolation in a shared backend | `mooncake_cluster` |
| gRPC/RPC port | Master service port | `50051` |

## Notes

- **seccomp:** the native `mooncake_master` trips Docker's *default* seccomp on a
  local `docker run` (needs `--security-opt seccomp=unconfined` locally). Under
  Kubernetes `RuntimeDefault` it runs fine — no action needed on-cluster.
- **Non-HA is not data loss:** store data lives on the Mooncake store nodes, not
  the master. A master restart is a brief metadata blip.
