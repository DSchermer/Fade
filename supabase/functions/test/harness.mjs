import { generateKeyPairSync } from "node:crypto";
const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const PEM = privateKey.export({ type: "pkcs8", format: "pem" });
const which = process.argv[2];
const ENV = {
  SUPABASE_URL: "https://proj.supabase.co", SUPABASE_SERVICE_ROLE_KEY: "sb_secret_" + "x".repeat(31), SUPABASE_ANON_KEY: "sb_publishable_abc",
  APNS_KEY_ID: "KEYID12345", APNS_TEAM_ID: "TEAMID1234", APNS_PRIVATE_KEY: PEM, APNS_BUNDLE_ID: "com.dschermer.fade", PUSH_SECRET: "s3cret",
  APPLE_KEY_ID: "KEYID67890", APPLE_TEAM_ID: "TEAMID1234", APPLE_PRIVATE_KEY: PEM.trim().replace(/\n/g, "\\n"), APPLE_BUNDLE_ID: "com.dschermer.fade",
};
globalThis.Deno = { env: { get: (k) => ENV[k] }, serve: (h) => { globalThis.handler = h; } };
const calls = [];
let responder = () => new Response("{}", { status: 200 });
globalThis.fetch = async (url, init = {}) => { calls.push({ url: String(url), method: init.method ?? "GET", headers: init.headers ?? {}, body: init.body }); return responder(String(url), init); };
await import(`${process.env.FN_DIR}/${which}.mts`);
const assert = (c, m) => { if (!c) { console.log("FAIL:", m); process.exitCode = 1; } else console.log("ok:", m); };
const J = (o, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { "content-type": "application/json" } });

