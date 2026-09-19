import { classifyGameplaySwipe, menuPrimaryAction } from "./input.js";

const canvas = document.querySelector("#game");
const context = canvas.getContext("2d", { alpha: false });
const status = document.querySelector("#status");
const surface = document.querySelector("#game-surface");
const menuDialog = document.querySelector("#menu-dialog");
const menuPrimaryButton = document.querySelector("[data-menu-primary]");
const leaderboardDialog = document.querySelector("#leaderboard-dialog");
const floatingControls = document.querySelector("#floating-controls");
const SETTINGS_KEY = "raibert.settings.v1";
const DEFAULT_SETTINGS = { version: 1, overlay: { enabled: false, portrait: { x: .58, y: .72 }, landscape: { x: .78, y: .62 } }, game: { muted: false, selection: 0, difficulty: "normal", controls: {} }, initials: "" };
const images = new Map();
let animation = 0;
let frameCallback;
let keyCallback;
let actionCallback;
let configuredKeys = new Set();
let resizeCallback;
let worldScoreCallback;
let gameState = { screen: "select", status: "select", score: 0, stage: 1, difficulty: "normal", paused: false };
let pendingRun = null;
let settings = loadSettings();
let keepPausedForDialog = false;
let leaderboardPausedGame = false;
let displayedWorldScore = null;

function cloneDefaults() { return JSON.parse(JSON.stringify(DEFAULT_SETTINGS)); }
function loadSettings() {
  try {
    let value = JSON.parse(localStorage.getItem(SETTINGS_KEY));
    if (value?.version === 0) value = { version: 1, overlay: { enabled: value.floatingControls === true, ...value.positions }, game: { muted: value.muted, selection: value.selection, difficulty: value.difficulty, controls: value.controls }, initials: value.initials };
    if (!value || value.version !== 1) return cloneDefaults();
    const clean = cloneDefaults();
    clean.overlay.enabled = value.overlay?.enabled === true;
    for (const mode of ["portrait", "landscape"]) for (const axis of ["x", "y"]) {
      const number = Number(value.overlay?.[mode]?.[axis]);
      if (Number.isFinite(number) && number >= 0 && number <= 1) clean.overlay[mode][axis] = number;
    }
    if (typeof value.game?.muted === "boolean") clean.game.muted = value.game.muted;
    if ([0, 1].includes(value.game?.selection)) clean.game.selection = value.game.selection;
    if (["easy", "normal", "hard"].includes(value.game?.difficulty)) clean.game.difficulty = value.game.difficulty;
    if (value.game?.controls && typeof value.game.controls === "object") clean.game.controls = value.game.controls;
    if (/^[A-Z]{3}$/.test(value.initials || "")) clean.initials = value.initials;
    return clean;
  } catch { return cloneDefaults(); }
}
function persistSettings() { localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings)); }

function color(value) {
  const unsigned = Number(value) >>> 0;
  return `rgba(${unsigned >>> 16 & 255},${unsigned >>> 8 & 255},${unsigned & 255},${(unsigned >>> 24) / 255})`;
}

function alpha(value) {
  return ((Number(value) >>> 24) & 255) / 255;
}

function font(size, family) {
  const preferred = family === "Menlo" ? "Menlo, Consolas, monospace" : `${family}, monospace`;
  return `${size}px ${preferred}`;
}

