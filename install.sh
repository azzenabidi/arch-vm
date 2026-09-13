#!/usr/bin/env bash
set -euo pipefail

# Arch Linux learning VM — one-command installer.
#
#   curl -fsSL https://raw.githubusercontent.com/azzenabidi/arch-vm/main/install.sh | bash
#
# Downloads the verified Arch Linux live ISO, places the compose and launcher
# from this repo, and starts a KVM-accelerated VM so you can do the install
# by hand (no auto-installer).
#
# Override the install directory:
#   ARCH_VM_DIR=/tmp/my-arch-vm curl -fsSL ... | bash
#
# Download the ISO and start the container, but skip the VM start:
#   ARCH_NO_START=1 curl -fsSL ... | bash

REPO_RAW="https://raw.githubusercontent.com/azzenabidi/arch-vm/main"

BASE_DIR="${ARCH_VM_DIR:-${HOME}/arch-vm}"
STORAGE_DIR="${BASE_DIR}/arch"
SHARE_DIR="${BASE_DIR}/Arch"
ISO_PATH="${BASE_DIR}/archlinux-x86_64.iso"

ARCH_ISO_URL="${ARCH_ISO_URL:-https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso}"
CHECKSUMS_URL="https://geo.mirror.pkgbuild.com/iso/latest/sha256sums.txt"
NO_START="${ARCH_NO_START:-0}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log()  { printf "${GREEN}[*]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[!]${NC} %s\n" "$1" >&2; }
die()  { printf "${RED}[✗]${NC} %s\n" "$1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

command -v curl  >/dev/null 2>&1 || die "curl is required"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum (coreutils) is required"
command -v docker >/dev/null 2>&1 || die "docker is required (install docker or podman)"

[ -d /dev/kvm ] && log "KVM acceleration available" || warn "no /dev/kvm — VM will use slow TCG emulation"

# ---------------------------------------------------------------------------
# Docker helper — falls back to sudo/pkexec if the socket isn't reachable
# ---------------------------------------------------------------------------

docker_cmd() {
  if docker info >/dev/null 2>&1; then
    docker "$@"
  elif command -v pkexec >/dev/null 2>&1; then
    pkexec /usr/bin/docker "$@"
  else
    sudo docker "$@"
  fi
}

# ---------------------------------------------------------------------------
# Create layout
# ---------------------------------------------------------------------------

log "Setting up ${BASE_DIR}"
mkdir -p "${BASE_DIR}" "${STORAGE_DIR}" "${SHARE_DIR}"

# ---------------------------------------------------------------------------
# Download + verify the Arch Linux live ISO
# ---------------------------------------------------------------------------

download_iso() {
  log "Downloading ${ARCH_ISO_URL}"
  curl -fSL --progress-bar "${ARCH_ISO_URL}" -o "${ISO_PATH}"
}

verify_iso() {
  local expected got
  expected=$(curl -fsSL "${CHECKSUMS_URL}" | awk '/archlinux-x86_64\.iso/ {print $1}' | head -n1)
  [ -n "${expected}" ] || die "Failed to fetch expected checksum"
  got=$(sha256sum "${ISO_PATH}" | awk '{print $1}')
  if [ "${got}" = "${expected}" ]; then
    log "ISO checksum verified ✓"
    return 0
  else
    die "ISO checksum mismatch (got ${got}, expected ${expected}). Re-run to re-download."
  fi
}

if [ ! -s "${ISO_PATH}" ]; then
  download_iso
  verify_iso
else
  log "ISO already present, verifying..."
  verify_iso
fi

# ---------------------------------------------------------------------------
# Fetch compose + launcher from this repo
# ---------------------------------------------------------------------------

log "Fetching compose file"
curl -fsSL "${REPO_RAW}/docker-compose.yml" -o "${BASE_DIR}/docker-compose.yml"

log "Fetching launcher"
curl -fsSL "${REPO_RAW}/omarchy-arch-vm" -o "${BASE_DIR}/omarchy-arch-vm"
chmod +x "${BASE_DIR}/omarchy-arch-vm"

# ---------------------------------------------------------------------------
# Start the VM
# ---------------------------------------------------------------------------

if [ "${NO_START}" = "1" ]; then
  log "VM NOT started (ARCH_NO_START=1)"
  echo ""
  echo "  To start it later:"
  echo "    cd ${BASE_DIR} && ./omarchy-arch-vm launch"
  exit 0
fi

log "Starting the VM (polkit prompt may appear if Docker needs root)..."
docker_cmd compose -f "${BASE_DIR}/docker-compose.yml" up -d

log "Waiting for QEMU to boot..."
sleep 5

if ss -tln 2>/dev/null | grep -q ':8007'; then
  log "Web viewer ready — open http://127.0.0.1:8007"
else
  warn "Port 8007 not yet listening — try http://127.0.0.1:8007 in a few seconds"
fi

echo ""
echo "  Manage:   ${BASE_DIR}/omarchy-arch-vm launch|stop|restart|status"
echo "  Viewer:   http://127.0.0.1:8007"
echo "  Storage:  ${STORAGE_DIR}"
echo "  Shared:   ${SHARE_DIR}"
