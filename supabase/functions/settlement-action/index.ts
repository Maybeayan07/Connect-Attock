import { adminClient, bad, corsHeaders, isAdmin, json, parseJson, requireUser } from '../_shared/http.ts'

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const { user } = await requireUser(request)
    const admin = adminClient()
    if (!await isAdmin(admin, user.id)) return bad('Admin role required', 403)
    const body = await parseJson(request) as { settlement_id?: string; reference?: string }
    if (!body.settlement_id || !body.reference?.trim()) return bad('settlement_id and reference are required')
    const { data, error } = await admin.rpc('payment_mark_settlement_paid', { p_settlement_id: body.settlement_id, p_admin_id: user.id, p_reference: body.reference.trim() })
    if (error) throw error
    return json({ settlement_id: data, status: 'paid' })
  } catch (error) { return bad(error instanceof Error ? error.message : 'Settlement action failed.', 400) }
})
