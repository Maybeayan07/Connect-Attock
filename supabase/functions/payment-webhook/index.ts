import { adminClient, bad, corsHeaders, json } from '../_shared/http.ts'
import { providerFromEnv } from '../_shared/payment.ts'

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return bad('POST required', 405)
  try {
    const rawBody = await request.text()
    const provider = providerFromEnv()
    if (!await provider.verifyWebhook(rawBody, request.headers)) return bad('Invalid or expired webhook signature', 401)
    const event = provider.parseWebhookEvent(rawBody)
    const payloadHash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(rawBody)).then((bytes) => [...new Uint8Array(bytes)].map((value) => value.toString(16).padStart(2, '0')).join(''))
    const admin = adminClient()
    const { data, error } = await admin.rpc('payment_process_webhook', { p_provider: provider.name, p_provider_event_id: event.providerEventId, p_payment_id: event.paymentId, p_provider_reference: event.providerReference, p_event_type: event.eventType, p_event_status: event.status, p_amount: event.amount, p_currency: event.currency, p_signature_verified: true, p_payload_hash: payloadHash, p_safe_metadata: event.metadata })
    if (error) throw error
    return json(data)
  } catch (error) { return bad(error instanceof Error ? error.message : 'Webhook processing failed.', 400) }
})