function draw(command) {
  context.save();
  switch (command.kind) {
    case "rect":
      context.fillStyle = color(command.color);
      context.fillRect(command.x, command.y, command.width, command.height);
      break;
    case "line":
      if (command.color1 === command.color2) {
        context.strokeStyle = color(command.color1);
      } else {
        const gradient = context.createLinearGradient(command.x1, command.y1, command.x2, command.y2);
        gradient.addColorStop(0, color(command.color1));
        gradient.addColorStop(1, color(command.color2));
        context.strokeStyle = gradient;
      }
      context.beginPath();
      context.moveTo(command.x1, command.y1);
      context.lineTo(command.x2, command.y2);
      context.stroke();
      break;
    case "quad":
      if (command.colors.every(value => value === command.colors[0])) {
        context.fillStyle = color(command.colors[0]);
      } else {
        const gradient = context.createLinearGradient(
          command.points[0], command.points[1], command.points[4], command.points[5]
        );
        command.colors.forEach((value, index) => gradient.addColorStop(index / 3, color(value)));
        context.fillStyle = gradient;
      }
      context.beginPath();
      context.moveTo(command.points[0], command.points[1]);
      for (let index = 2; index < command.points.length; index += 2) {
        context.lineTo(command.points[index], command.points[index + 1]);
      }
      context.closePath();
      context.fill();
      break;
    case "image": {
      const image = images.get(command.url);
      if (!image) break;
      context.globalAlpha = alpha(command.color);
      context.drawImage(image, ...command.source, command.x, command.y, command.width, command.height);
      break;
    }
    case "text":
      context.fillStyle = color(command.color);
      context.font = font(command.size, command.family);
      context.textBaseline = "top";
      context.translate(command.x, command.y);
      context.scale(command.scale_x, command.scale_y);
      context.fillText(command.text, 0, 0);
      break;
  }
  context.restore();
}

class AudioEngine {
  constructor() {
    this.context = null;
    this.bytes = new Map();
    this.buffers = new Map();
    this.song = null;
    this.token = 0;
  }

  resume() {
    this.context ||= new AudioContext();
    const startPendingSong = () => {
      if (this.song && !this.song.paused && !this.song.source) {
        this.playSong(this.song.url, this.song.volume, this.song.looping).catch(console.error);
      }
    };
    if (this.context.state === "suspended") {
      this.context.resume().then(startPendingSong).catch(console.error);
    } else {
      startPendingSong();
    }
  }

  prefetch(url) {
    if (!this.bytes.has(url)) {
      this.bytes.set(url, fetch(url)
        .then(response => {
          if (!response.ok) throw new Error(`Audio ${response.status}: ${url}`);
          return response.arrayBuffer();
        }));
    }
    return this.bytes.get(url);
  }

  preload(url) {
    this.prefetch(url).catch(() => {});
  }

  async buffer(url) {
    if (!this.context) throw new Error("Audio has not been unlocked by a user gesture");
    if (!this.buffers.has(url)) {
      this.buffers.set(url, this.prefetch(url).then(bytes => this.context.decodeAudioData(bytes.slice(0))));
    }
    return this.buffers.get(url);
  }

  async effect(url, volume, rate, looping) {
    if (!this.context) return;
    const audio = this.context;
    const source = audio.createBufferSource();
    const gain = audio.createGain();
    source.buffer = await this.buffer(url);
    source.playbackRate.value = rate;
    source.loop = looping;
    gain.gain.value = volume;
    source.connect(gain).connect(audio.destination);
    source.start();
  }

  async playSong(url, volume, looping) {
    if (!this.song || this.song.url !== url) {
      this.stopSong();
      this.song = { url, volume, looping, offset: 0, source: null, startedAt: 0, paused: false };
    } else {
      this.song.volume = volume;
      this.song.looping = looping;
      this.song.paused = false;
    }
    if (!this.context) return;
    const token = ++this.token;
    const buffer = await this.buffer(url);
    if (token !== this.token || !this.song || this.song.url !== url || this.song.source) return;
    const audio = this.context;
    const source = audio.createBufferSource();
    const gain = audio.createGain();
    source.buffer = buffer;
    source.loop = looping;
    gain.gain.setValueAtTime(0, audio.currentTime);
    gain.gain.linearRampToValueAtTime(volume, audio.currentTime + 0.04);
    source.connect(gain).connect(audio.destination);
    this.song.source = source;
    this.song.gain = gain;
    this.song.startedAt = audio.currentTime;
    source.start(0, this.song.offset % buffer.duration);
  }

