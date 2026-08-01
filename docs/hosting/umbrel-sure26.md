# Deploying Sure26 on an Umbrel Pro (standard Docker Compose)

A beginner-safe walkthrough for running Sure26 on an Umbrel Pro node using
plain Docker Compose — no Umbrel app packaging. It builds the app from your
fork's source, so you run the exact Sure26 code (with biweekly budgeting).

> On Umbrel, run Docker commands with `sudo`. When `sudo` asks for a password,
> it's your Umbrel login password, and nothing shows on screen as you type.
> **Never paste secrets into a chat or a shared document.**

---

## 0. Prerequisites

- SSH access to the node: `ssh umbrel@umbrel.local` (or `ssh umbrel@<node-ip>`).
- Docker (bundled with umbrelOS) and `git`.
- If you previously ran Sure from the Umbrel App Store, uninstall it from the
  Umbrel dashboard first so it doesn't conflict.

---

## 1. Get the source

```bash
mkdir -p ~/sure26 && cd ~/sure26
git clone https://github.com/aso42244/sure26.git .
git checkout sure26          # the deployable Sure26 branch
```

## 2. Configure secrets

```bash
cp .env.sure26.example .env
# Generate the two required secrets and write them into .env:
echo "SECRET_KEY_BASE=$(openssl rand -hex 64)" >> .env
echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)" >> .env
echo "BUILD_COMMIT_SHA=$(git rev-parse HEAD)"    >> .env
```

Then open `.env` (`nano .env`) and make sure `SECRET_KEY_BASE` and
`POSTGRES_PASSWORD` each appear **once** with a value. (If a key appears twice,
delete the empty one.) Save with `Ctrl+O`, `Enter`, exit with `Ctrl+X`.

## 3. Build and start

```bash
sudo docker compose -f compose.sure26.yml up -d --build
```

The first build takes several minutes. The web container runs database
migrations automatically on startup.

## 4. Verify it's healthy

```bash
sudo docker compose -f compose.sure26.yml ps
sudo docker compose -f compose.sure26.yml logs -f web   # Ctrl+C to stop watching
```

Open `http://<your-node-ip>:3000` (or the `PORT` you set) in a browser on the
same network, create your account, and confirm:

- Existing monthly budgeting works as normal.
- **Settings → Budget cadence** exists (this is the new feature).
- The version link (user menu) points at your Sure26 source.

## 5. Turn on automated daily backups

```bash
mkdir -p backups
sudo docker compose -f compose.sure26.yml --profile backup up -d
```

Backups are written to `./backups` (override with `BACKUP_DIR` in `.env`).

---

## 6. Take a manual backup (do this before any upgrade)

```bash
cd ~/sure26
sudo docker compose -f compose.sure26.yml exec -T db \
  pg_dump -U sure_user sure_production > backup-$(date +%Y%m%d-%H%M%S).sql
ls -lh backup-*.sql          # confirm it exists and is non-empty
head -n 5 backup-*.sql       # should look like a PostgreSQL dump
```

Copy that file somewhere safe before continuing.

## 7. Upgrade to a newer Sure26

```bash
cd ~/sure26
# 1) Back up first (section 6) — do not skip.
git pull
echo "BUILD_COMMIT_SHA=$(git rev-parse HEAD)" >> .env   # then remove the older duplicate line in .env
sudo docker compose -f compose.sure26.yml up -d --build
sudo docker compose -f compose.sure26.yml logs -f web
```

## 8. Roll back

Migrations added by biweekly budgeting are additive and reversible and never
drop existing financial data. Two options:

**A. Restore the pre-upgrade backup (safest):**
```bash
cd ~/sure26
sudo docker compose -f compose.sure26.yml stop web worker
sudo docker compose -f compose.sure26.yml exec -T db \
  psql -U sure_user -d sure_production < backup-YYYYMMDD-HHMMSS.sql
sudo docker compose -f compose.sure26.yml up -d
```

**B. Reverse only the biweekly migrations (schema-only undo):**
```bash
sudo docker compose -f compose.sure26.yml exec web bin/rails db:rollback STEP=5
```

When unsure, prefer **A**. Never run a migration or rollback without a verified
backup in hand.

---

## 9. Everyday commands

```bash
# Stop everything (keeps data):
sudo docker compose -f compose.sure26.yml down
# Start again:
sudo docker compose -f compose.sure26.yml up -d
# View logs:
sudo docker compose -f compose.sure26.yml logs -f web
# Full reset INCLUDING data (destructive!):
sudo docker compose -f compose.sure26.yml down -v
```

## 10. Troubleshooting

- **Port already in use:** set a different `PORT` in `.env` (e.g. `PORT=3010`)
  and re-run the `up -d` command.
- **`SECRET_KEY_BASE is required` / `POSTGRES_PASSWORD` error:** those aren't
  set in `.env` — see section 2.
- **App won't boot after an upgrade:** check `logs -f web`; if a migration
  failed, restore your backup (section 8A).

This deployment does not configure any remote access. Keep it on your LAN or
reach it through your own VPN/Tailscale, which is outside Sure26's scope.
