import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const source = await readFile(new URL("../public/web/telemetry.js", import.meta.url), "utf8");
const { createTelemetry } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`);

function setup({ hostname = "raibert.lol", search = "", navigator = {} } = {}) {
  const calls = [];
  let options;
  const sdk = new Proxy({}, { get: (target, name) => name in target ? target[name] : (...args) => calls.push([name, ...args]) });
  const env = { location: { hostname, search }, navigator, performance: { now: () => 0 } };
  const telemetry = createTelemetry(env, async () => ({ Glitchless: { init: value => { options = value; return sdk; } } }));
  const named = name => calls.filter(call => call[0] === name).map(call => call.slice(1));
  return { telemetry, calls, named, options: () => options };
}

const live = setup();
const base = { screen: "game", status: "playing", stage: 1, score: 100, difficulty: "normal", character: "rai", deaths: 0, pickups: {}, rescues_used: 0, bonuses: {} };
live.telemetry.state(base); // queued until the SDK has loaded
await live.telemetry.start();
assert.equal(live.options().env, "prod");
assert.equal(live.options().privacy, "install");
assert.equal(live.options().sessionType, "user");
live.telemetry.state({ ...base, pickups: { shield: 1 }, rescues_used: 1 });
live.telemetry.state({ ...base, pickups: { shield: 1 }, rescues_used: 1, deaths: 1, death_cause: "bug" });
live.telemetry.state({ ...base, status: "stage_clear", pickups: { shield: 1 }, rescues_used: 1, deaths: 1 });
live.telemetry.state({ ...base, stage: 2, pickups: { shield: 1 }, rescues_used: 1, deaths: 1 });
const over = { ...base, stage: 2, status: "game_over", score: 900, pickups: { shield: 1 }, rescues_used: 1, deaths: 2, death_cause: "fall" };
live.telemetry.state(over);
live.telemetry.state(over);
assert.deepEqual(live.named("levelStart").map(args => args[0]), ["stage-01", "stage-02"]);
assert.deepEqual(live.named("levelComplete").map(args => args[0]), ["stage-01"]);
assert.deepEqual(live.named("levelFail"), [["stage-02", { cause: "fall" }]]);
assert.deepEqual(live.named("death"), [[{ cause: "bug" }], [{ cause: "fall" }]]);
const events = live.named("track");
assert.equal(events.filter(([name]) => name === "powerup").length, 1);
assert.equal(events.filter(([name]) => name === "rescue").length, 1);
const runs = events.filter(([name]) => name === "run_end");
assert.equal(runs.length, 1);
assert.equal(runs[0][1].won, false);
assert.equal(runs[0][1].deaths, 2);
// A retry is a new run that starts at stage 1.
live.telemetry.state(base);
assert.equal(live.named("levelStart").length, 3);
live.telemetry.mirror("engagement", { seconds: 5 });
assert.deepEqual(live.named("track").at(-1), ["engagement", { seconds: 5 }]);
live.telemetry.setSharing(false);
const sent = live.named("track").length;
live.telemetry.track("leaderboard_view");
assert.equal(live.named("track").length, sent);
assert.deepEqual(live.named("setEnabled").at(-1), [false]);
assert.equal(live.telemetry.canReport(), false);

for (const blocked of [{ hostname: "localhost" }, { search: "?nogd=1" }, { navigator: { doNotTrack: "1" } }, { navigator: { globalPrivacyControl: true } }]) {
  const off = setup(blocked);
  await off.telemetry.start();
  off.telemetry.state(base);
  assert.equal(off.options(), undefined);
  assert.equal(off.calls.length, 0);
}
const bot = setup({ hostname: "localhost", search: "?glitchless=1&autoplay=1" });
await bot.telemetry.start();
assert.equal(bot.options().sessionType, "synthetic");
assert.equal(bot.options().env, "dev");

const broken = createTelemetry({ location: { hostname: "raibert.lol", search: "" }, navigator: {}, performance: { now: () => 0 } }, async () => { throw new Error("offline"); });
await broken.start();
broken.state(base);
assert.equal(broken.canReport(), false);
console.log("Telemetry checks passed");
