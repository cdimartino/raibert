// Run with node test/audio_test.mjs. No browser or extra packages required.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("../public/web/app.js", import.meta.url), "utf8");
const AudioEngine = runInNewContext(`${source.slice(source.indexOf("class AudioEngine"), source.indexOf("\nconst audio ="))}; AudioEngine`);
const starts = [];
const stops = [];
const ramps = [];
const engine = new AudioEngine();
engine.context = {
  currentTime: 0,
  state: "running",
  destination: {},
  createBufferSource() {
    return {
      connect(node) { return node; },
      start(...args) { starts.push(args); },
      stop(time) { stops.push(time); },
      playbackRate: {},
    };
  },
  createGain() {
    return {
      connect() {},
      gain: {
        setValueAtTime() {},
        linearRampToValueAtTime(value, time) { ramps.push([value, time]); },
        cancelAndHoldAtTime() {},
      },
    };
  },
};
engine.buffer = async () => ({ duration: 32 });
await engine.playSong("build", 0.18, true);
assert.equal(starts.length, 1);
assert.deepEqual(ramps.at(-1), [0.18, 0.04]);
engine.context.currentTime = 3;
engine.pauseSong();
assert.deepEqual(ramps.at(-1), [0, 3.04]);
assert.equal(stops.at(-1), 3.04);
engine.resume(); // Every key/touch unlocks audio, including while muted or paused.
await Promise.resolve();
assert.equal(starts.length, 1, "input must not restart paused or muted music");
await engine.playSong("build", 0.18, true);
assert.deepEqual(starts.at(-1), [0, 3], "explicit resume preserves position");
engine.stopSong();
assert.equal(engine.song, null);

let decode;
engine.buffer = () => new Promise(resolve => { decode = resolve; });
const pending = engine.playSong("test", 0.18, true);
engine.pauseSong();
decode({ duration: 32 });
await pending;
engine.resume();
await Promise.resolve();
assert.equal(starts.length, 2, "muting during decode cancels the pending song");
engine.stopSong();

const assets = JSON.parse(readFileSync(new URL("../public/web/assets.json", import.meta.url)));
assert.equal(assets.effects.length, 15);
for (const path of [...assets.effects, assets.initialSong]) {
  const wav = readFileSync(new URL(`..${path}`, import.meta.url));
  assert.equal(wav.toString("ascii", 0, 4), "RIFF", `${path} is a real WAV`);
  assert.equal(wav.toString("ascii", 8, 12), "WAVE");
}
console.log("Audio routing, fades, pause/mute races, and preload assets passed");
