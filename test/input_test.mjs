import assert from "node:assert/strict";
import { classifyGameplaySwipe, menuPrimaryAction } from "../public/web/input.js";

assert.equal(classifyGameplaySwipe(80, 2), "down_right", "a nearly horizontal right swipe is accepted");
assert.equal(classifyGameplaySwipe(-80, -2), "up_left", "a nearly horizontal left swipe is accepted");
assert.equal(classifyGameplaySwipe(6, -80), "up_right", "a steep swipe with clear rightward intent is accepted");
assert.equal(classifyGameplaySwipe(-6, 80), "down_left", "a steep swipe with clear leftward intent is accepted");
assert.equal(classifyGameplaySwipe(24, 0), "down_right", "a horizontal swipe at the distance threshold is accepted");
assert.equal(classifyGameplaySwipe(0, 80), null, "a vertical swipe without side intent is ignored");
assert.equal(classifyGameplaySwipe(5, 80), null, "incidental horizontal jitter is ignored");
assert.equal(classifyGameplaySwipe(23, 0), null, "a short swipe is ignored");
assert.equal(classifyGameplaySwipe(Number.NaN, 40), null, "invalid coordinates are ignored");
assert.equal(menuPrimaryAction({ screen: "game", status: "playing" }), "resume", "an active run resumes");
assert.equal(menuPrimaryAction({ screen: "game", status: "game_over" }), "replay", "a lost run replays");
assert.equal(menuPrimaryAction({ screen: "game", status: "victory" }), "replay", "a completed run replays");
assert.equal(menuPrimaryAction({ screen: "select", status: "select" }), "play", "selection starts play");

console.log("Touch gesture classification passed");
