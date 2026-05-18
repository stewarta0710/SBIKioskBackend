# SBIKioskBackend

FastAPI backend for visitor check-in, optional badge printing via CUPS (Zebra ZPL), and optional Power Automate webhook on save.

Remote access (kiosk tablets, admin laptops, SSH, and deploy from Windows) uses **[Tailscale](https://tailscale.com/)** as a private VPN (tailnet). Every machine that must reach the backend or SSH into it **must have Tailscale installed and be signed into the same tailnet**.

## Networking with Tailscale

Tailscale connects your devices over an encrypted mesh. You do not need to expose port 8000 on the public internet; only devices on your tailnet can reach the kiosk API and SSH.

### Install Tailscale (required)

Install the client on **each** device that participates:

| Device | Install |
|--------|---------|
| **Linux backend server** | [Linux install](https://tailscale.com/download/linux) — then `sudo tailscale up` and approve the node in the [admin console](https://login.tailscale.com/admin/machines). |
| **Windows PC** (edit code, `scp`, SSH) | [Windows install](https://tailscale.com/download/windows) — sign in with the same tailnet account or an invited user. |
| **Kiosk tablet / phone** | [Android](https://tailscale.com/download/android) or [iOS](https://tailscale.com/download/ios) — same tailnet. The browser opens the sign-in page using the server’s Tailscale hostname below. |

After install, confirm the machine appears online in the Tailscale admin console. Use **MagicDNS** hostnames (e.g. `machine-name.tailXXXX.ts.net`) or the machine’s **100.x** Tailscale IP from that console.

### Production backend (example)

Replace with your node’s name/IP from the admin console if you rebuild the server:

| Field | Value |
|-------|--------|
| Tailscale machine name | `sbikioskbackend` |
| MagicDNS (preferred) | `sbikioskbackend.tail96d5df.ts.net` |
| Tailscale IPv4 | `100.70.199.32` |
| App URL (port 8000) | `http://sbikioskbackend.tail96d5df.ts.net:8000` |

**TLS:** Unless you configure HTTPS on the app, use **HTTP** on the MagicDNS hostname. Do not store Tailscale **auth keys** or node keys in this repository.

### Kiosk tablet

1. Install Tailscale on the tablet and sign into the **same tailnet**.
2. Open the visitor UI in the browser: **`http://sbikioskbackend.tail96d5df.ts.net:8000`** (or your server’s MagicDNS name / `100.x` IP).
3. Bookmark that URL on the kiosk home screen if your launcher supports it.

### SSH and deploy from Windows (over Tailscale)

SSH (PowerShell or Terminal):

```powershell
ssh sbikioskbackend@sbikioskbackend.tail96d5df.ts.net
```

Copy files after editing locally (from your clone of this repo):

```powershell
cd "C:\Users\stewa\OneDrive\Desktop\Courser AI projects\visitor-kiosk"
scp .\app\main.py .\app\schemas.py .\app\badge.py sbikioskbackend@sbikioskbackend.tail96d5df.ts.net:~/visitor-kiosk/app/
scp .\templates\index.html sbikioskbackend@sbikioskbackend.tail96d5df.ts.net:~/visitor-kiosk/templates/
scp .\static\css\style.css sbikioskbackend@sbikioskbackend.tail96d5df.ts.net:~/visitor-kiosk/static/css/
```

On the server after Python/template changes: `sudo systemctl restart visitor-kiosk`. CSS-only updates usually need a browser refresh on the tablet.

**Git alternative:** push from Windows, then on the server `cd ~/visitor-kiosk && git pull && sudo systemctl restart visitor-kiosk`.

---

## Server reinstall and setup

These steps assume **Ubuntu** (or similar) and a normal SSH user (not root). The install script uses `sudo` where needed. Install **Tailscale on the server first** (see above) so you can SSH and open the app from other devices.

### 1. Prerequisites

- **Tailscale** on the server and on every client that will use or administer the kiosk (see [Networking with Tailscale](#networking-with-tailscale)).
- `python3`, `python3-venv`, `python3-pip` (the install script will tell you if Python is missing).
- Git access to this repository (or copy the project tree to `~/visitor-kiosk`).

### 2. Install application and service

```bash
cd ~
git clone https://github.com/stewarta0710/SBIKioskBackend.git visitor-kiosk
cd ~/visitor-kiosk
bash deploy/install-server.sh
```

This will:

- Create a Python virtualenv and install `requirements.txt`.
- Create **`/var/lib/visitor-kiosk`** and set ownership to your login user (application data directory).
- Install and start the **`visitor-kiosk`** systemd service listening on **port 8000**.

Check status:

```bash
sudo systemctl status visitor-kiosk
sudo journalctl -u visitor-kiosk -f
```

Local test on the server: `http://127.0.0.1:8000`

From another device on the tailnet: `http://<server-magicdns-or-100.x-ip>:8000` (see [Networking with Tailscale](#networking-with-tailscale)).

### 3. Firewall (if you use `ufw`)

```bash
sudo ufw allow 8000/tcp
sudo ufw reload
```

With Tailscale, you typically still allow 8000 only on the tailnet interface or rely on tailnet membership for access; avoid exposing 8000 on a public WAN interface unless you intend to.

### 4. Optional: Power Automate webhook

After save, the app can POST JSON to a webhook if **`VISITOR_WEBHOOK_URL`** is set. Configure via systemd overrides (URLs with `%` often need **`%%`** in unit files, or use **`EnvironmentFile=`**).

```bash
sudo systemctl edit visitor-kiosk
sudo systemctl daemon-reload
sudo systemctl restart visitor-kiosk
```

### 5. Optional: Zebra badge printing (CUPS, USB only)

Badge printing uses a **USB** Zebra connected to the Linux backend. We do **not** use Ethernet / JetDirect for this project.

1. Plug the Zebra into the server (USB).
2. Install CUPS if needed: `sudo apt update && sudo apt install -y cups cups-client`
3. Add the printer at **`http://127.0.0.1:631/`** as a **raw / pass-through** queue for ZPL (not a generic driver that rasterizes labels).
4. Note the queue name from `lpstat -p` (or the CUPS admin UI).
5. Set that name on the service:

```bash
sudo systemctl edit visitor-kiosk
# Under [Service]:
# Environment=ZEBRA_CUPS_QUEUE=YourQueueName
sudo systemctl daemon-reload
sudo systemctl restart visitor-kiosk
```

6. Test print: `bash deploy/zebra-print-test.sh YourQueueName`

If **`ZEBRA_CUPS_QUEUE`** is unset, visitor submissions still save; no badge is printed.

Many label and font options are environment variables in `app/badge.py` (for example `ZEBRA_LABEL_WIDTH_IN`, `ZEBRA_TIMEZONE`, `ZEBRA_HOST_CAPTION_TEXT`).

### 6. Restore from backup (disaster recovery)

1. Install the app again (section 2).
2. Stop the service: `sudo systemctl stop visitor-kiosk`.
3. Restore data, for example:

   ```bash
   sudo tar -xzf visitor-kiosk-data-YYYYMMDD-HHMMSS.tar.gz -C /var/lib
   sudo chown -R "$USER:$USER" /var/lib/visitor-kiosk
   ```

4. Recreate **systemd overrides** using your saved `systemd-visitor-kiosk-*.txt` from backups (compare to `sudo systemctl cat visitor-kiosk` on the old machine). Webhook URLs and `ZEBRA_CUPS_QUEUE` are not stored in the repo.
5. Re-add the printer in CUPS on the new hardware and align `ZEBRA_CUPS_QUEUE` with the new queue name.
6. Start: `sudo systemctl start visitor-kiosk`.

---

## Backup (recommended: NAS)

**What actually matters**

| Item | Why |
|------|-----|
| **`/var/lib/visitor-kiosk`** | Contains `visitors.jsonl` (all saved submissions). This is the irreplaceable application state. |
| **systemd unit + drop-ins** | `ZEBRA_CUPS_QUEUE`, `VISITOR_WEBHOOK_URL`, timeouts, debug flags — these live outside the repo. |
| **CUPS queue name** | You can rebuild from `lpstat -p` notes; printer setup is usually redone on new hardware. |
| **Git remote** | Source code; your NAS backup is mainly for **data + config snapshots**, not a substitute for version control. |

**What you do not need to back up** for a clean restore: the `venv/` directory (recreated by `install-server.sh` or `pip install -r requirements.txt`).

### Option A: bundled script + NAS mount (simple)

1. On the NAS, create a share/folder, for example `Backups/visitor-kiosk`.
2. On the Linux server, mount that folder (SMB/CIFS or NFS — use your NAS docs). Example mount point: `/mnt/nas/visitor-kiosk-backup`.
3. Make the script executable and run it once manually to confirm files appear on the NAS:

```bash
chmod +x ~/visitor-kiosk/deploy/backup-kiosk-state.sh
BACKUP_DEST=/mnt/nas/visitor-kiosk-backup \
BACKUP_KEEP_LAST=30 \
bash ~/visitor-kiosk/deploy/backup-kiosk-state.sh
```

Each run writes a **timestamped** `.tar.gz` of the data directory plus text captures of **systemd** and **`lpstat`** for documentation. Set **`BACKUP_KEEP_LAST`** to trim old archives (optional). If you changed **`VISITOR_DATA_DIR`**, set the same variable when running this script.

4. Schedule with **cron** or a **systemd timer** (daily is typical). Example cron line (daily at 03:15, adjust paths):

```cron
15 3 * * * BACKUP_DEST=/mnt/nas/visitor-kiosk-backup BACKUP_KEEP_LAST=30 /home/YOUR_USER/visitor-kiosk/deploy/backup-kiosk-state.sh >> /var/log/visitor-kiosk-backup.log 2>&1
```

Ensure the cron user can read `/var/lib/visitor-kiosk` (same user as the service is simplest).

### Option B: `rsync` mirror (no tar)

If you prefer a live mirror of the data directory only:

```bash
rsync -a --delete /var/lib/visitor-kiosk/ /mnt/nas/visitor-kiosk-backup/latest/
```

Still export **`systemctl cat visitor-kiosk`** whenever you change overrides, and store that file on the NAS (the script does this for you).

### Option C: `rclone` to NAS WebDAV/S3/FTP

Useful when the server cannot mount the NAS directly. Configure `rclone` once, then sync the output directory produced by `backup-kiosk-state.sh` or sync `/var/lib/visitor-kiosk` plus a small `config/` folder where you save systemd exports manually.

### Secrets and webhook URLs

Backup archives contain **visitor data** (PII depending on your form). Restrict NAS permissions and encryption-at-rest if your policy requires it. Webhook URLs may contain **query secrets**; treat backup files like credentials.

### Test restores

Once a quarter (or after any major change), restore a tarball to a **test** directory, confirm you can read `visitors.jsonl`, and verify you still know how to recreate systemd overrides. Untested backups are a common failure mode.
