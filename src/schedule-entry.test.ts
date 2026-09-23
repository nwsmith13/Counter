import { describe,expect,it } from 'vitest'
import { bookingInitialDateTime } from './schedule-entry'

describe('calendar booking date handoff',()=>{
  const now=new Date(2026,8,23,14,37)
  it('uses the selected local calendar day while retaining the existing default time',()=>{expect(bookingInitialDateTime(new Date(2026,9,17),now)).toBe('2026-10-17T14:37')})
  it('does not shift the selected date through UTC parsing',()=>{expect(bookingInitialDateTime(new Date(2026,0,1),now).slice(0,10)).toBe('2026-01-01')})
  it('keeps the previous next-day fallback when no calendar date is supplied',()=>{expect(bookingInitialDateTime(undefined,now)).toBe('2026-09-24T14:37')})
})
