// Ruby's atlas coordinates stay in original pixels, independent of the web texture size.
export function artworkSource(url, sources, compact) {
  const source = sources[url];
  return source ? { ...source, src: compact ? source.mobileSrc : source.src } : { src: url };
}

export function artworkCrop(texture, source) {
  const scaleX = texture.image.naturalWidth / texture.width;
  const scaleY = texture.image.naturalHeight / texture.height;
  return source.map((value, index) => value * (index % 2 === 0 ? scaleX : scaleY));
}
