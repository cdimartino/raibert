// Glitchless: performance, errors and gameplay moments. A facade that never blocks or breaks the game.
// Bump GAME_VERSION on every release so Glitchless can compare versions.
export const GAME_VERSION = "2026-11-25.1";
const INTAKE = "https://api.glitchless.gg";
// Public and write-only: it can only send data.
const CLIENT_TOKEN = "gl_pub_BDGg2a5w283658NDIWlpn9JY";
const MAX_QUEUED = 100;

const stageId = stage => `stage-${String(stage).padStart(2, "0")}`;
const total = counts => Object.values(counts || {}).reduce((sum, value) => sum + value, 0);

export function createTelemetry(env = globalThis, load = () => import("./glitchless-sdk.js")) {
  const query = new URLSearchParams(env.location.search);
  // Production only; ?glitchless=1 turns it on elsewhere to check the wiring. Browser privacy signals always win.
  const enabled = (env.location.hostname === "raibert.lol" || query.get("glitchless") === "1") &&
    query.get("nogd") !== "1" && env.navigator.doNotTrack !== "1" && !env.navigator.globalPrivacyControl;
  let sdk = null;
  let dead = !enabled;
  let sharing = true;
  const queue = [];
  const startedAt = env.performance.now();
  let run = null;
  let inputKind = null;

  function call(action) {
    if (dead || !sharing) return;
    if (!sdk) {
      if (queue.length < MAX_QUEUED) queue.push(action);
      return;
    }
    try { action(sdk); } catch {}
  }
  const track = (name, attrs = {}) => call(gd => gd.track(name, attrs));

  async function start({ sharing: choice = true, screenshot, onReportOpen, onReportClose } = {}) {
    sharing = choice;
    if (dead) return;
    try {
      const { Glitchless } = await load();
      const gd = Glitchless.init({
        service: "raibert",
        version: GAME_VERSION,
        env: env.location.hostname === "raibert.lol" ? "prod" : "dev",
        intake: INTAKE,
        clientToken: CLIENT_TOKEN,
        // A random ID kept on the device, so returning players can be counted. See privacy.html.
        privacy: "install",
        sessionType: env.navigator.webdriver || query.get("autoplay") === "1" ? "synthetic" : "user",
        bugReports: { hotkey: null, onOpen: onReportOpen, onClose: onReportClose }
      });
      // A 2D canvas has no engine adapter, so the bug report screenshot comes from the game.
      if (screenshot) gd.render = { screenshot: async () => screenshot() };
      gd.setEnabled(sharing);
      sdk = gd;
      queue.splice(0).forEach(call);
    } catch {
      dead = true;
      queue.length = 0;
    }
  }

  function setSharing(on) {
    sharing = Boolean(on);
    if (!sharing) { queue.length = 0; run = null; }
    try { sdk?.setEnabled(sharing); } catch {}
  }

  // The first-party analytics events, under the same names. Nested values and the referrer are left out.
  function mirror(event, extra = {}) {
    const { seconds, diagnostics } = extra;
    track(event, {
      ...(seconds === undefined ? {} : { seconds }),
      ...(diagnostics ? { error_type: diagnostics.errorType, phase: diagnostics.phase, source: diagnostics.source, line: diagnostics.line } : {})
    });
  }

  function input(kind) {
    if (kind === inputKind) return;
    inputKind = kind;
    call(gd => gd.setProperties({ input: kind }));
  }

  function endRun(gd, next, won) {
    gd.track("run_end", {
      won, stage: next.stage, score: next.score, difficulty: next.difficulty, character: run.character,
      duration_s: Math.round((env.performance.now() - run.startedAt) / 1000),
      deaths: next.deaths || 0, powerups: total(next.pickups), rescues: next.rescues_used || 0,
      speed_bonus: next.bonuses?.speed || 0, clean_bonus: next.bonuses?.clean || 0
    });
    run = null;
  }

  // Turns the states the Ruby game publishes into levels, deaths, powerups, rescues and run results.
  function state(next) {
    call(gd => {
      if (next.screen !== "game") return;
      const attrs = () => ({ difficulty: next.difficulty, character: run.character });
      const begin = () => {
        run.stage = next.stage;
        run.open = true;
        gd.levelStart(stageId(next.stage), attrs());
      };
      if (!run) {
        if (next.status !== "playing") return;
        run = { character: next.character || "unknown", startedAt: env.performance.now(), deaths: next.deaths || 0, pickups: { ...next.pickups }, rescues: next.rescues_used || 0 };
        gd.setProperties({ difficulty: next.difficulty, character: run.character });
        begin();
        return;
      }
      if ((next.deaths || 0) > run.deaths) {
        run.deaths = next.deaths;
        gd.death({ cause: next.death_cause || "unknown" });
      }
      for (const [kind, count] of Object.entries(next.pickups || {})) {
        for (let seen = run.pickups[kind] || 0; seen < count; seen++) gd.track("powerup", { kind, stage: run.stage });
        run.pickups[kind] = count;
      }
      if ((next.rescues_used || 0) > run.rescues) {
        run.rescues = next.rescues_used;
        gd.track("rescue", { stage: run.stage });
      }
      const complete = () => {
        if (!run.open) return;
        run.open = false;
        gd.levelComplete(stageId(run.stage), { score: next.score });
      };
      if (next.stage !== run.stage) { complete(); begin(); }
      if (next.status === "stage_clear") complete();
      if (next.status === "victory") { complete(); endRun(gd, next, true); }
      if (next.status === "game_over") {
        if (run.open) gd.levelFail(stageId(run.stage), { cause: next.death_cause || "unknown" });
        endRun(gd, next, false);
      }
    });
  }

  return {
    start, setSharing, mirror, track, state, input,
    gauge: values => { if (sdk && sharing) try { sdk.setContext(values); } catch {} },
    ready: () => track("game_ready", { load_s: Math.round((env.performance.now() - startedAt) / 100) / 10 }),
    error: (message, phase) => call(gd => gd.error(new Error(String(message)), { phase })),
    canReport: () => Boolean(sdk) && sharing,
    openBugReport: () => call(gd => gd.openBugReport()),
    registerTool: (...tool) => call(gd => gd.registerTool(...tool))
  };
}