  pauseSong() {
    this.token++;
    if (this.song) this.song.paused = true;
    if (!this.song?.source) return;
    this.song.offset += this.context.currentTime - this.song.startedAt;
    this.fadeOutSong();
    this.song.source = null;
  }

  fadeOutSong() {
    if (!this.song?.source) return;
    const now = this.context.currentTime;
    const gain = this.song.gain.gain;
    if (typeof gain.cancelAndHoldAtTime === "function") {
      gain.cancelAndHoldAtTime(now);
    } else {
      // cancelAndHoldAtTime is absent from some Web Audio implementations.
      // Preserve the current level before scheduling the fade so changing
      // stages cannot abort the game loop in those browsers.
      const currentValue = gain.value;
      gain.cancelScheduledValues(now);
      gain.setValueAtTime(currentValue, now);
    }
    gain.linearRampToValueAtTime(0, now + 0.04);
    this.song.source.stop(now + 0.04);
  }

  stopSong() {
    this.fadeOutSong();
    this.song = null;
    this.token++;
  }
}

const audio = new AudioEngine();

function dispatchKey(name) {
  if (!keyCallback) return;
  audio.resume();
  keyCallback(name);
}

function dispatchAction(action) {
  if (!actionCallback) return;
  audio.resume();
  actionCallback(action);
  if (gameState.screen === "select" && action === "confirm") gameState = { ...gameState, screen: "game", status: "playing" };
  else if (gameState.screen === "game" && ["game_over", "victory"].includes(gameState.status) && action === "confirm") gameState = { ...gameState, status: "playing", paused: false };
  else if (gameState.screen === "game" && gameState.status === "playing" && action === "pause") gameState = { ...gameState, paused: !gameState.paused };
}

function browserKey(event) {
  const codeNames = {
    ShiftLeft: "left_shift", ShiftRight: "right_shift",
    ControlLeft: "left_control", ControlRight: "right_control",
    AltLeft: "left_alt", AltRight: "right_alt",
    MetaLeft: "left_meta", MetaRight: "right_meta",
    Enter: "return", NumpadEnter: "enter",
    NumpadDecimal: "numpad_delete", NumpadDivide: "numpad_divide",
    NumpadSubtract: "numpad_minus", NumpadMultiply: "numpad_multiply", NumpadAdd: "numpad_plus",
    Semicolon: "semicolon", Comma: "comma", Period: "period", Slash: "slash",
    Backslash: "backslash", IntlBackslash: "iso", Minus: "minus", Equal: "equals",
    BracketLeft: "left_bracket", BracketRight: "right_bracket",
    Backquote: "backtick", Quote: "apostrophe"
  };
  if (codeNames[event.code]) return codeNames[event.code];
  if (event.code?.startsWith("Key")) return event.code.slice(3).toLowerCase();
  if (event.code?.startsWith("Digit")) return event.code.slice(5);
  if (/^Numpad\d$/.test(event.code)) return `numpad_${event.code.slice(-1)}`;
  const aliases = {
    Enter: "return", Escape: "escape", " ": "space",
    ArrowLeft: "left", ArrowRight: "right", ArrowUp: "up", ArrowDown: "down"
  };
  return aliases[event.key] || event.key.replace(/([a-z])([A-Z])/g, "$1_$2").toLowerCase();
}

