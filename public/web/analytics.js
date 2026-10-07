// Aggregate, first-party analytics. Tracking never blocks gameplay.
export function createAnalytics(env = globalThis) {
  const enabled = env.location.hostname === "raibert.lol" &&
    env.navigator.doNotTrack !== "1" && !env.navigator.globalPrivacyControl;
  let referrer = "direct";
  try { referrer = new URL(env.document.referrer).hostname.toLowerCase(); } catch {}
  const device = env.matchMedia("(pointer: coarse)").matches ? "mobile" : "desktop";
  function track(event, extra = {}) {
    if (!enabled) return;
    try {
      const body = JSON.stringify({ event, device, referrer, ...extra });
      // CloudFront's signed Lambda origin requires a SHA-256 payload hash.
      env.crypto.subtle.digest("SHA-256", new TextEncoder().encode(body)).then(hash => {
        const digest = Array.from(new Uint8Array(hash), byte => byte.toString(16).padStart(2, "0")).join("");
        return env.fetch("/api/analytics", { method: "POST", keepalive: true,
          headers: { "content-type": "application/json", "x-amz-content-sha256": digest }, body });
      }).catch(() => {});
    } catch {}
  }
  let playing = false;
  let last = env.performance.now();
  let activeMilliseconds = 0;
  function accrue() {
    const now = env.performance.now();
    if (playing && env.document.visibilityState === "visible") activeMilliseconds += Math.max(0, now - last);
    last = now;
  }
  function flush() {
    const seconds = Math.min(3600, Math.floor(activeMilliseconds / 1000));
    if (seconds > 0) { activeMilliseconds -= seconds * 1000; track("engagement", { seconds }); }
  }
  function state(next) {
    accrue();
    const inRun = next.screen === "game" && ["playing", "stage_clear"].includes(next.status);
    if (inRun && !running) track("game_start");
    if (running && ["game_over", "victory"].includes(next.status)) track(next.status);
    running = inRun;
    playing = inRun && next.status === "playing" && !next.paused;
  }
  let running = false;
  if (enabled) {
    track("page_view");
    try {
      if (!env.sessionStorage.getItem("raibert.analytics.session")) {
        track("session_start");
        env.sessionStorage.setItem("raibert.analytics.session", "1");
      }
    } catch { track("session_start"); }
    // Flush while the page is open as well as on exit; unload delivery is best effort.
    env.setInterval(() => { accrue(); flush(); }, 60_000);
    env.document.addEventListener("visibilitychange", () => {
      // On becoming hidden, the elapsed interval was still visible.
      if (env.document.visibilityState === "hidden" && playing) {
        activeMilliseconds += Math.max(0, env.performance.now() - last);
      }
      last = env.performance.now();
      flush();
    });
    env.addEventListener("pagehide", () => { accrue(); flush(); });
  }
  return { track, state };
}
