# SetPoint score timer

Calls the backend's `/api/cron/score` every 5 minutes so check-ins, snoozes, the after-training reminder
and the weigh-in reminder go out on time. It replaces the GitHub Actions timer, which only runs every
few hours on this repo.

## Set it up (once, about 5 minutes)

Run these in this folder (`cloudflare/score-timer`):

```bash
npx wrangler login
```
Opens your browser to sign in to Cloudflare (a free account is enough).

```bash
npx wrangler secret put CRON_SECRET
```
Paste the same `CRON_SECRET` the backend uses (the one in Vercel's environment variables).

```bash
npx wrangler deploy
```

## Check that it works

- Cloudflare dashboard → Workers → `setpoint-score-timer` → Logs: a line like `score … attempt 1: 200` every 5 minutes.
- Backend: `/ops` page, or `GET /api/admin/metrics` → `scheduler` should show a recent run and not `stale`.

## After it works: turn the old timer off

Two timers could send the same check-in. Once the lines above show up, open
`.github/workflows/score-checkins.yml` and delete the `schedule:` block (keep `workflow_dispatch:` so it
can still be run by hand).
