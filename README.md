# SBIKioskBackend

FastAPI backend for visitor check-in, optional badge printing via CUPS (Zebra ZPL), and optional Power Automate webhook on save.

## Server reinstall and setup

These steps assume **Ubuntu** (or similar) and a normal SSH user (not root). The install script uses `sudo` where needed.

### 1. Prerequisites

- `python3`, `python3-venv`, `python3-pip` (the install script will tell you if Python is missing).
- Git access to this repository (or copy the project tree to `~/visitor-kiosk`).

### 2. Install application and service

```bash
cd ~
git clone <your-repo-url> visitor-kiosk   # or unpack/sync the tree here
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

Local test: `http://127.0.0.1:8000`

### 3. Firewall (if you use `ufw`)

```bash
sudo ufw allow 8000/tcp
sudo ufw reload
```

### 4. Optional: Tailscale or LAN access

If the kiosk browser runs on another machine, reach the API over your network (for example Tailscale). Use `http://<server-tailscale-hostname-or-IP>:8000` from the client.

### 5. Optional: Power Automate webhook

After save, the app can POST JSON to a webhook if **`VISITOR_WEBHOOK_URL`** is set. Configure via systemd overrides (URLs with `%` often need **`%%`** in unit files, or use **`EnvironmentFile=`**).

```bash
sudo systemctl edit visitor-kiosk
sudo systemctl daemon-reload
sudo systemctl restart visitor-kiosk
```

### 6. Optional: Zebra badge printing (CUPS)

1. Add the printer in CUPS (`http://127.0.0.1:631/`) as a **raw / ZPL** queue (typical for USB).
2. Set the queue name in the service environment:

```bash
sudo systemctl edit visitor-kiosk
# Under [Service]:
# Environment=ZEBRA_CUPS_QUEUE=YourQueueName
sudo systemctl daemon-reload
sudo systemctl restart visitor-kiosk
```

Ethernet / JetDirect helper: `deploy/setup-zebra-ethernet-cups.sh`. Test print: `deploy/zebra-print-test.sh`.

Many label and font options are environment variables in `app/badge.py` (for example `ZEBRA_LABEL_WIDTH_IN`, `ZEBRA_TIMEZONE`, `ZEBRA_HOST_CAPTION_TEXT`).

### 7. Restore from backup (disaster recovery)

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
