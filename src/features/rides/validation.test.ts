import { describe, expect, it } from 'vitest'
import { bookingRequestSchema, cancellationSchema, rideFormSchema, rideLocalDateTimeToUtcIso, rideUtcIsoToLocalDateTime } from './validation'

describe('ride validation', () => {
  const validRide = { origin: 'Rawalpindi' as const, destination: 'Attock' as const, departureAt: rideUtcIsoToLocalDateTime(new Date(Date.now() + 86_400_000).toISOString()), totalSeats: 3, pricePerSeat: 400, vehicleId: '', description: '', pickupLabel: 'Saddar', dropoffLabel: 'Attock centre', pickupLatitude: 33.56, pickupLongitude: 73.01, dropoffLatitude: 33.76, dropoffLongitude: 72.35 }
  it('rejects same-city routes', () => expect(rideFormSchema.safeParse({ ...validRide, destination: 'Rawalpindi' }).success).toBe(false))
  it('rejects past departure', () => expect(rideFormSchema.safeParse({ ...validRide, departureAt: rideUtcIsoToLocalDateTime(new Date(Date.now() - 1000).toISOString()) }).success).toBe(false))
  it('interprets datetime-local values in Asia/Karachi across midnight', () => {
    expect(rideLocalDateTimeToUtcIso('2026-12-31T23:55')).toBe('2026-12-31T18:55:00.000Z')
    expect(rideLocalDateTimeToUtcIso('2027-01-01T00:05')).toBe('2026-12-31T19:05:00.000Z')
    expect(rideUtcIsoToLocalDateTime('2026-12-31T19:05:00.000Z')).toBe('2027-01-01T00:05')
  })
  it('requires explicit cancellation policy acceptance', () => expect(bookingRequestSchema.safeParse({ seats: 1, policyAccepted: false }).success).toBe(false))
  it('accepts a valid seat request', () => expect(bookingRequestSchema.safeParse({ seats: 2, policyAccepted: true }).success).toBe(true))
  it('requires a cancellation reason', () => expect(cancellationSchema.safeParse({ reason: 'no' }).success).toBe(false))
})
