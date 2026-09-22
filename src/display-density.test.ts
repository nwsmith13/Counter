import { describe, expect, it } from 'vitest'
import { LANE_DISPLAY_DENSITY_KEY, readLaneDisplayDensity, writeLaneDisplayDensity } from './display-density'

const storage = () => { const values = new Map<string, string>(); return { getItem: (key: string) => values.get(key) ?? null, setItem: (key: string, value: string) => void values.set(key, value), values } }

describe('lane display density', () => {
  it('defaults to comfortable and persists only a local presentation preference', () => {
    const local = storage()
    expect(readLaneDisplayDensity(local)).toBe('COMFORTABLE')
    writeLaneDisplayDensity('FIT_12', local)
    expect(readLaneDisplayDensity(local)).toBe('FIT_12')
    expect([...local.values.keys()]).toEqual([LANE_DISPLAY_DENSITY_KEY])
  })
})
