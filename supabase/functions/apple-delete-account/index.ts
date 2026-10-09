import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const APPLE_KEY_ID = Deno.env.get("APPLE_KEY_ID")!;
const APPLE_TEAM_ID = Deno.env.get("APPLE_TEAM_ID")!;
const APPLE_PRIVATE_KEY = Deno.env.get("APPLE_PRIVATE_KEY")!;
const APPLE_BUNDLE_ID = Deno.env.get("APPLE_BUNDLE_ID") ?? "com.dschermer.fadeapp";

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
  const userId = user.user.id;

  // 1. Tell Apple to disconnect this app from the person's Apple ID (only if we have a stored token — debug email accounts have none).
  const { data: stored } = await admin.from("apple_tokens").select("refresh_token").eq("user_id", userId).maybeSingle();
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
    if (!res.ok) return json({ error: "apple revoke failed", status: res.status }, 502);
  }

  // 2. Run the normal deletion as the signed-in person (it removes their data and then their sign-in account).
  const asUser = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: `Bearer ${jwt}` } }, auth: { persistSession: false } });
  const { error } = await asUser.rpc("delete_my_account");
  if (error) return json({ error: error.message }, 500);

  await admin.from("apple_tokens").delete().eq("user_id", userId);
  return json({ ok: true });
});
