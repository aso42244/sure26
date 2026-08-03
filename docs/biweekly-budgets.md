# Biweekly budgeting in Sure26

Sure26 adds an **optional biweekly budgeting cadence** to Sure. Everything that
already worked keeps working exactly as before — this is strictly additive and
**off by default**. You only get biweekly behavior if you explicitly turn it on.

- **Monthly (default):** budget periods are calendar months, just like upstream
  Sure.
- **Biweekly (opt-in):** budget periods are exact **14-day** cycles generated
  from an **anchor date** you choose. "Biweekly" here always means every 14
  days — never twice a month.

This document is written for a self-hosted, Docker Compose deployment and
assumes no prior Rails or Docker knowledge.

---

## 1. What you get

### Per-budget cadence
Cadence is chosen per family and is **effective-dated**: switching to biweekly
only changes **future** budget periods. Past and in-progress budgets are never
rewritten or recalculated. Monthly budgets you already have stay monthly.

### Exact 14-day cycles from your anchor
You pick the first day of a cycle (the **anchor date**). Every cycle is exactly
14 days. Sure26 generates past and future cycle boundaries by stepping 14 days
at a time from the anchor, so it correctly handles leap years, year boundaries,
daylight-saving changes, and calendar years that contain **27** cycle starts
(not always 26).

### Budget rollover (positive or negative, funding independent of payment)
Any budget category with its own individual budgeted amount — a top-level
category, or a subcategory once it's given its own limit instead of sharing
its parent's pool — in a monthly **or** biweekly budget can have **Roll over**
turned on. A subcategory still sharing its parent's pool has no independent
figure to roll on its own; it automatically reflects the parent's rollover
(if the parent has it on) through the existing shared-pool math. When rollover
is on, whatever's left in that category at the end of a period (or however far
over you went) carries into the next period,
added to whatever you budget there next. Nothing is auto-adjusted, and the
carry can go negative:

> Example — an expense you pay **$300 on the 1st of every month**, funded by
> budgeting **$150 every 14-day cycle** with rollover on:
>
> | Cycle | Opening | Budgeted | Actual payment | Closing (retained) |
> |------:|--------:|---------:|----------------:|-------------------:|
> | 1     | $0      | $150     | $0              | $150               |
> | 2     | $150    | $150     | $300            | $0                 |
> | 3     | $0      | $150     | $0              | **$150**           |
>
> A month with a third paycheck simply budgets a third $150; that surplus
> **stays** in the category. Later cycles are **never** auto-reduced because
> the category is ahead of schedule.
>
> If you instead overspend a category — say $75 budgeted, $175 spent — it
> carries a **-$100** balance into the next period, added to whatever's
> newly budgeted there (e.g. $75 + -$100 = -$25 to start that period).

The same idea applies to quarterly, semiannual, or annual bills: budget a small
amount each cycle and let it accumulate until the real bill posts, whenever
that is.

### Biweekly recurring income
A manually created recurring transaction (for example a paycheck) can be set to
a **biweekly** cadence, advancing by exact 14-day steps.

---

## 2. How to turn on biweekly budgeting (in the app)

1. Sign in as a family **admin**.
2. Go to **Settings → Budget cadence**.
3. Choose **Every 2 weeks (14 days)** and pick an **anchor date** — the first
   day of your first 14-day cycle (for many people, a payday).
4. Click **Preview change**. You'll see:
   - your current period,
   - the date the new cadence starts (always **after** the current period), and
   - the first two new 14-day periods.
5. Click **Apply change**.

Because changes are future-only, the switch never alters budgets you've already
been using. To go back, repeat the steps and choose **Monthly**; that also only
affects future periods.

