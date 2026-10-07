import { expect, test } from "@playwright/test";
import { writeFile } from "node:fs/promises";

const emptyBoard = { version: 1, highScore: 0, entries: [] };
async function bootRuby(page, start = true) {
  // Expose the existing VM only in the intercepted test response. Production
  // has no evaluation hook. All outcomes below are driven by real Ruby rules.
  await page.route("**/web/app.js", async route => {
    const response = await route.fetch();
    const body = (await response.text()).replace(
      'vm.eval("load \'/app/web/boot.rb\'");',
      `globalThis.testRuby = vm; vm.eval("$LOAD_PATH.unshift('/app/web'); require '/app/game'; $test_window = RaiBertWindow.new; $test_window.show");`
    );
    await route.fulfill({ response, body });
  });
  await page.route("**/api/leaderboard", route => route.fulfill({ json: emptyBoard }));
  await page.goto("/");
  await expect(page.locator("#status")).toBeHidden();
  if (start) await page.keyboard.press("Enter");
}
async function ruby(page, source) {
  return page.evaluate(code => globalThis.testRuby.eval(code).toString(), source);
}
async function finishRun(page, outcome, testInfo = null) {
  await ruby(page, `
    game = $test_window.instance_variable_get(:@game)
    game.instance_variable_set(:@score, 100)
    if '${outcome}' == 'victory'
      game.instance_variable_set(:@stage, 20)
      game.send(:setup_stage, $test_window.send(:game_time))
      game.tiles.each_key { |tile| game.tiles[tile] = game.target }
      direction, destination = game.neighbors.first
      game.tiles[destination] = game.target - 1
      $test_window.press(direction)
    else
      game.instance_variable_set(:@lives, 1)
      $test_window.press(:up_left)
    end
  `);
  await expect(page.locator("#ending-dialog")).toBeVisible();
  await expect(page.locator("#leaderboard-dialog")).toBeHidden();
  await expect(page.locator("#ending-title")).toHaveText(outcome === "victory" ? "Pipeline shipped!" : "Game over");
  if (testInfo) await page.screenshot({ path: testInfo.outputPath("ending.png") });
  await expect(page.locator("#leaderboard-dialog")).toBeVisible();
  await expect(page.locator("#run-outcome")).toHaveText(outcome === "victory" ? "Victory! All 20 stages cleared" : "Game over");
  await expect(page.locator("#run-summary")).toContainText(outcome === "victory" ? "Stage 20" : "Stage 1");
}
async function assertRestart(page) {
  await expect(page.locator("#leaderboard-dialog")).toBeHidden();
  await expect(page.locator("#game")).toBeFocused();
  // The initial tile awards 100 points in a fresh game.
  expect(JSON.parse(await ruby(page, 'g = $test_window.instance_variable_get(:@game); [g.status, g.score, g.stage, g.lives].to_json'))).toEqual(["playing", 100, 1, 3]);
}
for (const outcome of ["game_over", "victory"]) {
  test(`actual Ruby ${outcome} shows result and restarts through Retry game`, async ({ page }, testInfo) => {
    await bootRuby(page);
    await finishRun(page, outcome, testInfo);
    await expect(page.getByRole("button", { name: "Refresh scoreboard" })).toBeVisible();
    await expect(page.locator("#initials-form")).toBeVisible();
    await page.getByRole("button", { name: "Skip score", exact: true }).click();
    await expect(page.locator("#run-result")).toBeVisible();
    await page.screenshot({ path: testInfo.outputPath(`${outcome}.png`) });
    const replay = page.getByRole("button", { name: "Retry game", exact: true });
    if (testInfo.project.name === "mobile-chromium") await replay.tap();
    else { await replay.focus(); await page.keyboard.press("Enter"); }
    await assertRestart(page);
  });
}
test("nonqualifying and offline runs retain their outcome and replay", async ({ page }, testInfo) => {
  await bootRuby(page);
  await page.unroute("**/api/leaderboard");
  const entries = Array.from({ length: 15 }, (_, i) => ({ id: `score-${i}`, rank: i + 1, initials: ["ACE", "JAX", "RUB", "NEO", "PIX"][i % 5], score: 256400 - i * 11340, stage: Math.max(4, 20 - i), difficulty: i % 2 ? "normal" : "hard", outcome: i < 3 ? "victory" : "game_over" }));
  await page.route("**/api/leaderboard", route => route.fulfill({ json: { ...emptyBoard, entries } }));
  await finishRun(page, "game_over");
  await expect(page.locator("#initials-form")).toBeHidden();
  await expect(page.locator("#leaderboard-status")).toContainText("did not reach");
  await page.screenshot({ path: testInfo.outputPath("scoreboard-ranked.png") });
  await page.unroute("**/api/leaderboard");
  await page.route("**/api/leaderboard", route => route.abort());
  await page.getByRole("button", { name: "Refresh scoreboard" }).click();
  await expect(page.locator("#leaderboard-status")).toContainText("Offline");
  await expect(page.locator("#initials-form")).toBeVisible();
  if (await page.getByRole("button", { name: "Skip score", exact: true }).isVisible()) await page.getByRole("button", { name: "Skip score", exact: true }).click();
  await page.getByRole("button", { name: "Retry game", exact: true }).click();
  await assertRestart(page);
  await page.evaluate(() => localStorage.setItem("raibert.leaderboard.cache", "malformed"));
  await finishRun(page, "game_over");
  await expect(page.locator("#leaderboard-status")).toContainText("Leaderboard unavailable");
  await expect(page.locator("#initials-form")).toBeVisible();
  if (await page.getByRole("button", { name: "Skip score", exact: true }).isVisible()) await page.getByRole("button", { name: "Skip score", exact: true }).click();
  await page.getByRole("button", { name: "Retry game", exact: true }).click();
  await assertRestart(page);
});
test("submission failure can retry and pending submission blocks replay", async ({ page }) => {
  await bootRuby(page);
  await finishRun(page, "game_over");
  await page.unroute("**/api/leaderboard");
  let submitCount = 0;
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  await page.route("**/api/leaderboard", async route => {
    if (route.request().method() !== "POST") return route.fulfill({ json: emptyBoard });
    submitCount++;
    if (submitCount === 1) return route.fulfill({ status: 503, json: { error: "Try later" } });
    await gate;
    await route.fulfill({ json: { ...emptyBoard, rank: 1 } });
  });
  await page.locator("#initials").fill("RAI");
  await page.getByRole("button", { name: "Submit score" }).click();
  await expect(page.locator("#leaderboard-status")).toContainText("Submission failed");
  await page.getByRole("button", { name: "Submit score" }).click();
  await expect(page.getByRole("button", { name: "Retry game", exact: true })).toBeHidden();
  await expect(page.getByRole("button", { name: "Submit score", exact: true })).toBeDisabled();
  await page.keyboard.press("Escape");
  await expect(page.locator("#leaderboard-dialog")).toBeVisible();
  release();
  await expect(page.locator("#leaderboard-status")).toHaveText("Accepted at rank 1.");
  if (await page.getByRole("button", { name: "Skip score", exact: true }).isVisible()) await page.getByRole("button", { name: "Skip score", exact: true }).click();
  await page.getByRole("button", { name: "Retry game", exact: true }).click();
  await assertRestart(page);
  expect(submitCount).toBe(2);
});

