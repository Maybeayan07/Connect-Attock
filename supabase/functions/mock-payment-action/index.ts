import { adminClient, bad, corsHeaders, isAdmin, json, parseJson, requireUser } from '../_shared/http.ts'
import { signMockWebhook } from '../_shared/payment.ts'

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    if (Deno.env.get('ALLOW_MOCK_PAYMENTS') !== 'true') return bad('Mock payments are disabled in this environment.', 403)
    const { user } = await requireUser(request)
    const body = await parseJson(request) as { payment_id?: string; action?: 'success' | 'failure' | 'cancel' | 'replay' }
    if (!body.payment_id || !body.action) return bad('payment_id and action are required')
    const admin = adminClient()
    const { data: payment, error } = await admin.from('payments').select('id,amount,currency,provider_reference,status').eq('id', body.payment_id).single()
    if (error || !payment) return bad('Payment not found', 404)
    if (payment.provider !== 'mock_sandbox') return bad('This checkout is not using the Mock Sandbox provider')
    const adminUser = await isAdmin(admin, user.id)
    const { data: owner } = await admin.from('payments').select('payer_id').eq('id', body.payment_id).single()
    if (!adminUser && owner?.payer_id !== user.id) return bad('Payment not found', 404)
    const status = body.action === 'success' ? 'succeeded' : body.action === 'failure' ? 'failed' : body.action === 'cancel' ? 'cancelled' : 'succeeded'
    const eventId = body.action === 'replay' ? `mock_event_${payment.id}_success` : `mock_event_${payment.id}_${body.action}`
    const payload = JSON.stringify({ id: eventId, payment_id: payment.id, provider_reference: payment.provider_reference ?? `mock_payment_${payment.id}`, type: `payment.${status}`, action: body.action, status, amount: payment.amount, currency: payment.currency })
    const timestamp = String(Math.floor(Date.now() / 1000))
    const signature = await signMockWebhook(payload, timestamp)
    const webhookUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/payment-webhook`
    const response = await fetch(webhookUrl, { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-mock-timestamp': timestamp, 'x-mock-signature': signature }, body: payload })
    const result = await response.json()
    return json({ sandbox: true, webhook_status: response.status, result })
  } catch (error) { return bad(error instanceof Error ? error.message : 'Mock Sandbox action failed.', 400) }
})