globalThis.RaiBertWeb = {
  milliseconds: () => Math.floor(performance.now()),
  configure(width, height) {
    canvas.width = Number(width);
    canvas.height = Number(height);
  },
  imageSize(url) {
    const image = images.get(String(url));
    return image ? `${image.naturalWidth},${image.naturalHeight}` : "0,0";
  },
  textWidth(size, family, text) {
    context.save();
    context.font = font(Number(size), String(family));
    const width = context.measureText(String(text)).width;
    context.restore();
    return width;
  },
  render(json) {
    const commands = JSON.parse(String(json));
    commands.sort((left, right) => left.z - right.z || left.order - right.order);
    context.clearRect(0, 0, canvas.width, canvas.height);
    commands.forEach(draw);
  },
  start(frame, key, action, resize, worldScore, keyNames) {
    if (typeof resize === "string") {
      keyNames = resize;
      resize = null;
      worldScore = null;
    }
    frameCallback = frame;
    keyCallback = key;
    actionCallback = action;
    resizeCallback = resize;
    worldScoreCallback = worldScore;
    configuredKeys = new Set(JSON.parse(String(keyNames)));
    resizeGame();
    updateFloatingControls();
    loadLeaderboard();
    status.hidden = true;
    const tick = () => {
      frameCallback?.();
      animation = requestAnimationFrame(tick);
    };
    cancelAnimationFrame(animation);
    animation = requestAnimationFrame(tick);
    canvas.focus();
  },
  stop() {
    cancelAnimationFrame(animation);
    animation = 0;
    audio.stopSong();
  },
  fail(message) {
    status.hidden = false;
    status.textContent = `Rai*bert stopped: ${message}`;
    console.error(message);
  },
  playEffect: (url, volume, rate, looping) => audio.effect(String(url), Number(volume), Number(rate), Boolean(looping)).catch(console.error),
  playSong: (url, volume, looping) => audio.playSong(String(url), Number(volume), Boolean(looping))
    .catch(error => console.error("Could not play song", error)),
  pauseSong: () => audio.pauseSong(),
  stopSong: () => audio.stopSong(),
  preferences: () => JSON.stringify(settings.game),
  savePreferences(json) {
    settings.game = { ...settings.game, ...JSON.parse(String(json)) };
    persistSettings();
  },
  publishGameState(json) {
    const previous = gameState;
    gameState = JSON.parse(String(json));
    if (menuDialog.open) updateMenuPrimaryAction();
    if (!["game_over", "victory"].includes(previous.status) && ["game_over", "victory"].includes(gameState.status)) {
      pendingRun = { runId: crypto.randomUUID(), score: gameState.score, stage: gameState.stage, difficulty: gameState.difficulty, outcome: gameState.status };
      openLeaderboard(true);
    }
  }
};

function acceptsTextInput(target) {
  return target instanceof HTMLElement && (
    ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName) || target.isContentEditable
  );
}

document.addEventListener("keydown", event => {
  if (acceptsTextInput(event.target)) return;
  if ((event.key === "l" || event.key === "L") && !event.repeat && !leaderboardDialog.open) {
    event.preventDefault(); openLeaderboard(false); return;
  }
  const name = browserKey(event);
  if (!configuredKeys.has(name)) return;
  event.preventDefault();
  if (!event.repeat) dispatchKey(name);
});

function resizeGame() {
  const view = window.visualViewport;
  const width = Math.max(320, Math.round(view?.width || innerWidth));
  const height = Math.max(320, Math.round(view?.height || innerHeight));
  surface.style.width = `${width}px`; surface.style.height = `${height}px`;
  const portrait = height > width;
  const logicalWidth = portrait ? 760 : Math.round(760 * width / height);
  const logicalHeight = portrait ? Math.round(760 * height / width) : 760;
  if (resizeCallback) {
    canvas.width = logicalWidth; canvas.height = logicalHeight;
    resizeCallback(logicalWidth, logicalHeight);
  }
  updateFloatingControls();
}
addEventListener("resize", resizeGame);
window.visualViewport?.addEventListener("resize", resizeGame);

