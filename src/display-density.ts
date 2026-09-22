export type LaneDisplayDensity = 'COMFORTABLE' | 'FIT_12'
export const LANE_DISPLAY_DENSITY_KEY = 'bsb-open-play:lane-display-density:v1'

export const readLaneDisplayDensity = (storage: Pick<Storage, 'getItem'> = localStorage): LaneDisplayDensity =>
  storage.getItem(LANE_DISPLAY_DENSITY_KEY) === 'FIT_12' ? 'FIT_12' : 'COMFORTABLE'

export const writeLaneDisplayDensity = (density: LaneDisplayDensity, storage: Pick<Storage, 'setItem'> = localStorage) =>
  storage.setItem(LANE_DISPLAY_DENSITY_KEY, density)