if (which === "send-push") {
  let r = await handler(new Request("https://f/", { method: "POST" }));
  assert(r.status === 403 && calls.length === 0, "no credentials -> 403, nothing called");
  r = await handler(new Request("https://f/", { method: "POST", headers: { Authorization: "Bearer eyJwrongkey" } }));
  assert(r.status === 403 && calls.length === 0, "wrong bearer -> 403");
  responder = (url) => {
    if (url.endsWith("claim_notifications")) return J([{ id: 7, token: "ab".repeat(32), environment: "sandbox", title: "T", body: "B", data: { group_id: "g1" } },
                                                       { id: 7, token: "cd".repeat(32), environment: "production", title: "T", body: "B", data: { group_id: "g1" } },
                                                       { id: 8, token: "ef".repeat(32), environment: "sandbox", title: "T2", body: "B2", data: {} }]);
    if (url.includes("push.apple.com")) return url.includes("cdcdcd") ? J({ reason: "BadDeviceToken" }, 400) : new Response("", { status: 200 });
    return new Response(null, { status: 204 });
  };
  r = await handler(new Request("https://f/", { method: "POST", headers: { "x-push-secret": "s3cret", Authorization: "Bearer eyJanything" } }));
  const body = await r.json();
  assert(r.status === 200 && body.sent === 2 && body.failed === 0, `with the shared secret: 200, sent=2 (${JSON.stringify(body)})`);
  const claim = calls.find((c) => c.url.endsWith("claim_notifications"));
  assert(claim.headers.apikey.startsWith("sb_secret_") && !claim.headers.authorization, "new-style key sent as apikey only");
  assert(JSON.parse(claim.body).p_limit === 100, "claim asks for 100");
  const apns = calls.filter((c) => c.url.includes("push.apple.com"));
  assert(apns.length === 3 && apns[0].url.startsWith("https://api.sandbox.push.apple.com/3/device/") && apns[1].url.startsWith("https://api.push.apple.com/"), "sandbox/production hosts chosen per token");
  assert(/^bearer [\w-]+\.[\w-]+\.[\w-]+$/.test(apns[0].headers.authorization) && apns[0].headers["apns-topic"] === "com.dschermer.fade", "APNs JWT + topic");
  const fins = calls.filter((c) => c.url.endsWith("finish_notification")).map((c) => JSON.parse(c.body));
  assert(fins.length === 2 && fins[0].p_ok === true && fins[0].p_dead_tokens.length === 1 && fins[1].p_ok === true, `finish called per message, dead token reported (${JSON.stringify(fins[0])})`);
  responder = () => new Response("boom", { status: 500 });
  r = await handler(new Request("https://f/", { method: "POST", headers: { "x-push-secret": "s3cret" } }));
  assert(r.status === 500, "database error -> 500");
}
if (which === "apple-link") {
  let r = await handler(new Request("https://f/", { method: "POST", headers: { Authorization: "Bearer jwt1" }, body: JSON.stringify({ authorizationCode: "c0de" }) }));
  responder = () => new Response("{}", { status: 401 });
  r = await handler(new Request("https://f/", { method: "POST", headers: { Authorization: "Bearer jwt1" }, body: JSON.stringify({ authorizationCode: "c0de" }) }));
  assert(r.status === 401, "bad token -> 401");
  calls.length = 0;
  responder = (url) => {
    if (url.endsWith("/auth/v1/user")) return J({ id: "user-1" });
    if (url.includes("appleid.apple.com/auth/token")) return J({ refresh_token: "rt-123" });
    return new Response("", { status: 201 });
  };
  r = await handler(new Request("https://f/", { method: "POST", headers: { Authorization: "Bearer jwt1" }, body: JSON.stringify({ authorizationCode: "c0de" }) }));
  assert(r.status === 200, "happy path 200");
  const u = calls.find((c) => c.url.endsWith("/auth/v1/user"));
  assert(u.headers.apikey === "sb_publishable_abc" && u.headers.authorization === "Bearer jwt1", "caller identified with their own token");
  const tok = calls.find((c) => c.url.includes("appleid.apple.com/auth/token"));
  const params = new URLSearchParams(tok.body);
  assert(params.get("code") === "c0de" && params.get("client_id") === "com.dschermer.fade" && params.get("client_secret").split(".").length === 3, "Apple token request (client secret is a signed JWT, key with literal \\n worked)");
  const save = calls.find((c) => c.url.includes("/rest/v1/apple_tokens"));
  assert(JSON.parse(save.body).refresh_token === "rt-123" && JSON.parse(save.body).user_id === "user-1" && save.headers.prefer.includes("merge-duplicates"), "token saved with upsert");
  responder = (url) => url.endsWith("/auth/v1/user") ? J({ id: "user-1" }) : url.includes("appleid") ? J({ error: "invalid_grant" }, 400) : new Response("", { status: 201 });
  r = await handler(new Request("https://f/", { method: "POST", headers: { Authorization: "Bearer jwt1" }, body: JSON.stringify({ authorizationCode: "bad" }) }));
  assert(r.status === 502, "Apple refuses -> 502");
}
if (which === "apple-delete-account") {
  responder = (url, init) => {
    if (url.endsWith("/auth/v1/user")) return J({ id: "user-9" });
    if (url.includes("apple_tokens") && (init.method ?? "GET") === "GET") return J([{ refresh_token: "rt-9" }]);
    if (url.includes("appleid.apple.com/auth/revoke")) return new Response("", { status: 200 });
    return new Response(null, { status: 204 });
  };
  let r = await handler(new Request("https://f/", { method: "POST", headers: { Authorization: "Bearer jwt9" } }));
  assert(r.status === 200, "happy path 200");
  const order = calls.map((c) => c.url.replace("https://proj.supabase.co", "").replace(/\?.*/, "")).join(" | ");
  console.log("   order:", order);
  const idx = (s) => calls.findIndex((c) => c.url.includes(s));
  assert(idx("auth/revoke") < idx("rpc/delete_my_account") && idx("rpc/delete_my_account") < calls.findIndex((c) => c.method === "DELETE"), "Apple revoked first, then the account deleted, then the stored token removed");
  const del = calls.find((c) => c.url.endsWith("rpc/delete_my_account"));
  assert(del.headers.authorization === "Bearer jwt9" && del.headers.apikey === "sb_publishable_abc", "deletion runs AS the caller");
  const rev = calls.find((c) => c.url.includes("auth/revoke"));
  assert(new URLSearchParams(rev.body).get("token") === "rt-9", "revoke uses the stored token");
  calls.length = 0;
  responder = (url, init) => url.endsWith("/auth/v1/user") ? J({ id: "user-9" }) : url.includes("apple_tokens") ? J([{ refresh_token: "rt-9" }]) : url.includes("revoke") ? new Response("no", { status: 500 }) : new Response(null, { status: 204 });
  r = await handler(new Request("https://f/", { method: "POST", headers: { Authorization: "Bearer jwt9" } }));
  assert(r.status === 502 && !calls.some((c) => c.url.includes("delete_my_account")), "Apple revoke fails -> 502 and NOTHING deleted");
  calls.length = 0;
  responder = (url, init) => url.endsWith("/auth/v1/user") ? J({ id: "user-9" }) : url.includes("apple_tokens") && (init.method ?? "GET") === "GET" ? J([]) : new Response(null, { status: 204 });
  r = await handler(new Request("https://f/", { method: "POST", headers: { Authorization: "Bearer jwt9" } }));
  assert(r.status === 200 && !calls.some((c) => c.url.includes("auth/revoke")), "no stored token (debug account) -> straight to deletion");
  responder = () => new Response("{}", { status: 401 });
  r = await handler(new Request("https://f/", { method: "POST", headers: {} }));
  assert(r.status === 401, "not signed in -> 401");
}
