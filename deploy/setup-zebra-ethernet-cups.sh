#!/usr/bin/env bash
# Optional: LAN / JetDirect queue. For USB, add the printer at http://127.0.0.1:631/ instead.
#
# Create or replace a CUPS queue for a Zebra on the LAN (raw ZPL over JetDirect port 9100).
# Run on the kiosk server (Ubuntu) with sudo. From repo root:
#   bash deploy/setup-zebra-ethernet-cups.sh
#   bash deploy/setup-zebra-ethernet-cups.sh 192.168.1.4 Zebra_Kiosk
#
# If line endings break execution after copying from Windows:
#   sed -i 's/\r$//' deploy/setup-zebra-ethernet-cups.sh
#
# After this, point the app at the queue name:
#   sudo systemctl edit visitor-kiosk
#   # [Service]
#   # Environment=ZEBRA_CUPS_QUEUE=Zebra_Kiosk
#   sudo systemctl daemon-reload && sudo systemctl restart visitor-kiosk
#
# Prereq: sudo apt install -y cups cups-client

set -euo pipefail

PRINTER_IP="${1:-192.168.1.4}"
QUEUE_NAME="${2:-Zebra_Kiosk}"
URI="socket://${PRINTER_IP}:9100"

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run as a normal user; this script invokes sudo where needed."
  exit 1
fi

if ! command -v lpadmin >/dev/null 2>&1; then
  echo "Install CUPS: sudo apt update && sudo apt install -y cups cups-client"
  exit 1
fi

echo "==> CUPS queue ${QUEUE_NAME} -> ${URI} (raw ZPL)"

sudo lpadmin -x "$QUEUE_NAME" 2>/dev/null || true

if sudo lpadmin -p "$QUEUE_NAME" -E -v "$URI" -m raw 2>/dev/null; then
  echo "Using PPD model: raw"
elif sudo lpadmin -p "$QUEUE_NAME" -E -v "$URI" -m drv:///sample.drv/generic.ppd 2>/dev/null; then
  echo "Using PPD model: drv:///sample.drv/generic.ppd (if ZPL is corrupted, add queue via http://127.0.0.1:631/ as Raw)"
else
  echo "lpadmin failed on this OS/CUPS build."
  echo "Add manually: http://127.0.0.1:631/ -> Administration -> Add Printer"
  echo "  Connection / URI: ${URI}"
  echo "  Driver: Raw queue or Generic / pass-through so ZPL is not filtered."
  exit 1
fi

sudo cupsenable "$QUEUE_NAME" 2>/dev/null || true
sudo accept "$QUEUE_NAME" 2>/dev/null || true

echo ""
echo "==> Done. Test print:"
echo "  ZEBRA_QUEUE=${QUEUE_NAME} bash deploy/zebra-print-test.sh"
echo ""
echo "==> visitor-kiosk service (submit path):"
echo "  Environment=ZEBRA_CUPS_QUEUE=${QUEUE_NAME}"
