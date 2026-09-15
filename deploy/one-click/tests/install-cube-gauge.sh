#!/usr/bin/env bash
# Build cube_gauge.ko against the guest kernel that toolbox vmlinux came from,
# pack cube_gauge.ext4, copy it next to that vmlinux.
#
#   sudo bash deploy/one-click/tests/install-cube-gauge.sh
#
# Needs the kernel *tree* that produced the vmlinux (not the ELF alone).
# PVM default: deploy/pvm/pvm-guest-build/linux. Override with KDIR=.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
KERNEL_DIR="${CUBE_KERNEL_DIR:-/usr/local/services/cubetoolbox/cube-kernel-scf}"
VMLINUX="${KERNEL_DIR}/vmlinux"
DEST="${KERNEL_DIR}/cube_gauge.ext4"
PVM_TREE="${ROOT_DIR}/deploy/pvm/pvm-guest-build/linux"
PACK="${ROOT_DIR}/deploy/guest-modules/pack-cube-gauge-ext4.sh"

log() { printf '[cube-gauge] %s\n' "$*"; }
die() { printf '[cube-gauge] ERROR: %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "run as root"
[[ -e "${VMLINUX}" ]] || die "missing ${VMLINUX}"
[[ -x "${PACK}" || -f "${PACK}" ]] || die "missing ${PACK}"

KDIR="${KDIR:-}"
if [[ -z "${KDIR}" ]]; then
  target="$(readlink "${VMLINUX}" 2>/dev/null || true)"
  if [[ "${target}" == "vmlinux-pvm" && -d "${PVM_TREE}" ]]; then
    KDIR="${PVM_TREE}"
  else
    die "set KDIR to the kernel tree that built ${VMLINUX}"
  fi
fi

log "pairing toolbox ${VMLINUX} with KDIR=${KDIR}"
KDIR="${KDIR}" \
  PAIR_VMLINUX="${VMLINUX}" \
  OUTPUT="${DEST}" \
  bash "${PACK}"