let gesture = null;
canvas.addEventListener("pointerdown", event => {
  if (document.querySelector("dialog[open]")) return;
  if (gesture) { gesture.multitouch = true; clearTimeout(gesture.holdTimer); return; }
  gesture = { id: event.pointerId, x: event.clientX, y: event.clientY, at: performance.now(), moved: false };
  if (gameState.screen === "select") gesture.holdTimer = setTimeout(() => { if (gesture && !gesture.moved && !gesture.multitouch) { gesture = null; openMenu(); } }, 500);
  canvas.setPointerCapture(event.pointerId);
});
canvas.addEventListener("pointermove", event => {
  if (!gesture || gesture.id !== event.pointerId) return;
  if (Math.hypot(event.clientX - gesture.x, event.clientY - gesture.y) > 10) { gesture.moved = true; clearTimeout(gesture.holdTimer); }
});
canvas.addEventListener("pointercancel", () => { clearTimeout(gesture?.holdTimer); gesture = null; });
canvas.addEventListener("lostpointercapture", () => { if (gesture?.moved) gesture = null; });
canvas.addEventListener("pointerup", event => {
  if (!gesture || gesture.id !== event.pointerId) return;
  const current = gesture; gesture = null;
  clearTimeout(current.holdTimer);
  if (current.multitouch) return;
  const dx = event.clientX - current.x, dy = event.clientY - current.y, elapsed = performance.now() - current.at;
  if (elapsed > 600 || Math.hypot(dx, dy) < 24) {
    if (!current.moved && elapsed < 500) gameState.screen === "select" ? dispatchAction("confirm") : openMenu();
    else if (!current.moved && elapsed >= 500 && gameState.screen === "select") openMenu();
    return;
  }
  if (gameState.screen === "select") {
    dispatchAction(Math.abs(dx) > Math.abs(dy) ? (dx < 0 ? "select_left" : "select_right") : (dy < 0 ? "select_up" : "select_down"));
    return;
  }
  const action = classifyGameplaySwipe(dx, dy);
  if (action) dispatchAction(action);
});

function resumableRun() { return gameState.screen === "game" && gameState.status === "playing"; }
function updateMenuPrimaryAction() {
  const action = menuPrimaryAction(gameState);
  menuPrimaryButton.dataset.action = action;
  menuPrimaryButton.value = action;
  menuPrimaryButton.textContent = action === "replay" ? "Replay" : action === "play" ? "Play" : "Resume";
}

function openMenu() {
  if (leaderboardDialog.open || menuDialog.open) return;
  if (resumableRun() && !gameState.paused) dispatchAction("pause");
  updateMenuPrimaryAction();
  document.querySelector("#floating-toggle").checked = settings.overlay.enabled;
  menuDialog.showModal(); updateFloatingControls();
}
menuPrimaryButton.addEventListener("click", () => { if (["replay", "play"].includes(menuPrimaryButton.dataset.action)) dispatchAction("confirm"); });
menuDialog.addEventListener("close", () => { if (resumableRun() && gameState.paused && !keepPausedForDialog) dispatchAction("pause"); keepPausedForDialog = false; updateFloatingControls(); canvas.focus(); });
document.querySelector("[data-leaderboard]").addEventListener("click", () => { keepPausedForDialog = true; leaderboardPausedGame = gameState.screen === "game" && gameState.paused; menuDialog.close(); openLeaderboard(false); });
document.querySelector("[data-mute]").addEventListener("click", () => dispatchAction("mute"));
document.querySelector("[data-reset]").addEventListener("click", () => { settings = cloneDefaults(); persistSettings(); location.reload(); });
document.querySelector("#floating-toggle").addEventListener("change", event => { settings.overlay.enabled = event.target.checked; persistSettings(); updateFloatingControls(); });

