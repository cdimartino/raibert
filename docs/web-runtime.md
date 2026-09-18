# Browser runtime

The browser loads the same Ruby game through CRuby 4.0’s WASI build. `web/gosu.rb` is a small compatibility layer that translates rendering, input, audio, resize, preferences, and run-state events to `public/web/app.js`. Game rules stay in Ruby; network and form handling stay in JavaScript.

The committed content-hashed Wasm and loader files make production static. Rebuild after changing `game.rb`, `lib/`, `config/controls.json`, `web/gosu.rb`, or `web/boot.rb`:

```sh
script/build_web
```

Docker must support `linux/amd64`. The ignored `build/web-runtime` cache avoids recompiling the Ruby base when its inputs are unchanged. Set `RUBY_WASM_JOBS=1` on a memory-constrained native amd64 builder. Browser-only HTML, CSS, and JavaScript changes are served directly.

The first visit downloads the runtime, artwork, and initial audio. WebAssembly, ES modules, Canvas 2D, Web Audio, Pointer Events, and `visualViewport` are used where available. Audio unlocks on the first user gesture.
