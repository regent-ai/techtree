export interface ReplayStore {
  claim(key: string, ttlMs: number, nowMs?: number): boolean;
}

export class InMemoryReplayStore implements ReplayStore {
  private readonly expiresAtByKey = new Map<string, number>();

  public claim(key: string, ttlMs: number, nowMs: number = Date.now()): boolean {
    this.prune(nowMs);

    const existing = this.expiresAtByKey.get(key);
    if (typeof existing === "number" && existing > nowMs) {
      return false;
    }

    this.expiresAtByKey.set(key, nowMs + ttlMs);
    return true;
  }

  private prune(nowMs: number): void {
    for (const [key, expiresAt] of this.expiresAtByKey) {
      if (expiresAt <= nowMs) {
        this.expiresAtByKey.delete(key);
      }
    }
  }
}
