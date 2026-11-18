// Calls POST /api/cron/score on the SetPoint backend every 5 minutes (see wrangler.toml).
// The route is safe to call often: it only acts on check-ins that are due.

interface Env {
  API_URL: string;
  CRON_SECRET: string;
}

type Scheduled = { scheduledTime: number; cron: string };
type Context = { waitUntil(promise: Promise<unknown>): void };

async function callScore(env: Env): Promise<Response> {
  return fetch(`${env.API_URL}/api/cron/score`, {
    method: 'POST',
    headers: { 'x-cron-secret': env.CRON_SECRET },
    signal: AbortSignal.timeout(55_000),
  });
}

async function run(env: Env, when: Scheduled): Promise<void> {
  // One retry: a cold start or a brief network blip shouldn't cost a whole 5 minutes.
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    try {
      const res = await callScore(env);
      console.log(`score ${new Date(when.scheduledTime).toISOString()} attempt ${attempt}: ${res.status}`);
      if (res.ok) return;
    } catch (err) {
      console.log(`score attempt ${attempt} failed: ${err instanceof Error ? err.message : String(err)}`);
    }
  }
  throw new Error('score call failed twice');
}

export default {
  async scheduled(event: Scheduled, env: Env, ctx: Context): Promise<void> {
    ctx.waitUntil(run(env, event));
  },
  // Visiting the worker's address just says it's alive; it never calls the backend.
  async fetch(): Promise<Response> {
    return new Response('SetPoint score timer: every 5 minutes.\n', { status: 200 });
  },
};
