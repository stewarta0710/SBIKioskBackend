#!/usr/bin/env bash
# Run on Ubuntu from the project root as your SSH user (not root).
# Usage: bash deploy/install-server.sh
# This script uses sudo for /var/lib, systemd, and systemctl.
#
# If anything under this tree is root-owned (e.g. copied with sudo), fix first:
#   sudo chown -R "$USER:$USER" ~/visitor-kiosk
#
# If the script came from Windows and bash reports $'\r' errors, fix line endings:
#   sudo sed -i 's/\r$//' deploy/install-server.sh

set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run as your normal login user (e.g. sbikioskbackend), not root."
  echo "This script calls sudo where needed."
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -w "$ROOT" || ! -w "$ROOT/deploy" ]]; then
  echo "This directory is not writable (often root-owned files after scp)."
  echo "Run:"
  echo "  sudo chown -R \"${USER}:${USER}\" \"${ROOT}\""
  echo "Then: bash deploy/install-server.sh"
  exit 1
fi

if ! command -v python3 >/dev/null; then
  echo "Install Python first: sudo apt update && sudo apt install -y python3 python3-venv python3-pip"
  exit 1
fi

echo "==> venv + dependencies"
python3 -m venv venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install -r requirements.txt

DATA_ROOT="/var/lib/visitor-kiosk"
SERVICE_NAME="visitor-kiosk"
RUN_AS="$USER"

echo "==> data directory ${DATA_ROOT}"
sudo mkdir -p "$DATA_ROOT"
sudo chown "${RUN_AS}:${RUN_AS}" "$DATA_ROOT"

UVICORN="${ROOT}/venv/bin/uvicorn"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

echo "==> systemd unit -> ${UNIT_PATH}"
UNIT_TMP="$(mktemp)"
trap 'rm -f "$UNIT_TMP"' EXIT
cat >"$UNIT_TMP" <<EOF
[Unit]
Description=Visitor Kiosk (FastAPI)
After=network.target

[Service]
Type=simple
User=${RUN_AS}
Group=${RUN_AS}
WorkingDirectory=${ROOT}
Environment=VISITOR_DATA_DIR=${DATA_ROOT}
ExecStart=${UVICORN} app.main:app --host 0.0.0.0 --port 8000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo cp "$UNIT_TMP" "$UNIT_PATH"
sudo systemctl daemon-reload
sudo systemctl enable --now "${SERVICE_NAME}"

echo "==> done. Status:"
sudo systemctl status "${SERVICE_NAME}" --no-pager || true
echo ""
echo "On this machine: http://127.0.0.1:8000"
echo "From another PC (Tailscale): http://<this-host-Tailscale-IP>:8000"
echo ""
echo "Use sudo for service admin and logs:"
echo "  sudo journalctl -u ${SERVICE_NAME} -f"
echo "  sudo systemctl restart ${SERVICE_NAME}"
echo "  sudo systemctl status ${SERVICE_NAME}"
echo "If ufw is on: sudo ufw allow 8000/tcp && sudo ufw reload"
echo ""
echo "Optional Power Automate (HTTP trigger): after save, POST JSON to a webhook URL."
echo "  sudo systemctl edit visitor-kiosk"
echo "  # In the override file, under [Service]:"
echo "  # URLs with %% (query params like %%2F) need DOUBLED percent signs — systemd treats %% as literal %."
echo "  # Or use EnvironmentFile=/etc/visitor-kiosk.env (see systemd.environment(7))."
echo "  # Environment=\"VISITOR_WEBHOOK_URL=https://...invoke?api-version=1&sp=%%2Ftriggers%%2Fmanual%%2Frun&sv=...&sig=...\""
echo "  sudo systemctl daemon-reload && sudo systemctl restart visitor-kiosk"
echo "  Debug webhook in curl JSON: Environment=VISITOR_DEBUG_RESPONSE=1 (turn off after testing)"
echo ""
echo "Zebra badge test (USB via CUPS): plug in printer, add queue at http://127.0.0.1:631/ (raw/ZPL), then:"
echo "  bash deploy/zebra-print-test.sh YourQueueName"
echo "Optional Ethernet (JetDirect): bash deploy/setup-zebra-ethernet-cups.sh"
echo "Print on submit: sudo systemctl edit visitor-kiosk"
echo "  # Environment=ZEBRA_CUPS_QUEUE=YourQueueName"
echo "  Badge media: default 4in x 3in @300dpi -> ZEBRA_ZPL_PW=1200 ZEBRA_ZPL_LL=900"
echo "  Optional: ZEBRA_CONTENT_OFFSET_IN (default 0.5) shifts all text down; ZEBRA_MARGIN_TOP inner padding"
echo "  Optional: ZEBRA_LABEL_WIDTH_IN / ZEBRA_LABEL_HEIGHT_IN / ZEBRA_DPI (or ZEBRA_ZPL_PW / LL in dots)"
echo "  Optional: ZEBRA_FONT_* / ZEBRA_GAP_* / ZEBRA_FB_MAX_LINES (wrap lines, default 2 on short labels)"
echo "  Optional: ZEBRA_HOST_CAPTION_TEXT / ZEBRA_TIMEZONE (IANA, default America/New_York)"
