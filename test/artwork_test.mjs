import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { artworkSource, artworkCrop } from "../public/web/artwork.js";
const manifest = JSON.parse(readFileSync(new URL("../public/web/assets.json", import.meta.url)));
for (const url of manifest.images) {
  const full = artworkSource(url, manifest.imageSources, false);
  const mobile = artworkSource(url, manifest.imageSources, true);
  assert.notEqual(full.src, mobile.src);
  for (const source of [full, mobile]) {
    const bytes = readFileSync(new URL(`../public${source.src}`, import.meta.url));
    assert.equal(bytes.toString("ascii", 0, 4), "RIFF");
    assert.equal(bytes.toString("ascii", 8, 12), "WEBP");
  }
}
const texture = { image: { naturalWidth: 768, naturalHeight: 1144 }, width: 1536, height: 2288 };
assert.deepEqual(artworkCrop(texture, [192, 208, 192, 208]), [96, 104, 96, 104], "half-size atlas preserves tile boundaries");
assert.deepEqual(artworkCrop({ ...texture, image: { naturalWidth: 1536, naturalHeight: 2288 } }, [1344, 2080, 192, 208]), [1344, 2080, 192, 208]);
assert.deepEqual(artworkSource("/old.png", {}, true), { src: "/old.png" }, "old manifests remain loadable during rollout");
console.log("WebP assets, mobile atlas coordinates, and old-manifest compatibility passed");
