const two = (value:number) => String(value).padStart(2,'0')

/** Combines a local calendar day with the existing default local time without UTC parsing. */
export const bookingInitialDateTime = (selectedDate:Date|undefined, now=new Date()) => {
  const fallback = new Date(now.getTime()+86_400_000)
  const day = selectedDate ?? fallback
  return `${day.getFullYear()}-${two(day.getMonth()+1)}-${two(day.getDate())}T${two(fallback.getHours())}:${two(fallback.getMinutes())}`
}
