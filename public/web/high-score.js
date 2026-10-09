export const difficulties = ["easy", "normal", "hard"];

export function difficultyHighScores(board) {
  return Object.fromEntries(difficulties.map(difficulty => [difficulty, Math.max(
    Number(board.highScores?.[difficulty]) || 0,
    ...(board.entries || []).filter(entry => entry.difficulty === difficulty).map(entry => Number(entry.score) || 0)
  )]));
}

export class HighScoreTracker {
  constructor() { this.records = {}; this.newHigh = false; }
  load(board) {
    for (const [difficulty, score] of Object.entries(difficultyHighScores(board))) {
      this.records[difficulty] = Math.max(this.records[difficulty] || 0, score);
    }
  }
  update(previous, state) {
    const playing = state.screen === "game" && state.status === "playing";
    if (state.screen === "select" || (playing && (previous.screen !== "game" || previous.status !== "playing" || previous.difficulty !== state.difficulty))) {
      this.newHigh = false;
    }
    if (state.screen !== "game" || !Object.hasOwn(this.records, state.difficulty)) return false;
    const record = this.records[state.difficulty];
    if (state.score <= record) return false;
    this.records[state.difficulty] = state.score;
    const celebrate = !this.newHigh;
    this.newHigh = true;
    return celebrate;
  }
  label(difficulty) {
    const score = this.records[difficulty];
    return `${difficulty.toUpperCase()} HIGH ${score === undefined ? "-------" : String(score).padStart(7, "0")}`;
  }
}
