import { describe, expect, it, vi } from 'vitest'
import { SharedPollingLoop, SharedRefreshSequencer } from './open-play-sync'

describe('shared polling primitives', () => {
  it('rejects an older response after a newer refresh begins', () => {
    const sequencer = new SharedRefreshSequencer()
    const poll = sequencer.begin()
    sequencer.invalidate()
    const mutation = sequencer.begin()
    expect(sequencer.isCurrent(poll)).toBe(false)
    expect(sequencer.isCurrent(mutation)).toBe(true)
  })

  it('creates one loop, skips hidden tabs, and cleans up', async () => {
    const setInterval = vi.fn(() => 42)
    const clearInterval = vi.fn()
    Object.assign(globalThis, { window: { setInterval, clearInterval } })
    const refresh = vi.fn(async () => undefined)
    const loop = new SharedPollingLoop(5000, refresh, () => false)
    loop.start(); loop.start()
    expect(setInterval).toHaveBeenCalledTimes(1)
    await loop.poll()
    expect(refresh).not.toHaveBeenCalled()
    loop.stop()
    expect(clearInterval).toHaveBeenCalledWith(42)
  })

  it('keeps polling quiet after a temporary refresh failure', async () => {
    Object.assign(globalThis, { window: { setInterval: vi.fn(() => 1), clearInterval: vi.fn() } })
    const loop = new SharedPollingLoop(5000, async () => { throw new Error('offline') }, () => true)
    await expect(loop.poll()).resolves.toBeUndefined()
  })
})
