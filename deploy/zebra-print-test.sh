#!/usr/bin/env bash
# Send deploy/zebra-test.zpl to a CUPS queue (ZPL needs a raw / pass-through queue).
#
# Prereqs on Ubuntu:
#   sudo apt update && sudo apt install -y cups cups-client
#   USB (default): plug in ZD420, add printer at http://127.0.0.1:631/ (raw / pass-through ZPL)
#   lpinfo needs root on many systems: sudo lpinfo -v | grep -i zebra
#   Ethernet (JetDirect 9100): bash deploy/setup-zebra-ethernet-cups.sh or socket://<ip>:9100 in CUPS
#
# Usage:
#   bash deploy/zebra-print-test.sh              # lists queues, needs ZEBRA_QUEUE or arg
#   bash deploy/zebra-print-test.sh Zebra_ZD420
#   ZEBRA_QUEUE=MyPrinter bash deploy/zebra-print-test.sh
#
# If copied from Windows and you see $'\r': command not found:
#   sed -i 's/\r$//' deploy/zebra-print-test.sh
#
# If lp says unknown option "raw", try:
#   lp -d "$QUEUE" -o document-format=application/octet-stream "$ZPL"

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZPL="${ROOT}/deploy/zebra-test.zpl"

if ! command -v lp >/dev/null 2>&1; then
  echo "Install CUPS client tools: sudo apt install -y cups cups-client"
  exit 1
fi

if [[ ! -f "$ZPL" ]]; then
  echo "Missing ZPL file: $ZPL"
  exit 1
fi

QUEUE="${1:-${ZEBRA_QUEUE:-}}"

if [[ -z "$QUEUE" ]]; then
  echo "Set a CUPS queue name. Examples:"
  echo "  bash deploy/zebra-print-test.sh YourQueueName"
  echo "  ZEBRA_QUEUE=YourQueueName bash deploy/zebra-print-test.sh"
  echo ""
  echo "Known printers (lpstat -p):"
  lpstat -p 2>/dev/null || echo "(none — add a printer in CUPS first)"
  echo ""
  echo "Discovered backends (sudo lpinfo -v; USB often usb://Zebra/...):"
  sudo lpinfo -v 2>/dev/null | grep -iE 'usb://|socket://|ipp://|zebra' || sudo lpinfo -v 2>/dev/null | head -20 || true
  exit 1
fi

echo "Sending $ZPL to queue: $QUEUE"
if lp -d "$QUEUE" -o raw "$ZPL" 2>/dev/null; then
  echo "Job submitted. Check printer output (and: lpstat -o)"
  exit 0
fi

echo "Retrying without -o raw (some queues ignore it)..."
lp -d "$QUEUE" "$ZPL"
echo "Job submitted. Check printer output (and: lpstat -o)"
