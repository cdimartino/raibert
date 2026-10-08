import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { webcrypto } from "node:crypto";
const source = await readFile(new URL("../public/web/analytics.js", import.meta.url), "utf8");
const { createAnalytics } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`);
function environment() {
  const requests = [], handlers = {}, storage = new Map();
  let now = 0;
  const env = { location: { hostname: "raibert.lol" }, navigator: {},
    document: { referrer: "https://example.com/private?secret=1", visibilityState: "visible",
      addEventListener: (name, callback) => { handlers[name] = callback; } },
    matchMedia: () => ({ matches: false }), performance: { now: () => now }, crypto: webcrypto,
    sessionStorage: { getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value) },
    fetch: async (url, options) => { requests.push({ url, ...options, data: JSON.parse(options.body) }); },
    setInterval: callback => { handlers.interval = callback; },
    addEventListener: (name, callback) => { handlers[name] = callback; }
  };
  return { env, requests, handlers, advance: milliseconds => { now += milliseconds; } };
}
const settle = async () => { await new Promise(resolve => setTimeout(resolve, 30)); };
const test = environment();
const analytics = createAnalytics(test.env);
const playing = { screen: "game", status: "playing", paused: false };
analytics.state(playing); analytics.state(playing);
analytics.state({ ...playing, status: "stage_clear" }); analytics.state(playing);
test.advance(10_000); analytics.state({ ...playing, paused: true });
test.advance(20_000); analytics.state(playing);
test.advance(5000); test.env.document.visibilityState = "hidden"; test.handlers.visibilitychange();
test.advance(30_000); test.handlers.interval();
test.env.document.visibilityState = "visible"; test.handlers.visibilitychange();
test.advance(5000); analytics.state({ screen: "game", status: "game_over" });
analytics.state({ screen: "game", status: "game_over" });
test.handlers.pagehide();
await settle();
assert.equal(test.requests.filter(r => r.data.event === "game_start").length, 1);
assert.equal(test.requests.filter(r => r.data.event === "game_over").length, 1);
assert.equal(test.requests.filter(r => r.data.event === "engagement").reduce((sum, r) => sum + r.data.seconds, 0), 20);
for (const request of test.requests) {
  assert.equal(request.data.referrer, "example.com");
  const expected = Buffer.from(await webcrypto.subtle.digest("SHA-256", new TextEncoder().encode(request.body))).toString("hex");
  assert.equal(request.headers["x-amz-content-sha256"], expected);
}
createAnalytics(test.env); await settle();
assert.equal(test.requests.filter(r => r.data.event === "session_start").length, 1);
for (const override of [{ hostname: "localhost" }, { doNotTrack: "1" }, { globalPrivacyControl: true }]) {
  const disabled = environment();
  Object.assign(override.hostname ? disabled.env.location : disabled.env.navigator, override);
  createAnalytics(disabled.env).state(playing);
  await settle(); assert.equal(disabled.requests.length, 0);
}
const failed = environment(); failed.env.fetch = async () => { throw new Error("offline"); };
createAnalytics(failed.env).state(playing); await settle();
console.log("Analytics browser checks passed");
const diagnostic = environment();
diagnostic.env.navigator.userAgent = 'Mozilla/5.0 Chrome/140.0.0.0 Safari/537.36';
const reporter = createAnalytics(diagnostic.env);
reporter.error('TypeError: private secret user@example.com https://private.example/token\n at draw (https://raibert.lol/web/app.js:321:7)', 'gameplay', 'ruby-c9197c67427b1d81.wasm');
reporter.error('Error: duplicate', 'assets');
await settle();
const errors = diagnostic.requests.filter(r => r.data.event === 'runtime_error');
assert.equal(errors.length, 1);
assert.deepEqual(errors[0].data.diagnostics, { release: '2026-10-08.1', browser: 'Chrome', errorType: 'TypeError', phase: 'gameplay', runtime: 'ruby-c9197c67427b1d81.wasm', source: 'web/app.js', line: 321 });
assert.ok(!errors[0].body.includes('secret'));
assert.ok(!errors[0].body.includes('private.example'));
const unknown = environment();
createAnalytics(unknown.env).error('private arbitrary error /home/name/secret.rb:20', 'private phase', 'private runtime');
await settle();
assert.deepEqual(unknown.requests.find(r => r.data.event === 'runtime_error').data.diagnostics, {release:'2026-10-08.1',browser:'unknown',errorType:'unknown',phase:'unknown',runtime:'unknown',source:'unknown',line:0});
const privateEnv = environment(); privateEnv.env.navigator.globalPrivacyControl = true;
createAnalytics(privateEnv.env).error('Error: test'); await settle(); assert.equal(privateEnv.requests.length, 0);
console.log('Diagnostic privacy, deduplication and opt-out checks passed');
