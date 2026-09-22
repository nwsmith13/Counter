export class SharedRefreshSequencer {
  private generation = 0
  begin() { this.generation += 1; return this.generation }
  invalidate() { this.generation += 1 }
  isCurrent(generation: number) { return generation === this.generation }
}

export class SharedPollingLoop {
  private timer: number | null = null
  private inFlight = false
  constructor(private readonly intervalMs: number, private readonly refresh: () => Promise<void>, private readonly visible: () => boolean = () => document.visibilityState === 'visible') {}
  start() {
    if (this.timer !== null) return
    this.timer = window.setInterval(() => { void this.poll() }, this.intervalMs)
  }
  stop() { if (this.timer !== null) window.clearInterval(this.timer); this.timer = null }
  async poll() {
    if (this.inFlight || !this.visible()) return
    this.inFlight = true
    try { await this.refresh() } catch { /* The caller renders degraded state; polling stays quiet. */ } finally { this.inFlight = false }
  }
}
