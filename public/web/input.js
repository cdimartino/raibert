export const MINIMUM_SWIPE_DISTANCE = 24;
export const MINIMUM_HORIZONTAL_INTENT = 6;

export function classifyGameplaySwipe(dx, dy) {
  if (![dx, dy].every(Number.isFinite)) return null;
  if (Math.hypot(dx, dy) < MINIMUM_SWIPE_DISTANCE) return null;
  if (Math.abs(dx) < MINIMUM_HORIZONTAL_INTENT) return null;

  return `${dy < 0 ? "up" : "down"}_${dx < 0 ? "left" : "right"}`;
}

export function menuPrimaryAction({ screen, status }) {
  if (screen === "game" && ["game_over", "victory"].includes(status)) return "replay";
  if (screen === "game" && status === "playing") return "resume";
  return "play";
}