### Turning on rollover for a category
Open a budget, go to **Categories**, and check **Roll over** next to any
category. For a subcategory, give it its own individual amount first (instead
of leaving it at $0 sharing the parent's pool) — otherwise there's nothing
independent for it to roll. The running **Balance** is shown beneath the
amount once rollover is active.

### Setting a category's balance directly
A rollover category shows an editable **Balance** beneath its amount. Typing a
number sets the balance to exactly that — handy when you first start using
Sure26 and an envelope already holds money ("Car Repairs really has $500 in
it"), so you don't have to invent a transaction to get it there.

The amount field and the balance are different things: the **amount** is what
you add this period, the **balance** is what the category currently holds.
Setting the balance only works on the current period — closed periods stay
frozen — and only when rollover is on, since without it there's nothing to
carry the value forward.

### Moving money between categories
On the **Categories** page there's a **Move money** button. It opens a small
dialog where you pick a **From** category, a **To** category, and an amount —
the "take $50 out of Groceries, add it to Car Repairs" flow. This only affects
the **current** period (closed periods are frozen), and both categories must
have their own budget amount (a subcategory sharing its parent's pool isn't
eligible until you give it its own amount).

What actually moves depends on the category:

- **Rollover on:** the money comes out of the category's accumulated balance,
  so you can move funds you've saved up over many prior cycles — not just this
  cycle's contribution — and this cycle's planned amount is left unchanged.
- **Rollover off:** this period's budgeted amount is moved instead.

Moving more than a category currently has is allowed; it simply leaves that
category with a negative balance for the period.

---

## 3. Deploying Sure26 with Docker Compose

Sure26 uses upstream Sure's standard Docker Compose setup — nothing custom. Use
`compose.example.yml` as your starting point (copy it to `compose.yml`). It runs
the web app, a background worker, PostgreSQL, and Redis, with data kept in a
persistent volume.

> **Never commit secrets.** Keep passwords and keys in a `.env` file (which is
> git-ignored), not in the compose file.

Bring the stack up:

```bash
docker compose up -d
```

Check health and logs:

```bash
docker compose ps
docker compose logs -f web
```

Database migrations (including the additive ones this feature adds) run on
startup. The new tables/columns are all additive and default existing data to
monthly, so an existing Sure database upgrades in place with no data changes.

### AGPL source availability (required)
Sure26 is AGPLv3. The running app links every user to the corresponding source
for the exact deployed version (in the user menu and the version badge). So the
link points at **your** published source, set:

```bash
# In your .env
SURE_SOURCE_REPO=your-github-user/your-fork
BUILD_COMMIT_SHA=<the exact commit you built>
```

and **tag** the commit you deploy (e.g. `git tag v0.7.4-sure26.1 && git push --tags`)
so the link resolves to that exact source.

---

## 4. Back up before every upgrade or migration

**Always take a verified backup before upgrading or running migrations.**

Create a backup (adjust the service/user names to match your compose file):

```bash
# Dump the database to a timestamped file on the host
docker compose exec -T db pg_dump -U sure_user sure_production \
  > backup-$(date +%Y%m%d-%H%M%S).sql
```

Verify the backup is non-empty and looks like SQL:

```bash
ls -lh backup-*.sql
head -n 5 backup-*.sql   # should show PostgreSQL dump headers
```

Keep the backup somewhere safe **before** you continue.

---

## 5. Upgrade

```bash
# 1) Back up first (see section 4) — do not skip this.
# 2) Get the new version
git pull                       # or pull the new image tag
# 3) Rebuild and restart
docker compose up -d --build
# 4) Watch it come up; migrations run automatically
docker compose logs -f web
```

Confirm the app loads and your existing (monthly) budgets are unchanged.

---

## 6. Roll back

The migrations added by this feature are **reversible** and only add tables and
columns — they never drop or rewrite existing financial data. Two rollback
paths:

**A. Restore the pre-upgrade backup (safest):**

```bash
# Stop the app, keep the database service running
docker compose stop web worker
# Restore into a fresh database (drops and recreates, so be sure)
docker compose exec -T db psql -U sure_user -d sure_production < backup-YYYYMMDD-HHMMSS.sql
docker compose up -d
```

**B. Reverse just the new migrations (if you only need to undo the schema):**

```bash
# Revert the five additive migrations added by this feature
docker compose exec web bin/rails db:rollback STEP=5
```

Rolling back removes the biweekly columns/tables; monthly budgets are
unaffected because they never depended on them.

> If you are unsure, prefer **path A** (restore from backup). Never run a
> migration or rollback in production without a verified backup in hand.

---

## 7. Troubleshooting

- **The app won't start after upgrade.** Check `docker compose logs web`. If a
  migration failed, restore your backup (section 6A) and open an issue.
- **I switched to biweekly but an old month still shows monthly.** That's
  correct — cadence changes are future-only and never rewrite past periods.
- **A rollover balance didn't carry into the next cycle.** Rollover only
  chains through budget periods you actually open/set up. Use **Copy
  previous** when starting the next cycle, or just visit the new period
  directly — its opening balance is seeded from the prior period automatically.
