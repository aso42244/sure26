# Running Sure26 under Portainer on Umbrel (durable deployment)

This is the recommended way to run Sure26 on Umbrel long-term. GitHub Actions
builds the app image in the cloud and publishes it to GHCR; **Portainer** (an
Umbrel App Store app) pulls that image and keeps the stack running across
reboots and umbrelOS updates. Your Umbrel never compiles anything — it only
downloads a finished image.

Follows Umbrel's Portainer best practices: **named volumes only**, **`restart:
unless-stopped`**, and a single published **port**.

---

## Part 1 — Publish the image from GitHub (one-time, in your browser)

1. **Enable Actions on your fork:** open `https://github.com/aso42244/sure26`,
   click the **Actions** tab, and if prompted, click **"I understand my
   workflows, go ahead and enable them."**
2. **Run the build:** Actions -> **Publish Docker image** (left list) -> **Run
   workflow** (right) -> set **Use workflow from** to branch **`sure26`**, set
   the **ref** input to **`sure26`**, set **push** to **true**, then **Run
   workflow**. It takes ~15-25 min (it runs the test suite, then builds
   amd64 + arm64).
3. **Make the image public:** once it's green, go to your profile ->
   **Packages** -> **sure26** -> **Package settings** -> **Change visibility**
   -> **Public**. (This lets Portainer pull it without a login, and satisfies
   AGPL source availability.)

To **update** later: merge your changes to `sure26`, run this workflow again,
then in Portainer hit **Pull and redeploy** on the stack.

---

## Part 2 — Install Portainer

1. Umbrel dashboard -> **App Store** -> search **Portainer** -> **Install**.
2. Open Portainer and set its **admin password** when prompted (store it in your
   password manager). Choose the local Docker environment.

---

## Part 3 — Remove the temporary SSH deployment (fresh start)

You chose to start fresh, so remove the SSH stack (this frees port 3000 and
deletes its test database). Over SSH:

```bash
cd ~/sure26
sudo docker compose -f compose.sure26.yml down -v
```

---

## Part 4 — Deploy the Sure26 stack in Portainer

1. Portainer -> **Stacks** -> **Add stack**. Name it **`sure26`**.
2. Build method: **Web editor**. Paste the contents of
   [`compose.sure26.registry.yml`](../../compose.sure26.registry.yml).
3. Scroll to **Environment variables** -> **Add an environment variable**, and
   add these (values stay on your device, in Portainer):
   - `SECRET_KEY_BASE` = a fresh value from `openssl rand -hex 64`
   - `POSTGRES_PASSWORD` = a fresh value from `openssl rand -hex 24`
   - `SURE_SOURCE_REPO` = `aso42244/sure26`
   - *(optional)* `PORT` = `3000` (change if another app uses 3000)
   - *(optional)* `BUILD_COMMIT_SHA` = the commit you built (for the source link)
4. Click **Deploy the stack**. Portainer pulls the image and starts everything.

> Generate the two secrets in your SSH terminal with the `openssl` commands
> above and paste them into Portainer's fields — never into a chat or document.

---

## Part 5 — Verify

- Portainer -> **Containers**: `sure26-web-1`, `-worker-1`, `-db-1`, `-redis-1`,
  `-backup-1` should be **running** (db/redis **healthy**).
- In a browser on the same network: **`http://umbrel.local:3000`** (or your
  `PORT`) shows the Sure26 sign-up page. Create your account.
- Confirm **Settings -> Budget cadence** is present, and the user-menu version
  link points at your fork.

Because the stack uses `restart: unless-stopped` and named volumes, it comes
back automatically after reboots and umbrelOS updates, and your data persists.

---

## Backups & restore

Automated daily backups run in the `backup` container into the **named volume**
`sure26_pg-backups`.

- **Copy a backup off the device** (SSH):
  ```bash
  sudo docker cp sure26-backup-1:/backups ~/sure26-backups
  ```
- **Manual backup on demand** (SSH):
  ```bash
  sudo docker exec -t sure26-db-1 pg_dump -U sure_user sure_production > backup-$(date +%Y%m%d-%H%M%S).sql
  ```
- **Restore** a dump into the running stack (SSH):
  ```bash
  cat backup-YYYYMMDD-HHMMSS.sql | sudo docker exec -i sure26-db-1 psql -U sure_user -d sure_production
  ```

Always take and verify a backup before updating.
