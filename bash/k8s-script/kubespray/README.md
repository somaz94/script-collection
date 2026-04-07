# Kubespray Management Scripts

Scripts for managing Kubernetes clusters deployed with [Kubespray](https://github.com/kubernetes-sigs/kubespray).

<br/>

## Scripts

| Script | Run Location | Description |
|--------|-------------|-------------|
| `config.env` | - | Shared configuration (user, IP, paths) |
| `check-version.sh` | Local machine | Version check, compatibility matrix, inventory sync |
| `upgrade-kubespray.sh` | Control plane | Kubespray tag switch with config diff and backup |
| `post-upgrade-check.sh` | Local machine | Post-upgrade health check (9 items) |

<br/>

## Setup

1. Copy `config.env` and update with your cluster info:

```bash
vi config.env
# Set: CONTROL_PLANE_USER, CONTROL_PLANE_HOST, INVENTORY_NAME, CLUSTER_NODES, etc.
```

2. Make scripts executable:

```bash
chmod +x *.sh
```

<br/>

## Usage

### Version Check

```bash
./check-version.sh              # Full check
./check-version.sh --k8s        # K8s cluster only
./check-version.sh --supported  # Supported K8s versions from checksums
./check-version.sh --kubespray  # Kubespray version + latest tags
./check-version.sh --sync       # Sync inventory from control plane
./check-version.sh -h           # Help
```

### Kubespray Upgrade (copy to control plane first)

```bash
scp upgrade-kubespray.sh user@control-plane:~/kubespray/scripts/

# On control plane
./upgrade-kubespray.sh --check              # Pre-flight check
./upgrade-kubespray.sh --diff-only          # Config diff only
./upgrade-kubespray.sh --target v2.30.0     # Upgrade to specific version
./upgrade-kubespray.sh                      # Interactive upgrade
```

### Post-Upgrade Health Check

```bash
./post-upgrade-check.sh           # Full check (9 items)
./post-upgrade-check.sh --quick   # Quick check (nodes + pods)
```

Checks: Node status, version consistency, pod health, system components, DNS, certificates, containerd registry, etcd, API server.

<br/>

## Environment Variable Override

```bash
# Override without editing config.env
CONTROL_PLANE_USER=admin CONTROL_PLANE_HOST=192.168.1.100 ./check-version.sh
EXPECTED_NODES=6 ./post-upgrade-check.sh
```
