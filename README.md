# hpc-dev-cluster

Infrastructure-as-Code for a local VMware Workstation HPC development cluster
running **Warewulf v4** + **Slurm** on **Rocky Linux 10**.

## Cluster layout

| Node | Role | CPU | RAM | Disk | Network |
|---|---|---|---|---|---|
| hpc-dev-head | Head / controller | 2 vCPU | 8 GB | 160 GB | NIC1: Bridged (campus), NIC2: hpc-lan |
| hpc-dev-cpu01 | Compute (PXE) | 2 vCPU | 8 GB | 16 GB | hpc-lan only |
| hpc-dev-cpu02 | Compute (PXE) | 2 vCPU | 8 GB | 16 GB | hpc-lan only |

**hpc-lan** is a VMware LAN Segment (isolated, no host DHCP).
Warewulf on the head node provides DHCP + TFTP + PXE for compute nodes.

## Repository structure

```
hpc-dev-cluster/
├── justfile            # all lifecycle commands (deploy, start, snapshot …)
├── variables.env       # shared parameters — edit here to customise
├── vmware/
│   ├── hpc-dev-head/
│   │   └── hpc-dev-head.vmx
│   ├── hpc-dev-cpu01/
│   │   └── hpc-dev-cpu01.vmx
│   └── hpc-dev-cpu02/
│       └── hpc-dev-cpu02.vmx
└── docs/               # setup notes, network diagrams, etc.
```

VMDKs, snapshots, logs, and ISOs are **not** tracked (see `.gitignore`).

## Prerequisites

- VMware Workstation (≥ 17) on Windows with WSL 2
- WSL shell with `curl`, `wget`, `git`
- `just` — installed automatically by `just bootstrap`

## Quick start

```bash
# 1. Clone
git clone https://github.com/nooobkevin/hpc-dev-cluster.git
cd hpc-dev-cluster

# 2. Install just and verify recipes
bash -c "$(curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh)" -- --to ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"
just bootstrap

# 3. First-time provision (ISO download + VMDK creation + VMX deploy)
just provision

# 4. Start the head node and install Rocky Linux
just start-head
```

## Common commands

```bash
just status           # list running VMs
just start-all        # start all three VMs
just stop-all         # graceful shutdown
just deploy           # re-deploy VMX files after editing
just snapshot "label" # snapshot all VMs
just snapshot-list    # list all snapshots
```

## Network

```
Campus network (Bridged)
        │
   [hpc-dev-head]
   NIC1: DHCP from campus
   NIC2: 192.168.100.1/24 ─── hpc-lan (LAN Segment) ───┬─ [hpc-dev-cpu01]
                                                         └─ [hpc-dev-cpu02]
```

Warewulf assigns static IPs to compute nodes via MAC-based DHCP on hpc-lan.
