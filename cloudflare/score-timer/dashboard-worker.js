// SetPoint score timer, as plain JavaScript to paste into the Cloudflare dashboard editor.
// Calls POST /api/cron/score every 5 minutes (set the Cron Trigger to */5 * * * *).
// Needs a secret named CRON_SECRET and a variable named API_URL (https://set-point-backend.vercel.app).

async function run(env, scheduledTime) {
  // One retry: a cold start or a brief network blip shouldn't cost a whole 5 minutes.
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    try {
      const res = await fetch(`${env.API_URL}/api/cron/score`, {
        method: 'POST',
        headers: { 'x-cron-secret': env.CRON_SECRET },
        signal: AbortSignal.timeout(55000),
      });
      console.log(`score ${new Date(scheduledTime).toISOString()} attempt ${attempt}: ${res.status}`);
      if (res.ok) return;
    } catch (err) {
      console.log(`score attempt ${attempt} failed: ${err instanceof Error ? err.message : String(err)}`);
    }
  }
  throw new Error('score call failed twice');
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(run(env, event.scheduledTime));
  },
  // Visiting the worker's address just says it's alive; it never calls the backend.
  async fetch() {
    return new Response('SetPoint score timer: every 5 minutes.\n', { status: 200 });
  },
};
