import { adminClient, bad, corsHeaders, isAdmin, json, parseJson, requireUser } from '../_shared/http.ts'
import { providerFromEnv, type PaymentRecord } from '../_shared/payment.ts'

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const { user } = await requireUser(request)
    const admin = adminClient()
    if (!await isAdmin(admin, user.id)) return bad('Admin role required', 403)
    const body = await parseJson(request) as { payment_id?: string; amount?: string | number; reason?: string }
    if (!body.payment_id || !body.reason?.trim()) return bad('payment_id and reason are required')
    const { data: payment, error: paymentError } = await admin.from('payments').select('id,amount,currency,provider,status,expires_at,payer_id,ride_booking_id').eq('id', body.payment_id).single()
    if (paymentError || !payment) return bad('Payment not found', 404)
    const amount = body.amount == null ? String(payment.amount) : String(body.amount)
    const { data: refundId, error: requestError } = await admin.rpc('payment_request_refund', { p_payment_id: payment.id, p_amount: amount, p_reason: body.reason.trim(), p_requested_by: user.id })
    if (requestError) throw requestError
    const provider = providerFromEnv()
    let providerResult: { providerReference: string }
    try { providerResult = await provider.refund(payment as PaymentRecord, amount, body.reason) } catch (providerError) { await admin.rpc('payment_process_refund', { p_refund_id: refundId, p_admin_id: user.id, p_provider_reference: null, p_success: false }); throw providerError }
    const { data: result, error: processError } = await admin.rpc('payment_process_refund', { p_refund_id: refundId, p_admin_id: user.id, p_provider_reference: providerResult.providerReference, p_success: true })
    if (processError) throw processError
    return json(result)
  } catch (error) { return bad(error instanceof Error ? error.message : 'Refund failed.', 400) }
})
