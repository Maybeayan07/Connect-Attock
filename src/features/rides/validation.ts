import { z } from 'zod'

export const RIDE_TIME_ZONE = 'Asia/Karachi'

/** datetime-local values have no offset. Connect Attock treats them as Pakistan local time. */
export function rideLocalDateTimeToUtcIso(value: string) {
  const trimmed = value.trim()
  if (!trimmed) return ''
  if (/[zZ]|[+-]\d{2}:?\d{2}$/.test(trimmed)) return new Date(trimmed).toISOString()
  const normalized = trimmed.length === 16 ? `${trimmed}:00` : trimmed
  return new Date(`${normalized}+05:00`).toISOString()
}

export function rideUtcIsoToLocalDateTime(value: string) {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: RIDE_TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(new Date(value))
  const get = (type: string) => parts.find((part) => part.type === type)?.value ?? ''
  return `${get('year')}-${get('month')}-${get('day')}T${get('hour')}:${get('minute')}`
}

export const rideFormSchema = z.object({
  origin: z.enum(['Rawalpindi', 'Attock']),
  destination: z.enum(['Rawalpindi', 'Attock']),
  departureAt: z.string().min(1, 'Choose a departure date and time.'),
  totalSeats: z.coerce.number().int().min(1).max(20),
  pricePerSeat: z.coerce.number().min(0, 'Fare cannot be negative.'),
  vehicleId: z.string().optional(),
  description: z.string().max(500, 'Keep the description under 500 characters.').optional(),
  pickupLabel: z.string().min(2, 'Add a pickup point label.'),
  dropoffLabel: z.string().min(2, 'Add a drop-off point label.'),
  pickupLatitude: z.coerce.number().min(-90).max(90),
  pickupLongitude: z.coerce.number().min(-180).max(180),
  dropoffLatitude: z.coerce.number().min(-90).max(90),
  dropoffLongitude: z.coerce.number().min(-180).max(180),
}).refine((data) => data.origin !== data.destination, { path: ['destination'], message: 'Choose the opposite city.' }).refine((data) => { try { return new Date(rideLocalDateTimeToUtcIso(data.departureAt)).getTime() > Date.now() } catch { return false } }, { path: ['departureAt'], message: 'Departure must be in the future.' })

export const rideSearchSchema = z.object({ origin: z.string(), destination: z.string(), date: z.string(), maxFare: z.coerce.number().min(0).optional(), departureFrom: z.string().optional(), departureTo: z.string().optional(), minSeats: z.coerce.number().int().min(1).max(20), sort: z.enum(['earliest', 'cheapest']) })
export const cancellationSchema = z.object({ reason: z.string().min(5, 'Give a short reason so the other person has context.').max(300) })
export const vehicleSchema = z.object({ make: z.string().min(2), model: z.string().min(1), year: z.coerce.number().int().min(1950).max(new Date().getFullYear() + 1).nullable(), color: z.string().max(40), registrationMasked: z.string().max(30), seats: z.coerce.number().int().min(1).max(20) })
export const bookingRequestSchema = z.object({ seats: z.coerce.number().int().min(1).max(20), policyAccepted: z.literal(true, { errorMap: () => ({ message: 'Accept the cancellation policy before requesting.' }) }) })
