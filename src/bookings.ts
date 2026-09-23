import type { Booking, BookingType } from './domain'

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
export type BookingDraft={type:BookingType;scheduledAt:string;lanesNeeded:number;notes:string|null;leagueId:string|null;designation:'PRE'|'POST'|null;teamDescription:string|null;partyName:string|null;partyAmountCents:number|null;customerName:string|null;expectedBowlers:number|null}
export const bookingDraft = (type:BookingType,scheduledAt:string,lanesNeeded:number,notes:string,details:Partial<BookingDraft>):BookingDraft => ({type,scheduledAt:new Date(scheduledAt).toISOString(),lanesNeeded,notes:notes.trim()||null,leagueId:null,designation:null,teamDescription:null,partyName:null,partyAmountCents:null,customerName:null,expectedBowlers:null,...details})
export const bookingLabel=(booking:Booking)=>booking.type==='PRE_POST'?(booking.designation==='PRE'?'PRE-BOWL':'POST-BOWL'):booking.type==='PARTY'?'PARTY':'OPEN PLAY'
export const bookingName=(booking:Booking)=>booking.type==='PRE_POST'?booking.teamDescription??'Pre/Post':booking.type==='PARTY'?booking.partyName??'Party':booking.customerName??'Open Play'
export const monthGrid=(month:Date)=>{const first=new Date(month.getFullYear(),month.getMonth(),1);const start=new Date(first);start.setDate(1-first.getDay());return Array.from({length:42},(_,index)=>{const date=new Date(start);date.setDate(start.getDate()+index);return date})}
export const bookingsForDate=(bookings:Record<string,Booking>,date:Date)=>scheduledBookings(bookings).filter(booking=>localDateKey(booking.scheduledAt)===localDateKey(date))
export const scheduledDateKeys=(bookings:Record<string,Booking>)=>new Set(scheduledBookings(bookings).map(booking=>localDateKey(booking.scheduledAt)))
