import { adminClient, bad, corsHeaders, isAdmin, json, requireUser } from '../_shared/http.ts'

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const { user } = await requireUser(request)
    const url = new URL(request.url)
    const paymentId = url.searchParams.get('payment_id')
    if (!paymentId) return bad('payment_id is required')
    const admin = adminClient()
    const adminUser = await isAdmin(admin, user.id)
    const { data: payment, error } = await admin.from('payments').select('id,payer_id,ride_booking_id,amount,currency,status,provider,provider_reference,expires_at,succeeded_at,failed_at,cancelled_at,under_review_reason,created_at,updated_at').eq('id', paymentId).single()
    if (error || !payment) return bad('Payment not found', 404)
    if (!adminUser && payment.payer_id !== user.id) return bad('Payment not found', 404)
    const { data: transactions } = await admin.from('payment_transactions').select('id,event_type,transaction_type,amount,status,signature_verified,created_at,occurred_at').eq('payment_id', paymentId).order('created_at', { ascending: false }).limit(20)
    return json({ payment, transactions: transactions ?? [] })
  } catch (error) { return bad(error instanceof Error ? error.message : 'Payment status unavailable.', 400) }
})