test("selection, preset, persisted guidance, and reset stay usable", async ({ page }, testInfo) => {
  await bootRuby(page, false);
  await page.screenshot({ path: testInfo.outputPath("selection.png") });
  await page.keyboard.press("KeyO");
  await page.screenshot({ path: testInfo.outputPath("controls.png") });
  for (let i = 0; i < 4; i++) await page.keyboard.press("ArrowDown");
  await page.keyboard.press("Enter");
  await expect.poll(() => page.evaluate(() => JSON.parse(localStorage.getItem("raibert.settings.v1")).game.controls)).toEqual({ up_left: ["q"], up_right: ["r"], down_left: ["s"], down_right: ["d"] });
  await page.reload();
  await expect(page.locator("#status")).toBeHidden();
  await expect(page.locator("#game")).toHaveAttribute("aria-label", /up-right: R; down-left: S/);
  await page.keyboard.press("KeyS");
  expect(await ruby(page, '$test_window.instance_variable_get(:@difficulty_selection)')).toBe("2");
  await page.keyboard.press("KeyO");
  for (let i = 0; i < 5; i++) await page.keyboard.press("ArrowDown");
  await page.keyboard.press("Enter");
  await expect(page.locator("#game")).toHaveAttribute("aria-label", /up-right: E; down-left: A/);
});

