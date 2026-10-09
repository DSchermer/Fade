// Sends queued push notifications through Apple's push service (APNs).
// Called once a minute by a database job (supabase/ops/schedule_push.sql) using the service-role key.
// UNTESTED against Apple (needs the paid Apple Developer account) — see docs/APPLE_ACCOUNT_STEPS.md.
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const KEY_ID = Deno.env.get("APNS_KEY_ID")!;
const TEAM_ID = Deno.env.get("APNS_TEAM_ID")!;
const PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY")!; // the whole .p8 file, including the BEGIN/END lines
const BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "com.dschermer.fade";
const PUSH_SECRET = (Deno.env.get("PUSH_SECRET") ?? "").trim();   // stray spaces/line breaks from copy-paste are ignored   // our own shared secret for the database job (Edge Function secret + Vault secret `push_secret`)

/** Our own database and sign-in service are called with plain web requests. The service key can be the older long `eyJ…` kind or
 *  the newer short `sb_…` kind: the newer kind goes in the `apikey` header only. */
const serviceHeaders = (): Record<string, string> =>
  SERVICE_KEY.startsWith("eyJ")
    ? { apikey: SERVICE_KEY, authorization: `Bearer ${SERVICE_KEY}`, "content-type": "application/json" }
    : { apikey: SERVICE_KEY, "content-type": "application/json" };

const b64url = (data: ArrayBuffer | Uint8Array | string) => {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = "";
  bytes.forEach((b) => (s += String.fromCharCode(b)));
  return btoa(s).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
};

/** Apple wants a short-lived signed token (JWT, ES256) made from your .p8 key. Reused for ~50 minutes. */
let cached: { token: string; at: number } | null = null;
async function apnsToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && now - cached.at < 3000) return cached.token;
  const pem = PRIVATE_KEY.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\\n/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: KEY_ID }));
  const claims = b64url(JSON.stringify({ iss: TEAM_ID, iat: now }));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`));
  cached = { token: `${header}.${claims}.${b64url(sig)}`, at: now };
  return cached.token;
}

Deno.serve(async (req) => {
  // Only the database job may trigger sending. It proves itself with our own shared secret (x-push-secret header). The service key is
  // also accepted, but the project's injected key can be in a different format than the one the job holds, so the secret is the real gate.
  const auth = req.headers.get("Authorization") ?? "";
  const viaSecret = PUSH_SECRET.length > 0 && (req.headers.get("x-push-secret") ?? "").trim() === PUSH_SECRET;
  const viaKey = !!SERVICE_KEY && auth === `Bearer ${SERVICE_KEY}`;
  if (!viaSecret && !viaKey) return new Response(JSON.stringify({ error: "forbidden" }), { status: 403, headers: { "content-type": "application/json" } });

  const claim = await fetch(`${SUPABASE_URL}/rest/v1/rpc/claim_notifications`, {
    method: "POST", headers: serviceHeaders(), body: JSON.stringify({ p_limit: 100 }),
  });
  if (!claim.ok) return new Response(JSON.stringify({ error: `claim_notifications ${claim.status}`, detail: (await claim.text()).slice(0, 300) }), { status: 500 });
  const rows: any[] = await claim.json();

  // one queued message can go to several phones
  const byMessage = new Map<number, any[]>();
  for (const r of rows) byMessage.set(r.id, [...(byMessage.get(r.id) ?? []), r]);

  let sent = 0, failed = 0;
  const jwt = byMessage.size ? await apnsToken() : "";
  for (const [id, deliveries] of byMessage) {
    let ok = false;
    let lastError = "";
    const dead: string[] = [];
    for (const d of deliveries) {
      const host = d.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
      const res = await fetch(`https://${host}/3/device/${d.token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": BUNDLE_ID,
          "apns-push-type": "alert",
          "apns-priority": "10",
          "content-type": "application/json",
        },
        body: JSON.stringify({
          aps: { alert: { title: d.title, body: d.body }, sound: "default", "thread-id": d.data?.group_id },
          ...d.data,
        }),
      });
      if (res.ok) {
        ok = true;
      } else {
        const body = await res.json().catch(() => ({}));
        lastError = `${res.status} ${body.reason ?? ""}`.trim();
        if (res.status === 410 || ["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"].includes(body.reason)) dead.push(d.token);
      }
    }
    const fin = await fetch(`${SUPABASE_URL}/rest/v1/rpc/finish_notification`, {
      method: "POST", headers: serviceHeaders(),
      body: JSON.stringify({ p_id: id, p_ok: ok, p_error: ok ? null : lastError, p_dead_tokens: dead }),
    });
    if (!fin.ok) console.error("finish_notification failed", fin.status, (await fin.text()).slice(0, 300));
    ok ? sent++ : failed++;
  }
  return new Response(JSON.stringify({ sent, failed }), { headers: { "content-type": "application/json" } });
});