function orientationKey() { return innerHeight > innerWidth ? "portrait" : "landscape"; }
function updateFloatingControls() {
  const visible = settings.overlay.enabled && !document.querySelector("dialog[open]");
  floatingControls.hidden = !visible;
  if (!visible) return;
  const point = settings.overlay[orientationKey()];
  const maxX = Math.max(0, innerWidth - floatingControls.offsetWidth), maxY = Math.max(0, innerHeight - floatingControls.offsetHeight);
  floatingControls.style.left = `${point.x * maxX}px`; floatingControls.style.top = `${point.y * maxY}px`;
}
floatingControls.querySelectorAll("[data-action]").forEach(button => button.addEventListener("pointerdown", event => { event.stopPropagation(); dispatchAction(button.dataset.action); }));
floatingControls.querySelector("[data-menu]").addEventListener("click", openMenu);
let drag = null;
floatingControls.querySelector(".grip").addEventListener("pointerdown", event => { event.stopPropagation(); drag = { id:event.pointerId, dx:event.clientX-floatingControls.offsetLeft, dy:event.clientY-floatingControls.offsetTop }; event.currentTarget.setPointerCapture(event.pointerId); });
floatingControls.querySelector(".grip").addEventListener("pointermove", event => {
  if (!drag || drag.id !== event.pointerId) return;
  const maxX = Math.max(0, innerWidth-floatingControls.offsetWidth), maxY = Math.max(0, innerHeight-floatingControls.offsetHeight);
  const x = Math.max(0, Math.min(maxX, event.clientX-drag.dx)), y = Math.max(0, Math.min(maxY, event.clientY-drag.dy));
  floatingControls.style.left=`${x}px`; floatingControls.style.top=`${y}px`;
  settings.overlay[orientationKey()]={x:maxX ? x/maxX : 0,y:maxY ? y/maxY : 0}; persistSettings();
});
floatingControls.querySelector(".grip").addEventListener("pointerup", () => { drag=null; });

function renderLeaderboard(board, highlightId) {
  const rows = document.querySelector("#leaderboard-rows"); rows.replaceChildren();
  (board.entries || []).forEach((entry, index) => {
    const row = document.createElement("tr"); row.style.setProperty("--row", index);
    if (entry.id === highlightId) row.classList.add("new-entry");
    for (const value of [entry.rank || index+1, entry.initials, Number(entry.score).toLocaleString("en-US"), entry.stage, entry.difficulty, entry.outcome.replace("_", " ")]) { const cell=document.createElement("td"); cell.textContent=value; row.append(cell); }
    rows.append(row);
  });
  animateWorldScore(board.highScore ?? null);
}
function animateWorldScore(next) {
  if (!worldScoreCallback) return;
  const target = next == null ? null : Number(next);
  if (target == null || displayedWorldScore == null || matchMedia("(prefers-reduced-motion: reduce)").matches) {
    displayedWorldScore = target; worldScoreCallback(target); return;
  }
  const from = displayedWorldScore, started = performance.now();
  const roll = now => {
    const amount = Math.min(1, (now - started) / 320);
    displayedWorldScore = Math.round(from + (target - from) * amount); worldScoreCallback(displayedWorldScore);
    if (amount < 1) requestAnimationFrame(roll);
  };
  requestAnimationFrame(roll);
}
async function loadLeaderboard() {
  const message = document.querySelector("#leaderboard-status");
  try {
    const response = await fetch("/api/leaderboard"); if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const board = await response.json(); localStorage.setItem("raibert.leaderboard.cache", JSON.stringify(board)); renderLeaderboard(board);
    message.textContent = board.entries?.length ? "Worldwide scores are live." : "The board is empty. Be first."; return board;
  } catch {
    const cached = JSON.parse(localStorage.getItem("raibert.leaderboard.cache") || "null");
    if (cached) { renderLeaderboard(cached); message.textContent = "Offline — showing cached scores."; }
    else message.textContent = "Leaderboard unavailable. Gameplay is unaffected.";
    return cached;
  }
}
async function openLeaderboard(offerSubmission) {
  if (menuDialog.open) menuDialog.close();
  if (gameState.screen === "game" && gameState.status === "playing" && !gameState.paused) { dispatchAction("pause"); leaderboardPausedGame = true; }
  if (!leaderboardDialog.open) leaderboardDialog.showModal(); updateFloatingControls();
  const board = await loadLeaderboard();
  const cutoff = board?.entries?.length < 15 ? -1 : Number(board.entries.at(-1)?.score || 0);
  const form = document.querySelector("#initials-form");
  form.hidden = !(offerSubmission && pendingRun && pendingRun.score > cutoff);
  if (!form.hidden) { document.querySelector("#initials").value = settings.initials; document.querySelector("#initials").focus(); }
  else if (offerSubmission) document.querySelector("#leaderboard-status").textContent = "That run did not reach the current Top 15.";
}
leaderboardDialog.querySelectorAll("[data-close]").forEach(button => button.addEventListener("click", () => leaderboardDialog.close()));
leaderboardDialog.querySelector("[data-retry]").addEventListener("click", loadLeaderboard);
leaderboardDialog.addEventListener("close", () => { if (leaderboardPausedGame && resumableRun() && gameState.paused) dispatchAction("pause"); leaderboardPausedGame = false; updateFloatingControls(); canvas.focus(); });
document.querySelector("[data-skip]").addEventListener("click", () => { document.querySelector("#initials-form").hidden=true; pendingRun=null; });
document.querySelector("#initials").addEventListener("input", event => { event.target.value=event.target.value.toUpperCase().replace(/[^A-Z]/g,"").slice(0,3); });
document.querySelector("#initials-form").addEventListener("submit", async event => {
  event.preventDefault(); const initials=document.querySelector("#initials").value;
  if (!/^[A-Z]{3}$/.test(initials) || !pendingRun) return;
  const message=document.querySelector("#leaderboard-status"); message.textContent="Submitting score…";
  try {
    const response=await fetch("/api/leaderboard",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({...pendingRun,initials})});
    const board=await response.json(); if(!response.ok) throw new Error(board.error||`HTTP ${response.status}`);
    settings.initials=initials; persistSettings(); renderLeaderboard(board,board.entry?.id); document.querySelector("#initials-form").hidden=true;
    message.textContent=board.rank ? `Accepted at rank ${board.rank}.` : "The cutoff changed; this run did not qualify."; pendingRun=null;
  } catch(error) { message.textContent=`Submission failed: ${error.message}. Retry or skip.`; }
});

