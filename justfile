# hpc-dev-cluster justfile
# Run `just` to see available commands.
# First-time setup: `just bootstrap` installs just itself system-wide.

set dotenv-load
set dotenv-filename := "variables.env"

VMRUN        := env_var("VMRUN")
VMWARE_GUI   := env_var("VMWARE_BIN") + "/vmware.exe"
VDISKMANAGER := env_var("VDISKMANAGER")
VM_BASE_WSL  := env_var("VM_BASE_WSL")
ISO_LOCAL    := env_var("ISO_LOCAL")
ISO_URL      := env_var("ISO_URL")

# WSL paths — used for file operations (cp, ls, test -d …)
HEAD_VMX_WSL  := VM_BASE_WSL / "hpc-dev-head/hpc-dev-head.vmx"
CPU01_VMX_WSL := VM_BASE_WSL / "hpc-dev-cpu01/hpc-dev-cpu01.vmx"
CPU02_VMX_WSL := VM_BASE_WSL / "hpc-dev-cpu02/hpc-dev-cpu02.vmx"

# Windows paths — converted at recipe time via: wslpath -w "<wsl-path>"

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
    VMDK_WSL="{{VM_BASE_WSL}}/hpc-dev-head/hpc-dev-head.vmdk"
    if [ -f "$VMDK_WSL" ]; then echo ">>> head VMDK exists, skipping."; exit 0; fi
    mkdir -p "$(dirname "$VMDK_WSL")"
    "{{VDISKMANAGER}}" -c -s 160GB -a lsilogic -t 0 \
        "$(wslpath -w "$VMDK_WSL")"

_disk-cpu01:
    #!/usr/bin/env bash
    set -euo pipefail
    VMDK_WSL="{{VM_BASE_WSL}}/hpc-dev-cpu01/hpc-dev-cpu01.vmdk"
    if [ -f "$VMDK_WSL" ]; then echo ">>> cpu01 VMDK exists, skipping."; exit 0; fi
    mkdir -p "$(dirname "$VMDK_WSL")"
    "{{VDISKMANAGER}}" -c -s 16GB -a lsilogic -t 0 \
        "$(wslpath -w "$VMDK_WSL")"

_disk-cpu02:
    #!/usr/bin/env bash
    set -euo pipefail
    VMDK_WSL="{{VM_BASE_WSL}}/hpc-dev-cpu02/hpc-dev-cpu02.vmdk"
    if [ -f "$VMDK_WSL" ]; then echo ">>> cpu02 VMDK exists, skipping."; exit 0; fi
    mkdir -p "$(dirname "$VMDK_WSL")"
    "{{VDISKMANAGER}}" -c -s 16GB -a lsilogic -t 0 \
        "$(wslpath -w "$VMDK_WSL")"

# ── VMX deploy ───────────────────────────────────────────────────────────────

# Copy VMX files from repo into the VMware VM directories
deploy: _deploy-head _deploy-cpu01 _deploy-cpu02
    @echo ">>> All VMX files deployed."

_deploy-head:
    cp vmware/hpc-dev-head/hpc-dev-head.vmx "{{HEAD_VMX_WSL}}"
    @echo ">>> hpc-dev-head.vmx deployed."

_deploy-cpu01:
    cp vmware/hpc-dev-cpu01/hpc-dev-cpu01.vmx "{{CPU01_VMX_WSL}}"
    @echo ">>> hpc-dev-cpu01.vmx deployed."

_deploy-cpu02:
    cp vmware/hpc-dev-cpu02/hpc-dev-cpu02.vmx "{{CPU02_VMX_WSL}}"
    @echo ">>> hpc-dev-cpu02.vmx deployed."

# ── Full provision (first-time setup) ────────────────────────────────────────

# First-time: download ISO, create disks, deploy VMX files
provision: iso-download disks-create deploy
    @echo ">>> Cluster provisioned. Start hpc-dev-head to begin OS installation."

# ── VM lifecycle ─────────────────────────────────────────────────────────────

# Start head node — opens VMware Workstation GUI in user session
start-head:
    #!/usr/bin/env bash
    set -euo pipefail
    VMX="{{HEAD_VMX_WSL}}"
    if [ -d "${VMX}.lck" ]; then
        echo ">>> hpc-dev-head is already running (lock file present), skipping."
        exit 0
    fi
    WIN_VMX="$(wslpath -w "$VMX")"
    # Use explorer.exe to open the VMX — guaranteed to open in the current user desktop session
    explorer.exe "$WIN_VMX" &
    disown
    echo ">>> hpc-dev-head: VMware Workstation opening..."

# Start compute nodes — opens VMware Workstation GUI in user session
start-nodes:
    #!/usr/bin/env bash
    set -euo pipefail
    for VMX in "{{CPU01_VMX_WSL}}" "{{CPU02_VMX_WSL}}"; do
        NAME=$(basename "$VMX" .vmx)
        if [ -d "${VMX}.lck" ]; then
            echo ">>> $NAME is already running (lock file present), skipping."
        else
            WIN_VMX="$(wslpath -w "$VMX")"
            explorer.exe "$WIN_VMX" &
            disown
            echo ">>> $NAME: VMware Workstation opening..."
        fi
    done

# Start all VMs
start-all: start-head start-nodes

# Stop all VMs gracefully
stop-all:
    #!/usr/bin/env bash
    "{{VMRUN}}" stop "$(wslpath -w "{{HEAD_VMX_WSL}}")"  soft || true
    "{{VMRUN}}" stop "$(wslpath -w "{{CPU01_VMX_WSL}}")" soft || true
    "{{VMRUN}}" stop "$(wslpath -w "{{CPU02_VMX_WSL}}")" soft || true

# Show VM status (lock-file based — vmrun list cannot track GUI-mode VMs)
status:
    #!/usr/bin/env bash
    echo "VM STATUS"
    echo "========="
    for VMX in "{{HEAD_VMX_WSL}}" "{{CPU01_VMX_WSL}}" "{{CPU02_VMX_WSL}}"; do
        NAME=$(basename "$VMX" .vmx)
        if [ -d "${VMX}.lck" ]; then
            echo "  [RUNNING]  $NAME"
        else
            echo "  [stopped]  $NAME"
        fi
    done

# ── Snapshot ─────────────────────────────────────────────────────────────────

# Take a named snapshot of all VMs  (usage: just snapshot "after-ww-install")
snapshot name:
    #!/usr/bin/env bash
    set -euo pipefail
    "{{VMRUN}}" snapshot "$(wslpath -w "{{HEAD_VMX_WSL}}")"  "{{name}}"
    "{{VMRUN}}" snapshot "$(wslpath -w "{{CPU01_VMX_WSL}}")" "{{name}}"
    "{{VMRUN}}" snapshot "$(wslpath -w "{{CPU02_VMX_WSL}}")" "{{name}}"
    echo ">>> Snapshot '{{name}}' taken on all VMs."

# List snapshots for all VMs
snapshot-list:
    #!/usr/bin/env bash
    echo "=== hpc-dev-head ==="
    "{{VMRUN}}" listSnapshots "$(wslpath -w "{{HEAD_VMX_WSL}}")"
    echo "=== hpc-dev-cpu01 ==="
    "{{VMRUN}}" listSnapshots "$(wslpath -w "{{CPU01_VMX_WSL}}")"
    echo "=== hpc-dev-cpu02 ==="
    "{{VMRUN}}" listSnapshots "$(wslpath -w "{{CPU02_VMX_WSL}}")"
