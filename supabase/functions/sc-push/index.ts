// sc-push: sends the queued reminder pushes. Pinged by the database (sc_push_kick) with a secret header.
// No secrets here: sc_push_take checks the ping's key against Supabase Vault and returns the push key.
import { sendPush } from './webpush.js';

const SB_URL = Deno.env.get('SUPABASE_URL')!;
const SB_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

async function rpc(fn: string, args: unknown = {}) {
  const r = await fetch(`${SB_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(args),
  });
  if (!r.ok) throw new Error(`${fn} ${r.status} ${await r.text()}`);
  const t = await r.text();
  return t ? JSON.parse(t) : null;
}

Deno.serve(async (req) => {
  const key = req.headers.get('x-sc-key') || '';
  if (!key) return new Response('no', { status: 401 });
  // A delayed test ("Send a test" waits so the phone can be locked first): wait, then send.
  let delay = 0;
  try { delay = Math.min(20, Math.max(0, Number((await req.json())?.delay) || 0)); } catch (_) { /* no body */ }
  if (delay) await new Promise((r) => setTimeout(r, delay * 1000 + 800));
  let take: { jobs: { endpoint: string; keys: { p256dh: string; auth: string }; payload: Record<string, unknown> }[]; vapid: { jwk: JsonWebKey; pub: string } };
  try {
    take = await rpc('sc_push_take', { p_key: key });
  } catch (e) {
    console.error(String(e));
    return new Response('no', { status: String(e).includes('bad_key') ? 401 : 500 });
  }
  const vapid = { jwk: take.vapid?.jwk, pub: take.vapid?.pub, subject: 'https://stevepc95.github.io/steve-and-chlo/' };
  const results = await Promise.all((take.jobs || []).map(async (j) => {
    try {
      const r = await sendPush({ endpoint: j.endpoint, keys: j.keys }, j.payload, vapid);
      return { endpoint: j.endpoint, status: r.status, text: r.text };
    } catch (e) {
      return { endpoint: j.endpoint, status: 0, text: String(e).slice(0, 200) };
    }
  }));
  if (results.length) await rpc('sc_push_result', { p_results: results }).catch((e) => console.error(String(e)));
  return Response.json({ sent: results.length, statuses: results.map((r) => r.status + ' ' + r.text) });
});
