import { describe, expect, it } from 'vitest'
import { LANE_WISDOM, LANE_WISDOM_ROTATION_MS, selectLaneWisdom } from './lane-wisdom'

describe('Lane Wisdom', () => {
  it('contains the complete curated 75-entry pool with valid categories', () => {
    expect(LANE_WISDOM).toHaveLength(75)
    expect(new Set(LANE_WISDOM.map(entry => entry.text)).size).toBe(75)
    expect(LANE_WISDOM.filter(entry => entry.category === 'FACT')).toHaveLength(25)
    expect(LANE_WISDOM.filter(entry => entry.category === 'BOWLER')).toHaveLength(35)
    expect(LANE_WISDOM.filter(entry => entry.category === 'CENTER')).toHaveLength(15)
  })

  it('uses the established five-minute rotation interval', () => {
    expect(LANE_WISDOM_ROTATION_MS).toBe(300_000)
  })

  it('uses category weighting and never immediately repeats an entry', () => {
    const fact = selectLaneWisdom(undefined, () => .1)
    const bowler = selectLaneWisdom(undefined, () => .3)
    const center = selectLaneWisdom(undefined, () => .9)
    expect(fact.category).toBe('FACT')
    expect(bowler.category).toBe('BOWLER')
    expect(center.category).toBe('CENTER')
    expect(selectLaneWisdom(fact, () => .1).text).not.toBe(fact.text)
  })

  it('retains the longest curated center observation for normal component truncation/wrapping', () => {
    expect(LANE_WISDOM).toContainEqual({ category: 'CENTER', text: 'Bowling centers run on electricity, oil, and somebody knowing what that noise means.' })
  })
})