async function preloadImages(imageUrls) {
  let loaded = 0;
  await Promise.all(imageUrls.map(url => new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => {
      images.set(url, image);
      status.textContent = `Loading artwork… ${++loaded}/${imageUrls.length}`;
      resolve();
    };
    image.onerror = () => reject(new Error(`Could not load ${url}`));
    image.src = url;
  })));
}

async function boot() {
  const [assetsResponse, runtimeResponse] = await Promise.all([
    fetch("/web/assets.json"),
    fetch("/web/runtime.json")
  ]);
  if (!assetsResponse.ok) throw new Error(`Asset manifest ${assetsResponse.status}`);
  if (!runtimeResponse.ok) throw new Error(`Runtime manifest ${runtimeResponse.status}`);
  const assets = await assetsResponse.json();
  const runtimeFiles = await runtimeResponse.json();
  await preloadImages(assets.images);
  assets.effects.forEach(url => audio.preload(url));
  audio.preload(assets.initialSong);
  status.textContent = "Loading Ruby…";
  const runtime = await import(`/web/${runtimeFiles.javascript}`);
  const response = await fetch(`/web/${runtimeFiles.webassembly}`);
  if (!response.ok) throw new Error(`Ruby runtime ${response.status}`);
  const module = await WebAssembly.compileStreaming(response);
  const result = await runtime.DefaultRubyVM(module);
  const vm = result.vm || result;
  status.textContent = "Starting Rai*bert…";
  vm.eval("load '/app/web/boot.rb'");
}

boot().catch(error => globalThis.RaiBertWeb.fail(error.stack || error.message));