test("rescue cues render across the campaign and frame timing is recorded", async ({ page }, testInfo) => {
  await bootRuby(page);
  for (const stage of [1, 2, 3, 4, 15, 18, 20]) {
    await ruby(page, `g = $test_window.instance_variable_get(:@game); g.instance_variable_set(:@stage, ${stage}); g.send(:setup_stage, $test_window.send(:game_time)); $test_window.update; $test_window.draw; Gosu.flush`);
    await page.screenshot({ path: testInfo.outputPath(`rescue-stage-${stage}.png`) });
  }
  const timing = await page.evaluate(() => new Promise(resolve => {
    const intervals = []; let previous;
    function frame(now) {
      if (previous !== undefined) intervals.push(now - previous);
      previous = now;
      if (intervals.length < 60) requestAnimationFrame(frame);
      else { const sorted = intervals.toSorted((a, b) => a - b); resolve({ medianMs: sorted[30], p95Ms: sorted[57], maxMs: sorted[59], samples: sorted.length }); }
    }
    requestAnimationFrame(frame);
  }));
  await testInfo.attach("frame-timing", { body: JSON.stringify(timing), contentType: "application/json" });
  await writeFile(testInfo.outputPath("frame-timing.json"), JSON.stringify(timing, null, 2));
  expect(timing.samples).toBe(60);
});

test("menu Replay resets a real ended run and clears its submission", async ({ page }) => {
  await bootRuby(page);
  await finishRun(page, "game_over");
  await page.getByRole("button", { name: "Close leaderboard", exact: true }).click();
  await page.locator("#game").click({ position: { x: 80, y: 180 } });
  await page.getByRole("button", { name: "Replay", exact: true }).click();
  await expect(page.locator("#menu-dialog")).toBeHidden();
  await assertRestart(page);
  await page.keyboard.press("KeyL");
  await page.getByRole("button", { name: "Refresh scoreboard" }).click();
  await expect(page.locator("#initials-form")).toBeHidden();
  await expect(page.locator("#run-result")).toBeHidden();
});

test('ending supports reduced motion, mute, and an immediate leaderboard transition', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await bootRuby(page);
  await page.keyboard.press('KeyM');
  await page.evaluate(() => {
    globalThis.endingOscillators = 0;
    const original = AudioContext.prototype.createOscillator;
    AudioContext.prototype.createOscillator = function (...args) { globalThis.endingOscillators++; return original.apply(this, args); };
  });
  await ruby(page, 'g = $test_window.instance_variable_get(:@game); g.instance_variable_set(:@lives, 1); $test_window.press(:up_left)');
  await expect(page.locator('#ending-dialog')).toBeVisible();
  await expect(page.locator('#ending-score')).toHaveText('Final score: 100');
  expect(await page.locator('#ending-title').evaluate(element => getComputedStyle(element).animationName)).toBe('none');
  expect(await page.evaluate(() => globalThis.endingOscillators)).toBe(0);
  await page.getByRole('button', { name: 'View leaderboard', exact: true }).click();
  await expect(page.locator('#ending-dialog')).toBeHidden();
  await expect(page.locator('#leaderboard-dialog')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Refresh scoreboard' })).toContainText('Refresh');
  await expect(page.getByRole('button', { name: 'Retry game', exact: true })).toBeHidden();
  await page.getByRole('button', { name: 'Skip score', exact: true }).click();
  await page.getByRole('button', { name: 'Retry game', exact: true }).click();
  await assertRestart(page);
});

test('pausing preserves the remaining speed bonus', async ({ page }) => {
  await bootRuby(page);
  await page.keyboard.press('Escape');
  const before = await ruby(page, '$test_window.instance_variable_get(:@game).speed_bonus($test_window.send(:game_time))');
  await page.waitForTimeout(300);
  expect(await ruby(page, '$test_window.instance_variable_get(:@game).speed_bonus($test_window.send(:game_time))')).toBe(before);
});
