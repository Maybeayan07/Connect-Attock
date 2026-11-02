import { adminClient, bad, corsHeaders, json, parseJson, requireUser } from '../_shared/http.ts'
import { providerFromEnv, type PaymentRecord } from '../_shared/payment.ts'

const attempts = new Map<string, number[]>()
function allow(userId: string) { const now = Date.now(); const recent = (attempts.get(userId) ?? []).filter((value) => now - value < 60_000); if (recent.length >= 8) return false; recent.push(now); attempts.set(userId, recent); return true }

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const { user } = await requireUser(request)
    if (!allow(user.id)) return bad('Too many checkout attempts. Please wait a minute.', 429)
    const body = await parseJson(request) as { booking_id?: string }
    if (!body.booking_id) return bad('booking_id is required')
    const admin = adminClient()
    const provider = providerFromEnv()
    const idempotencyKey = `ride-booking:${body.booking_id}`
    const { data, error } = await admin.rpc('payment_create_checkout', { p_booking_id: body.booking_id, p_payer_id: user.id, p_idempotency_key: idempotencyKey, p_provider: provider.name })
    if (error) throw error
    const payment = data as { payment_id: string; amount: string | number; currency: string; status: string; expires_at: string | null; checkout_url?: string | null; provider?: string }
    if (payment.checkout_url) return json(payment)
    const { data: record, error: recordError } = await admin.from('payments').select('id,amount,currency,provider,status,expires_at,payer_id,ride_booking_id').eq('id', payment.payment_id).single()
    if (recordError) throw recordError
    const checkout = await provider.createCheckout(record as PaymentRecord)
    const { data: updated, error: updateError } = await admin.from('payments').update({ status: 'pending', checkout_url: checkout.checkoutUrl, provider_reference: checkout.providerReference, updated_at: new Date().toISOString() }).eq('id', payment.payment_id).select('id,amount,currency,status,expires_at,checkout_url,provider').single()
    if (updateError) throw updateError
    return json(updated)
  } catch (error) { return bad(error instanceof Error ? error.message : 'Checkout could not be created.', 400) }
})
