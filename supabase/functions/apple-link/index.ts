import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const APPLE_KEY_ID = Deno.env.get("APPLE_KEY_ID")!;
const APPLE_TEAM_ID = Deno.env.get("APPLE_TEAM_ID")!;
const APPLE_PRIVATE_KEY = Deno.env.get("APPLE_PRIVATE_KEY")!; // the whole .p8 file for the Sign in with Apple key
const APPLE_BUNDLE_ID = Deno.env.get("APPLE_BUNDLE_ID") ?? "com.dschermer.fade";

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
  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const { data: user, error: userError } = await admin.auth.getUser(jwt);
  if (userError || !user?.user) return json({ error: "not signed in" }, 401);

  const { authorizationCode } = await req.json().catch(() => ({}));
  if (!authorizationCode) return json({ error: "missing authorizationCode" }, 400);

  // Trade Apple's one-time code for a long-lived refresh token, and keep it so the connection can be revoked later.
  const res = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: APPLE_BUNDLE_ID,
      client_secret: await appleClientSecret(),
      code: authorizationCode,
      grant_type: "authorization_code",
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body.refresh_token) return json({ error: "apple refused", detail: body.error ?? res.status }, 502);

  const { error } = await admin.from("apple_tokens").upsert({ user_id: user.user.id, refresh_token: body.refresh_token });
  if (error) return json({ error: error.message }, 500);
  return json({ ok: true });
});
