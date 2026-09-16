const canvas = document.querySelector("#game");
const context = canvas.getContext("2d", { alpha: false });
const status = document.querySelector("#status");
const images = new Map();
let animation = 0;
let frameCallback;
let keyCallback;
let actionCallback;
let configuredKeys = new Set();

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
      if (this.song && !this.song.source) {
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
      this.song = { url, volume, looping, offset: 0, source: null, startedAt: 0 };
    } else {
      this.song.volume = volume;
      this.song.looping = looping;
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
    gain.gain.value = volume;
    source.connect(gain).connect(audio.destination);
    this.song.source = source;
    this.song.startedAt = audio.currentTime;
    source.start(0, this.song.offset % buffer.duration);
  }

  pauseSong() {
    this.token++;
    if (!this.song?.source) return;
    this.song.offset += this.context.currentTime - this.song.startedAt;
    this.song.source.stop();
    this.song.source = null;
  }

  stopSong() {
    if (this.song?.source) this.song.source.stop();
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
  start(frame, key, action, keyNames) {
    frameCallback = frame;
    keyCallback = key;
    actionCallback = action;
    configuredKeys = new Set(JSON.parse(String(keyNames)));
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
  stopSong: () => audio.stopSong()
};

document.addEventListener("keydown", event => {
  const name = browserKey(event);
  if (!configuredKeys.has(name)) return;
  event.preventDefault();
  if (!event.repeat) dispatchKey(name);
});

document.querySelectorAll("button[data-key]").forEach(button => {
  button.addEventListener("click", event => {
    event.preventDefault();
    const actions = {
      w: "up_left", d: "up_right", a: "down_left", s: "down_right",
      return: "confirm", escape: "pause", m: "mute"
    };
    dispatchAction(actions[button.dataset.key]);
  });
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
  audio.preload(assets.effect);
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
