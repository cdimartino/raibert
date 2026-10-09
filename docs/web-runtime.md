# Browser runtime

The browser loads the same Ruby game through CRuby 4.0’s WASI build. `web/gosu.rb` is a small compatibility layer that translates rendering, input, audio, resize, preferences, and run-state events to `public/web/app.js`. Game rules stay in Ruby; network and form handling stay in JavaScript.

The committed content-hashed Wasm and loader files make production static. Rebuild after changing `game.rb`, `lib/`, `config/controls.json`, `web/gosu.rb`, or `web/boot.rb`:

```sh
script/build_web
```

Docker must support `linux/amd64`. The ignored `build/web-runtime` cache avoids recompiling the Ruby base when its inputs are unchanged. Set `RUBY_WASM_JOBS=1` on a memory-constrained native amd64 builder. Browser-only HTML, CSS, and JavaScript changes are served directly.

The first visit downloads the runtime, artwork, and initial audio. WebAssembly, ES modules, Canvas 2D, Web Audio, Pointer Events, and `visualViewport` are used where available. Audio unlocks on the first user gesture.

## Runtime and artwork size

The release build strips DWARF debug sections with the pinned WASI SDK's `llvm-strip --strip-debug` after packaging the Ruby app and before computing its filename. `build/web-runtime/ruby-app.debug.wasm` retains the unstripped build for local diagnostics. Function names remain in the shipped module. Game source, interpreter behavior, and the bundled standard library are unchanged.

Browser artwork is generated separately, using cwebp 1.6.0:

```sh
script/build_web_art
```

Commit `public/web/art/` and `public/web/assets.json` together. Original PNGs remain untouched for native play, editing, and rollout compatibility. WebP files use quality 85 with full-resolution and half-resolution variants. The app selects half resolution for a narrow viewport or a phone-sized coarse-pointer display, including landscape. It keeps that choice during the session; rotation does not allocate a second texture set. The manifest retains original dimensions, and the renderer scales atlas crop coordinates so Ruby sees exactly the same tile geometry.

Measured October 8, 2026 against the pre-optimization working build (decimal MB):

| Resource | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| WASM decoded file | 53.11 MB | 33.02 MB | 37.8% |
| WASM gzip transfer | 17.27 MB | 10.20 MB | 40.9% |
| Desktop artwork transfer | 20.34 MB | 2.35 MB | 88.4% |
| Mobile artwork transfer | 20.34 MB | 0.90 MB | 95.6% |
| Mobile artwork RGBA pixel storage | 69.00 MB | 17.25 MB | 75.0% |

RGBA storage is width × height × four bytes, not measured total process/GPU memory. Desktop retains full dimensions. WASM plus mobile artwork falls from about 37.62 MB to 11.10 MB, excluding audio, JavaScript, and HTTP overhead. Lossless WebP was also measured: 14.55 MB, a smaller saving than quality 85.

Further work should preserve the working Ruby runtime rather than blindly choosing the smallest build. The game requires `json`, `optparse`, and the Ruby/JS bridge. The [ruby.wasm minimal profile](https://github.com/ruby/ruby.wasm) omits extensions the game needs. A custom extension/standard-library build needs its own dependency trace and full campaign tests. The current stripped module has about 12.4 MB of code and 20.0 MB of data, so library/filesystem reduction is the next substantial WASM opportunity. Removing function names saves only about 0.17 MB more over gzip and makes native diagnostics less useful.

For artwork, loading only the active background/selected character and releasing old textures could reduce memory further, but requires transitions and load-failure handling. Reducing mobile resolution further should be evaluated on physical phones before sacrificing readability. Browser mobile emulation checks layout and decoding, but does not prove that an Android low-memory crash is fixed.

A Brotli quality-11 experiment produces about 7.3 MB for the stripped module, versus 10.2 MB gzip. It is not enabled in this change: packaging, validation, and CDN `Content-Encoding` must switch together, using a fresh runtime URL and verifying both fresh and cached clients. Keep gzip compatibility for retained releases. This offers another roughly 28% transfer reduction without changing Ruby code or decoded memory.
