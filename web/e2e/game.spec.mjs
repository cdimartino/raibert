import { expect, test } from "@playwright/test";

async function waitForGame(page) {
  await page.route("**/api/leaderboard", route => route.fulfill({ json: { version: 1, highScore: 256400, entries: [] } }));
  await page.goto("/");
  await expect(page.locator("#status")).toBeHidden({ timeout: 120_000 });
  await expect(page.locator("#game")).toBeFocused();
}

async function canvasFrame(page) {
  return page.locator("#game").evaluate(canvas => canvas.toDataURL());
}

test("loads the Ruby/Wasm game and completes a keyboard journey", async ({ page }) => {
  const pageErrors = [];
  page.on("pageerror", error => pageErrors.push(error.message));

  await waitForGame(page);
  const selectionFrame = await canvasFrame(page);

  await page.keyboard.press("Enter");
  await expect.poll(() => canvasFrame(page)).not.toBe(selectionFrame);
  const playingFrame = await canvasFrame(page);

  await page.keyboard.press("KeyD");
  await expect.poll(() => canvasFrame(page)).not.toBe(playingFrame);

  await page.keyboard.press("Escape");
  await expect(page.locator("#status")).toBeHidden();
  expect(pageErrors).toEqual([]);
});

async function swipe(page, from, to) {
  await page.locator("#game").dispatchEvent("pointerdown", { pointerId: 1, pointerType: "touch", clientX: from.x, clientY: from.y });
  await page.locator("#game").dispatchEvent("pointermove", { pointerId: 1, pointerType: "touch", clientX: to.x, clientY: to.y });
  await page.locator("#game").dispatchEvent("pointerup", { pointerId: 1, pointerType: "touch", clientX: to.x, clientY: to.y });
}

test("portrait gestures fill the viewport and the optional controls persist", async ({ page }) => {
  const pageErrors = [];
  page.on("pageerror", error => pageErrors.push(error.message));

  await page.setViewportSize({ width: 390, height: 844 });
  await waitForGame(page);
  const selectionFrame = await canvasFrame(page);
  await swipe(page, { x: 250, y: 400 }, { x: 170, y: 400 });
  await expect.poll(() => canvasFrame(page)).not.toBe(selectionFrame);
  await page.locator("#game").click({ position: { x: 195, y: 420 } });
  const playingFrame = await canvasFrame(page);
  await swipe(page, { x: 200, y: 400 }, { x: 260, y: 460 });
  await expect.poll(() => canvasFrame(page)).not.toBe(playingFrame);
  await page.locator("#game").click({ position: { x: 40, y: 700 } });
  await expect(page.locator("#menu-dialog")).toBeVisible();
  await page.locator("#floating-toggle").check();
  await page.getByRole("button", { name: "Resume" }).click();
  await expect(page.locator("#floating-controls")).toBeVisible();
  await page.reload();
  await expect(page.locator("#floating-controls")).toBeVisible({ timeout: 120_000 });
  await expect(page.locator("#status")).toBeHidden();
  const canvasBox = await page.locator("#game").boundingBox();
  expect(canvasBox.width).toBe(390); expect(canvasBox.height).toBe(844);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.documentElement.scrollHeight <= innerHeight)).toBe(true);
  expect(pageErrors).toEqual([]);
});

test("leaderboard is keyboard accessible and survives an offline refresh", async ({ page }) => {
  await waitForGame(page);
  await page.keyboard.press("KeyL");
  await expect(page.locator("#leaderboard-dialog")).toBeVisible();
  await expect(page.getByText("The board is empty. Be first.")).toBeVisible();
  await page.unroute("**/api/leaderboard");
  await page.route("**/api/leaderboard", route => route.abort());
  await page.getByRole("button", { name: "Retry" }).click();
  await expect(page.getByText(/cached scores/)).toBeVisible();
  await page.getByRole("button", { name: "Close" }).last().click();
  await expect(page.locator("#game")).toBeFocused();
});

test("landscape rotation keeps the active run and safe viewport", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await waitForGame(page);
  await page.locator("#game").click({ position: { x: 195, y: 420 } });
  await page.setViewportSize({ width: 844, height: 390 });
  await expect(page.locator("#status")).toBeHidden();
  const before = await canvasFrame(page);
  await swipe(page, { x: 400, y: 180 }, { x: 460, y: 240 });
  await expect.poll(() => canvasFrame(page)).not.toBe(before);
  const box = await page.locator("#game").boundingBox();
  expect(box.width).toBe(844); expect(box.height).toBe(390);
});
