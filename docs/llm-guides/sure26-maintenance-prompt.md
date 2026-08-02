# Sure26 maintenance prompt

Copy everything in the box below and paste it into a **new** Claude Code
session (attach the `aso42244/sure26` GitHub repo if it isn't already) whenever
you want to: pull in the latest changes from upstream Sure, rebuild the
Docker image, and update the copy running on your Synology.

You don't need to edit anything in the box — it's written to work as-is. Just
paste it and follow along; it will ask before doing anything risky and will
walk you through each manual step one at a time.

---

```
You are picking up maintenance work on Sure26, a personal fork of Sure
(we-promise/sure) that adds an optional biweekly (14-day) budgeting cadence
with sinking-fund contributions. I am not a developer — explain plainly, one
step at a time, and never assume I know Git/Docker/Rails terms.

## Repository & branch model (do not deviate without asking me)
- Fork: aso42244/sure26. Upstream: we-promise/sure.
- `main` is an untouched mirror of upstream `main` — never customize it.
- `sure26` is the long-lived, deployable branch with the biweekly-budget
  feature. This is what gets built into the running Docker image.
- Feature/fix work happens on a short-lived branch off `sure26`, merged back
  via a pull request that I review and approve. Never push directly to
  `sure26` or `main`, never force-push, never merge without my explicit
  go-ahead in this conversation.

## Task 1 — Sync upstream changes into Sure26
1. Fetch `we-promise/sure` and compare it against this fork's `main`.
2. Fast-forward this fork's `main` to match upstream `main` exactly (no
   Sure26-specific changes ever go on `main`).
3. Merge the updated `main` into `sure26` on a new branch (do not rebase or
   force-push `sure26` — it's shared/deployed history). Resolve any conflicts
   by hand, preserving both the upstream change and the Sure26 biweekly-budget
   behavior — never resolve a conflict by blindly taking one whole side.
4. Read upstream's release notes / commit log for the range you're merging:
   flag any security advisories, dependency bumps, deleted/renamed APIs, new
   migrations, or changes to budget/date assumptions that might interact with
   Sure26's `Budget::Cadence`, `BudgetSchedule`, `BudgetCategoryFund`, or
   `RecurringTransaction` cadence code (see app/models/budget/, app/models/
   budget_schedule.rb, app/models/budget_category_fund.rb).
5. Run the full check suite and report exact results (pass/fail counts, not
   just "tests pass"):
   - `bin/rails test`
   - `DISABLE_PARALLELIZATION=true bin/rails test:system` (only if relevant
     files changed — it's slow)
   - `bin/rubocop -f github -a`
   - `bundle exec erb_lint ./app/**/*.erb -a`
   - `bin/brakeman --no-pager`
6. Open a pull request from your branch into `sure26` (never into `main`).
   Summarize: what changed upstream, any conflicts and how you resolved them,
   full test/lint/security results, and anything that needs my judgment call.
7. Stop and wait for me to review and say "merge it" — do not merge yourself.

## Task 2 — Rebuild and publish the Docker image (only after Task 1's PR is merged)
The image is NOT rebuilt automatically when `sure26` changes — pushing to
`sure26` does not trigger the publish workflow (only pushes to `main` or a
version tag do that automatically). You must trigger it by hand:

1. In the GitHub UI: Actions tab → "Publish Docker image" → Run workflow →
   set "Use workflow from" to branch `sure26`, set the `ref` input to
   `sure26`, set `push` to `true` → Run workflow.
   (If you have `gh`/API access instead, trigger the same workflow_dispatch
   with those inputs.)
2. Wait for it to go green (it runs the full test suite first, then builds
   both amd64 and arm64, ~15-25 min). Report the result plainly — if it's red,
   diagnose and fix before continuing.
3. On success this publishes `ghcr.io/aso42244/sure26:latest` (public image,
   no login needed to pull) at the new commit.

## Task 3 — Walk me through updating the Synology deployment
Do this as a sequence of individual, copy-paste steps for me to run over SSH
— do not run these yourself, I don't have automated access set up for you to
reach my NAS. One command at a time, explain what each does and what success
looks like, and wait for me to paste back the result before giving the next
one.

Deployment facts (use these, don't ask me to rediscover them):
- Host: Synology DS220+, DSM 7.3.2, Container Manager (Docker 24.x, Compose
  v2.20.x). SSH as my DSM admin user.
- Project directory: /volume1/docker/sure26
  - compose.sure26.registry.yml — pulls the prebuilt image, never builds
    on-device.
  - .env — holds SECRET_KEY_BASE, POSTGRES_PASSWORD, SURE_SOURCE_REPO, PORT,
    POSTGRES_USER, POSTGRES_DB, RAILS_ASSUME_SSL=true. Never ask me to paste
    its contents into chat.
- Public URL: https://budget.<mydomain> via an existing Cloudflare Tunnel
  (the tunnel connector runs on my Umbrel and reaches the Synology over the
  LAN — no changes needed there for a routine update).
- The stack already includes an automated daily Postgres backup container
  (`prodrigestivill/postgres-backup-local`) writing to a named Docker volume
  — but ALWAYS take and verify a fresh manual backup before updating anyway.

Steps to walk me through, in order:
1. **Verified backup first, no exceptions:**
   `cd /volume1/docker/sure26 && sudo docker compose -f compose.sure26.registry.yml exec -T db pg_dump -U sure_user sure_production > backup-$(date +%Y%m%d-%H%M%S).sql`
   then confirm the file is non-empty and starts with `-- PostgreSQL database dump`.
2. Pull the freshly published image and recreate the containers:
   `sudo docker compose -f compose.sure26.registry.yml pull && sudo docker compose -f compose.sure26.registry.yml up -d`
3. Check container health:
   `sudo docker compose -f compose.sure26.registry.yml ps`
4. Confirm the app responds locally before I check the public URL:
   `curl -m 5 -o /dev/null -s -w "HTTP %{http_code}\n" http://localhost:3000/up`
5. Have me confirm in the browser at https://budget.<mydomain> that the app
   loads and — since we're specifically tracking this — that Settings →
   Budget cadence still works.
6. If anything is broken: stop, do not guess-and-retry repeatedly. Show me the
   relevant `docker compose logs --tail=60 web` output, explain what you
   think is wrong, and propose the fix before acting. If it's bad enough,
   the rollback is: restore the backup from step 1
   (`sudo docker compose -f compose.sure26.registry.yml exec -T db psql -U sure_user -d sure_production < backup-YYYYMMDD-HHMMSS.sql`)
   and, if needed, redeploy the previous known-good commit by rebuilding from
   that commit (Task 2, but with the older `ref`).

## General rules for this whole session
- Never deploy, migrate, or touch the running Synology stack without an
  explicit go-ahead from me in this conversation, same as the PR merge rule.
- Never commit secrets, `.env` contents, or anything from the Synology's
  `.env` file into the repo or into chat.
- Keep changes minimal and scoped — this is a maintenance sync, not a
  feature-development session. If you notice something worth improving that's
  out of scope, list it separately without doing it.
```

---

*This file lives at `docs/llm-guides/sure26-maintenance-prompt.md` in the
repo so it's never lost even if you clear your chat history. If Sure26's
deployment details change (new host, new domain, etc.), update this file to
match.*
