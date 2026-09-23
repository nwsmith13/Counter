import type { Booking } from './domain'

export const scheduledBookings = (bookings: Record<string,Booking>) => Object.values(bookings).filter(booking=>booking.status==='SCHEDULED').sort((a,b)=>new Date(a.scheduledAt).getTime()-new Date(b.scheduledAt).getTime()||a.id.localeCompare(b.id))
export const localDateKey = (value: string|Date) => { const date=value instanceof Date?value:new Date(value); return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}` }
export const todayBookings = (bookings: Record<string,Booking>, now=new Date()) => scheduledBookings(bookings).filter(booking=>localDateKey(booking.scheduledAt)===localDateKey(now))
export type TodayReminder = { booking: Booking; additionalCount: number; urgency: 'NORMAL'|'SOON'|'WAITING' }
export const todayReminder = (bookings: Record<string,Booking>, now=new Date()): TodayReminder | null => {
  const [booking,...rest] = todayBookings(bookings,now)
  if (!booking) return null
  const minutesUntil=(new Date(booking.scheduledAt).getTime()-now.getTime())/60_000
  return { booking, additionalCount:rest.length, urgency:minutesUntil<=0?'WAITING':minutesUntil<=60?'SOON':'NORMAL' }
}
export const bookingDraft = (scheduledAt:string,leagueId:string,designation:'PRE'|'POST',teamDescription:string,lanesNeeded:number,notes:string) => ({scheduledAt:new Date(scheduledAt).toISOString(),leagueId,designation,teamDescription:teamDescription.trim(),lanesNeeded,notes:notes.trim()||null})
