import { chromium } from "playwright";

const origin = process.env.RAIBERT_URL || "http://127.0.0.1:9292";
const entries = Array.from({ length: 15 }, (_, index) => ({
  id: `capture-${index}`, rank: index + 1, initials: ["RAI", "RBY", "DEV", "OPS", "QBT"][index % 5],
  score: 256400 - index * 12700, stage: 20 - index, difficulty: ["hard", "normal", "easy"][index % 3], outcome: index ? "game_over" : "victory"
}));

async function prepare(page) {
  await page.route("**/api/leaderboard", route => route.fulfill({ json: { version: 8, highScore: 256400, entries } }));
  await page.goto(origin);
  await page.locator("#status").waitFor({ state: "hidden", timeout: 120000 });
}

const browser = await chromium.launch();
const desktop = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
await prepare(desktop);
await desktop.keyboard.press("Enter");
await desktop.waitForTimeout(900);
await desktop.screenshot({ path: "../docs/screenshots/desktop-gameplay.png" });
await desktop.keyboard.press("KeyL");
await desktop.locator("#leaderboard-dialog").waitFor({ state: "visible" });
await desktop.waitForTimeout(1000);
await desktop.locator("#leaderboard-rows tr").first().evaluate(row => row.classList.add("new-entry"));
await desktop.screenshot({ path: "../docs/screenshots/leaderboard.png" });

for (const [name, overlay] of [["mobile-gameplay", false], ["mobile-controls", true]]) {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
  await page.addInitScript(value => localStorage.setItem("raibert.settings.v1", JSON.stringify({ version: 1, overlay: { enabled: value, portrait: { x: .56, y: .7 }, landscape: { x: .78, y: .62 } }, game: { muted: true, selection: 0, difficulty: "normal" }, initials: "RAI" })), overlay);
  await prepare(page);
  await page.locator("#game").click({ position: { x: 195, y: 420 } });
  await page.waitForTimeout(900);
  await page.screenshot({ path: `../docs/screenshots/${name}.png` });
  await page.close();
}
await browser.close();
