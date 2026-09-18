import { expect, test } from "@playwright/test";

async function waitForGame(page) {
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

test("touch controls cover options, start, movement, mute, and pause", async ({ page }) => {
  const pageErrors = [];
  page.on("pageerror", error => pageErrors.push(error.message));

  await waitForGame(page);
  const selectionFrame = await canvasFrame(page);

  await page.getByRole("button", { name: "Options" }).click();
  await expect.poll(() => canvasFrame(page)).not.toBe(selectionFrame);
  await page.getByRole("button", { name: "Pause / back" }).click();
  await page.getByRole("button", { name: "Start / confirm" }).click();
  await page.getByRole("button", { name: "Move down-right" }).click();
  await page.getByRole("button", { name: "Mute" }).click();
  await page.getByRole("button", { name: "Pause / back" }).click();

  await expect(page.locator("#status")).toBeHidden();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true);
  expect(pageErrors).toEqual([]);
});
