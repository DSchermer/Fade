const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const APPLE_KEY_ID = Deno.env.get("APPLE_KEY_ID")!;
const APPLE_TEAM_ID = Deno.env.get("APPLE_TEAM_ID")!;
const APPLE_PRIVATE_KEY = Deno.env.get("APPLE_PRIVATE_KEY")!;
const APPLE_BUNDLE_ID = Deno.env.get("APPLE_BUNDLE_ID") ?? "com.dschermer.fade";

/** Our own database and sign-in service are called with plain web requests. The service key can be the older long `eyJ…` kind or
 *  the newer short `sb_…` kind: the newer kind goes in the `apikey` header only. */
const serviceHeaders = (): Record<string, string> =>
  SERVICE_KEY.startsWith("eyJ")
    ? { apikey: SERVICE_KEY, authorization: `Bearer ${SERVICE_KEY}`, "content-type": "application/json" }
    : { apikey: SERVICE_KEY, "content-type": "application/json" };

/** Who is calling? Ask the sign-in service about the caller's own token. Returns their user id, or null. */
async function userIdFromToken(token: string): Promise<string | null> {
  if (!token) return null;
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, { headers: { apikey: ANON_KEY, authorization: `Bearer ${token}` } });
  if (!res.ok) return null;
  const user = await res.json().catch(() => null);
  return user?.id ?? null;
}

const b64url = (data: ArrayBuffer | Uint8Array | string) => {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = "";
  bytes.forEach((b) => (s += String.fromCharCode(b)));
  return btoa(s).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
};

/** The "client secret" Apple asks for: a JWT signed (ES256) with your Sign in with Apple key, valid for 5 minutes. */
async function appleClientSecret(): Promise<string> {
  const pem = APPLE_PRIVATE_KEY.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\\n/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: APPLE_KEY_ID }));
  const claims = b64url(JSON.stringify({ iss: APPLE_TEAM_ID, iat: now, exp: now + 300, aud: "https://appleid.apple.com", sub: APPLE_BUNDLE_ID }));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`));
  return `${header}.${claims}.${b64url(sig)}`;
}

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

Deno.serve(async (req) => {
  const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
  const userId = await userIdFromToken(jwt);
  if (!userId) return json({ error: "not signed in" }, 401);

  // 1. Tell Apple to disconnect this app from the person's Apple ID (only if we have a stored token — debug email accounts have none).
  const lookup = await fetch(`${SUPABASE_URL}/rest/v1/apple_tokens?select=refresh_token&user_id=eq.${userId}`, { headers: serviceHeaders() });
  if (!lookup.ok) return json({ error: `could not look up the Apple token (${lookup.status})` }, 500);
  const stored = (await lookup.json().catch(() => []))[0];
  if (stored?.refresh_token) {
    const res = await fetch("https://appleid.apple.com/auth/revoke", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: APPLE_BUNDLE_ID,
        client_secret: await appleClientSecret(),
        token: stored.refresh_token,
        token_type_hint: "refresh_token",
      }),
    });
    // Apple answers 200 even for tokens it no longer knows; any other answer means we should NOT delete yet.
    if (!res.ok) {
      console.error("apple revoke refused:", res.status, (await res.text().catch(() => "")).slice(0, 300));
      return json({ error: "apple revoke failed", status: res.status }, 502);
    }
  }

  // 2. Run the normal deletion as the signed-in person (it removes their data and then their sign-in account).
  const del = await fetch(`${SUPABASE_URL}/rest/v1/rpc/delete_my_account`, {
    method: "POST",
    headers: { apikey: ANON_KEY, authorization: `Bearer ${jwt}`, "content-type": "application/json" },
    body: "{}",
  });
  if (!del.ok) return json({ error: `delete failed (${del.status})`, detail: (await del.text()).slice(0, 300) }, 500);

  await fetch(`${SUPABASE_URL}/rest/v1/apple_tokens?user_id=eq.${userId}`, { method: "DELETE", headers: serviceHeaders() });
  return json({ ok: true });
});
