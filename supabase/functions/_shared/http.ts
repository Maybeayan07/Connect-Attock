import { createClient, type SupabaseClient, type User } from 'https://esm.sh/@supabase/supabase-js@2'

export const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-mock-signature, x-mock-timestamp', 'Access-Control-Allow-Methods': 'POST, GET, OPTIONS' }

export function json(body: unknown, status = 200) { return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }) }
export function bad(message: string, status = 400) { return json({ error: message }, status) }
export function env(name: string) { const value = Deno.env.get(name); if (!value) throw new Error(`Missing Edge Function secret: ${name}`); return value }
export function adminClient(): SupabaseClient { return createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false, autoRefreshToken: false } }) }
export function authClient(token: string): SupabaseClient { return createClient(env('SUPABASE_URL'), env('SUPABASE_ANON_KEY'), { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false, autoRefreshToken: false } }) }
export async function requireUser(request: Request): Promise<{ user: User; token: string }> { const header = request.headers.get('Authorization'); if (!header?.startsWith('Bearer ')) throw new Error('Authentication required'); const token = header.slice(7); const client = authClient(token); const { data, error } = await client.auth.getUser(token); if (error || !data.user) throw new Error('Invalid session'); return { user: data.user, token } }
export async function isAdmin(client: SupabaseClient, userId: string) { const { data, error } = await client.from('user_roles').select('role').eq('user_id', userId).eq('role', 'admin').maybeSingle(); if (error) throw error; return Boolean(data) }
export function parseJson(request: Request) { return request.json().catch(() => { throw new Error('Invalid JSON body') }) }
