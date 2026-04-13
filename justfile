# hpc-dev-cluster justfile
# Run `just` to see available commands.
# First-time setup: `just bootstrap` installs just itself system-wide.

set dotenv-load  # auto-load variables.env

VMRUN        := env_var("VMRUN")
VDISKMANAGER := env_var("VDISKMANAGER")
VM_BASE_WSL  := env_var("VM_BASE_WSL")
ISO_LOCAL    := env_var("ISO_LOCAL")
ISO_URL      := env_var("ISO_URL")

HEAD_VMX  := VM_BASE_WSL / "hpc-dev-head/hpc-dev-head.vmx"
CPU01_VMX := VM_BASE_WSL / "hpc-dev-cpu01/hpc-dev-cpu01.vmx"
CPU02_VMX := VM_BASE_WSL / "hpc-dev-cpu02/hpc-dev-cpu02.vmx"

# ── Bootstrap ────────────────────────────────────────────────────────────────

# Install just (if not present) to ~/.local/bin and show available recipes
bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    export PATH="$HOME/.local/bin:$PATH"
    if ! command -v just &>/dev/null; then
        echo ">>> Installing just to ~/.local/bin ..."
        curl --proto '=https' --tlsv1.2 -sSf \
            https://just.systems/install.sh | bash -s -- --to ~/.local/bin
        echo ">>> just installed: $(just --version)"
        echo ">>> Add to shell: echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
    else
        echo ">>> just already installed: $(just --version)"
    fi
    just --list

# ── ISO ──────────────────────────────────────────────────────────────────────

# Download Rocky Linux 10.1 boot ISO (skip if already present)
iso-download:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -f "{{ISO_LOCAL}}" ]; then
        echo ">>> ISO already present: {{ISO_LOCAL}}"
    else
        mkdir -p "$(dirname "{{ISO_LOCAL}}")"
        wget -c "{{ISO_URL}}" -O "{{ISO_LOCAL}}" --progress=bar:force
        echo ">>> Download complete."
    fi

# ── VMDK ─────────────────────────────────────────────────────────────────────

# Create all VM disk images (idempotent — skips if VMDK already exists)
disks-create: _disk-head _disk-cpu01 _disk-cpu02

_disk-head:
    #!/usr/bin/env bash
    set -euo pipefail
    VMDK="{{VM_BASE_WSL}}/hpc-dev-head/hpc-dev-head.vmdk"
    if [ -f "$VMDK" ]; then echo ">>> head VMDK exists, skipping."; exit 0; fi
    mkdir -p "$(dirname "$VMDK")"
    "{{VDISKMANAGER}}" -c -s 160GB -a lsilogic -t 0 \
        "C:\\Users\\nooob\\Documents\\Virtual Machines\\hpc-dev-head\\hpc-dev-head.vmdk"

_disk-cpu01:
    #!/usr/bin/env bash
    set -euo pipefail
    VMDK="{{VM_BASE_WSL}}/hpc-dev-cpu01/hpc-dev-cpu01.vmdk"
    if [ -f "$VMDK" ]; then echo ">>> cpu01 VMDK exists, skipping."; exit 0; fi
    mkdir -p "$(dirname "$VMDK")"
    "{{VDISKMANAGER}}" -c -s 16GB -a lsilogic -t 0 \
        "C:\\Users\\nooob\\Documents\\Virtual Machines\\hpc-dev-cpu01\\hpc-dev-cpu01.vmdk"

_disk-cpu02:
    #!/usr/bin/env bash
    set -euo pipefail
    VMDK="{{VM_BASE_WSL}}/hpc-dev-cpu02/hpc-dev-cpu02.vmdk"
    if [ -f "$VMDK" ]; then echo ">>> cpu02 VMDK exists, skipping."; exit 0; fi
    mkdir -p "$(dirname "$VMDK")"
    "{{VDISKMANAGER}}" -c -s 16GB -a lsilogic -t 0 \
        "C:\\Users\\nooob\\Documents\\Virtual Machines\\hpc-dev-cpu02\\hpc-dev-cpu02.vmdk"

# ── VMX deploy ───────────────────────────────────────────────────────────────

# Copy VMX files from repo into the VMware VM directories
deploy: _deploy-head _deploy-cpu01 _deploy-cpu02
    @echo ">>> All VMX files deployed."

_deploy-head:
    cp vmware/hpc-dev-head/hpc-dev-head.vmx "{{VM_BASE_WSL}}/hpc-dev-head/hpc-dev-head.vmx"
    @echo ">>> hpc-dev-head.vmx deployed."

_deploy-cpu01:
    cp vmware/hpc-dev-cpu01/hpc-dev-cpu01.vmx "{{VM_BASE_WSL}}/hpc-dev-cpu01/hpc-dev-cpu01.vmx"
    @echo ">>> hpc-dev-cpu01.vmx deployed."

_deploy-cpu02:
    cp vmware/hpc-dev-cpu02/hpc-dev-cpu02.vmx "{{VM_BASE_WSL}}/hpc-dev-cpu02/hpc-dev-cpu02.vmx"
    @echo ">>> hpc-dev-cpu02.vmx deployed."

# ── Full provision (first-time setup) ────────────────────────────────────────

# First-time: download ISO, create disks, deploy VMX files
provision: iso-download disks-create deploy
    @echo ">>> Cluster provisioned. Start hpc-dev-head to begin OS installation."

# ── VM lifecycle ─────────────────────────────────────────────────────────────

# Start head node (GUI)
start-head:
    "{{VMRUN}}" start "{{HEAD_VMX}}" gui

# Start compute nodes (GUI)
start-nodes:
    "{{VMRUN}}" start "{{CPU01_VMX}}" gui
    "{{VMRUN}}" start "{{CPU02_VMX}}" gui

# Start all VMs
start-all: start-head start-nodes

# Stop all VMs gracefully
stop-all:
    -"{{VMRUN}}" stop "{{HEAD_VMX}}"  soft
    -"{{VMRUN}}" stop "{{CPU01_VMX}}" soft
    -"{{VMRUN}}" stop "{{CPU02_VMX}}" soft

# Show running VMs
status:
    "{{VMRUN}}" list

# ── Snapshot ─────────────────────────────────────────────────────────────────

# Take a named snapshot of all VMs  (usage: just snapshot "after-ww-install")
snapshot name:
    "{{VMRUN}}" snapshot "{{HEAD_VMX}}"  "{{name}}"
    "{{VMRUN}}" snapshot "{{CPU01_VMX}}" "{{name}}"
    "{{VMRUN}}" snapshot "{{CPU02_VMX}}" "{{name}}"
    @echo ">>> Snapshot '{{name}}' taken on all VMs."

# List snapshots for all VMs
snapshot-list:
    @echo "=== hpc-dev-head ==="
    "{{VMRUN}}" listSnapshots "{{HEAD_VMX}}"
    @echo "=== hpc-dev-cpu01 ==="
    "{{VMRUN}}" listSnapshots "{{CPU01_VMX}}"
    @echo "=== hpc-dev-cpu02 ==="
    "{{VMRUN}}" listSnapshots "{{CPU02_VMX}}"
