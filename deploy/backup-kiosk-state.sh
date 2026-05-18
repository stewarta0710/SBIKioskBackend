#!/usr/bin/env bash
# Snapshot visitor-kiosk data + service/printer hints for off-box backup (e.g. NAS mount).
#
# Usage:
#   BACKUP_DEST=/mnt/nas/visitor-kiosk-backup bash deploy/backup-kiosk-state.sh
#   bash deploy/backup-kiosk-state.sh /mnt/nas/visitor-kiosk-backup
#
# Optional:
#   VISITOR_DATA_DIR   default /var/lib/visitor-kiosk
#   BACKUP_KEEP_LAST   if set (e.g. 30), delete older visitor-kiosk-data-*.tar.gz in BACKUP_DEST
#
# Run as a user that can read VISITOR_DATA_DIR (the kiosk service user is ideal).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BACKUP_DEST="${BACKUP_DEST:-${1:-}}"
if [[ -z "${BACKUP_DEST}" ]]; then
  echo "Set BACKUP_DEST or pass a directory path, e.g.:"
  echo "  BACKUP_DEST=/mnt/nas/visitor-kiosk-backup bash deploy/backup-kiosk-state.sh"
  exit 1
fi

DATA_ROOT="${VISITOR_DATA_DIR:-/var/lib/visitor-kiosk}"
if [[ ! -d "$DATA_ROOT" ]]; then
  echo "Data directory missing or not a directory: ${DATA_ROOT}"
  exit 1
fi
if [[ ! -r "$DATA_ROOT" ]]; then
  echo "Cannot read ${DATA_ROOT} (run as the service user or fix permissions)."
  exit 1
fi

mkdir -p "$BACKUP_DEST"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="${BACKUP_DEST}/visitor-kiosk-data-${STAMP}.tar.gz"

echo "==> archiving ${DATA_ROOT} -> ${ARCHIVE}"
tar -czf "$ARCHIVE" -C "$(dirname "$DATA_ROOT")" "$(basename "$DATA_ROOT")"

echo "==> systemd snapshot -> ${BACKUP_DEST}/systemd-visitor-kiosk-${STAMP}.txt"
systemctl cat visitor-kiosk >"${BACKUP_DEST}/systemd-visitor-kiosk-${STAMP}.txt" 2>&1 || true

echo "==> CUPS printers (lpstat) -> ${BACKUP_DEST}/cups-lpstat-${STAMP}.txt"
if command -v lpstat >/dev/null 2>&1; then
  lpstat -p >"${BACKUP_DEST}/cups-lpstat-${STAMP}.txt" 2>&1 || true
else
  echo "lpstat not installed" >"${BACKUP_DEST}/cups-lpstat-${STAMP}.txt"
fi

if [[ -n "${BACKUP_KEEP_LAST:-}" ]]; then
  echo "==> pruning old data archives (keep last ${BACKUP_KEEP_LAST})"
  mapfile -t _old < <(ls -1t "${BACKUP_DEST}"/visitor-kiosk-data-*.tar.gz 2>/dev/null | tail -n +"$((BACKUP_KEEP_LAST + 1))" || true)
  if ((${#_old[@]} > 0)); then
    rm -f "${_old[@]}"
  fi
fi

echo "==> done"
ls -la "$ARCHIVE"
