import { useEffect, useState } from 'react'
import { Clock3, Loader2, ShieldCheck } from 'lucide-react'
import { Button, LoadingButton, Notice, StatusBadge } from '../../components/ui'
import { createCheckout } from '../../features/payments/api'
import { formatCountdown, secondsRemaining } from '../../features/payments/types'
import type { Booking } from '../../features/rides/types'

export function PayPanel({ booking }: { booking: Booking }) {
  const [seconds, setSeconds] = useState(() => secondsRemaining(booking.hold_expires_at))
  const [working, setWorking] = useState(false)
  const [error, setError] = useState('')
  useEffect(() => { const timer = window.setInterval(() => setSeconds(secondsRemaining(booking.hold_expires_at)), 1000); return () => window.clearInterval(timer) }, [booking.hold_expires_at])
  if (!['awaiting_payment', 'accepted'].includes(booking.status)) return null
  const pay = async () => { setWorking(true); setError(''); try { const checkout = await createCheckout(booking.id); if (!checkout.checkout_url) throw new Error('The sandbox checkout URL was not returned.'); window.location.assign(checkout.checkout_url) } catch (e) { setError(e instanceof Error ? e.message : 'Sandbox checkout could not be started.') } finally { setWorking(false) } }
  const expired = seconds <= 0
  return <div className="rounded-2xl border border-cyan-200 bg-cyan-50 p-6"><div className="flex items-start justify-between gap-4"><div><p className="text-xs font-bold uppercase tracking-[0.16em] text-cyan-700">SANDBOX — NO REAL MONEY</p><h2 className="mt-2 font-display text-2xl font-bold text-navy-900">Pay to hold your seats.</h2></div><StatusBadge tone={expired ? 'navy' : 'amber'}>{expired ? 'Hold expired' : <><Clock3 className="mr-1 inline" size={13} /> {formatCountdown(seconds)}</>}</StatusBadge></div><div className="mt-5 grid grid-cols-3 gap-3 text-sm"><div><p className="text-muted">Fare</p><p className="font-bold text-navy-900">Rs. {Number(booking.amount).toLocaleString()}</p></div><div><p className="text-muted">Platform fee</p><p className="font-bold text-navy-900">Rs. 0</p></div><div><p className="text-muted">Total</p><p className="font-bold text-navy-900">Rs. {Number(booking.amount).toLocaleString()}</p></div></div><p className="mt-5 text-sm leading-6 text-muted">The price comes from the booking record. Payment confirmation can only happen after the signed sandbox provider webhook is verified by the backend.</p>{error && <div className="mt-4"><Notice type="error">{error}</Notice></div>}<LoadingButton loading={working} disabled={expired || booking.status === 'accepted'} className="mt-5" onClick={() => void pay()}><ShieldCheck size={16} /> {booking.status === 'accepted' ? 'Waiting for payment state' : 'Pay in Sandbox Checkout'}</LoadingButton>{booking.status === 'accepted' && <p className="mt-3 text-xs text-muted">The provider is still finalizing the temporary hold. Refresh in a moment.</p>}</div>
}
