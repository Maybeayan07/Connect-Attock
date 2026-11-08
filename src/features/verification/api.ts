import { supabase } from '../../lib/supabase'
import { validateVerificationFile } from './validation'

export const verificationDocumentTypes = ['identity', 'driving_licence', 'vehicle_registration', 'vehicle_image'] as const
export type VerificationDocumentType = typeof verificationDocumentTypes[number]
export type VerificationDocument = { id: string; document_type: VerificationDocumentType; storage_path: string; status: string; rejection_reason: string | null; created_at: string }
export type ProviderVehicle = { id: string; provider_id: string; make: string; model: string; year: number | null; color: string | null; seats: number; status: string }
export type ProviderReview = { user_id: string; full_name: string; verification_status: string; rejection_reason: string | null; documents: VerificationDocument[]; vehicles: ProviderVehicle[] }

function client() { if (!supabase) throw new Error('Connect Supabase before using provider verification.'); return supabase }

export async function getMyVerification(): Promise<{ profile: { verification_status: string; rejection_reason: string | null } | null; documents: VerificationDocument[] }> {
  const db = client()
  const { data: profile, error } = await db.from('driver_profiles').select('user_id,verification_status,rejection_reason,reviewed_at').maybeSingle()
  if (error) throw error
  const { data: documents, error: documentError } = await db.from('verification_documents').select('id,document_type,storage_path,status,rejection_reason,created_at').order('created_at', { ascending: false })
  if (documentError) throw documentError
  return { profile: profile as { verification_status: string; rejection_reason: string | null } | null, documents: (documents ?? []) as VerificationDocument[] }
}

function extensionFor(file: File): string {
  const extensions: Record<string, string> = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'application/pdf': 'pdf' }
  return extensions[file.type] ?? 'bin'
}

export async function uploadVerificationDocument(userId: string, type: VerificationDocumentType, file: File): Promise<void> {
  const db = client()
  const validationError = validateVerificationFile(file)
  if (validationError) throw new Error(validationError)
  const path = `${userId}/${type}.${extensionFor(file)}`
  const { error: uploadError } = await db.storage.from('verification-documents').upload(path, file, { contentType: file.type, upsert: true })
  if (uploadError) throw uploadError

  const { data: existing, error: existingError } = await db.from('verification_documents').select('id,storage_path,status').eq('user_id', userId).eq('document_type', type).neq('storage_path', path)
  if (existingError) throw existingError
  const { data: samePath, error: samePathError } = await db.from('verification_documents').select('id').eq('user_id', userId).eq('document_type', type).eq('storage_path', path).maybeSingle()
  if (samePathError) throw samePathError
  if (samePath) {
    const { error: removeRowError } = await db.from('verification_documents').delete().eq('id', samePath.id)
    if (removeRowError) throw removeRowError
  }
  const { error } = await db.from('verification_documents').insert({ user_id: userId, document_type: type, storage_path: path, status: 'pending', reviewed_by: null, reviewed_at: null, rejection_reason: null })
  if (error) throw error
  if (existing?.length) {
    const oldPaths = existing.map((row) => row.storage_path)
    await db.storage.from('verification-documents').remove(oldPaths)
    const { error: cleanupError } = await db.from('verification_documents').delete().eq('user_id', userId).eq('document_type', type).neq('storage_path', path)
    if (cleanupError) throw cleanupError
  }
}

export async function submitProviderVerification(): Promise<string> { const { data, error } = await client().rpc('submit_provider_verification'); if (error) throw error; return data as string }
export async function getSignedVerificationUrl(path: string): Promise<string> { const { data, error } = await client().storage.from('verification-documents').createSignedUrl(path, 300); if (error) throw error; return data.signedUrl }
export async function listPendingProviderReviews(): Promise<ProviderReview[]> { const db = client(); const { data, error } = await db.from('driver_profiles').select('user_id,verification_status,rejection_reason,profiles!inner(full_name),verification_documents(id,document_type,storage_path,status,rejection_reason,created_at),vehicles(id,provider_id,make,model,year,color,seats,status)').eq('verification_status', 'pending').order('created_at', { ascending: true }); if (error) throw error; return (data ?? []).map((row: any) => ({ user_id: row.user_id, full_name: row.profiles?.full_name ?? 'Provider', verification_status: row.verification_status, rejection_reason: row.rejection_reason ?? null, documents: (row.verification_documents ?? []) as VerificationDocument[], vehicles: (row.vehicles ?? []) as ProviderVehicle[] })) }
export async function reviewProvider(providerId: string, approve: boolean, reason = '') { const { data, error } = await client().rpc('admin_review_provider', { p_provider_id: providerId, p_approve: approve, p_reason: reason || null }); if (error) throw error; return data }
export async function reviewVehicle(vehicleId: string, approve: boolean, reason = '') { const { data, error } = await client().rpc('admin_review_vehicle', { p_vehicle_id: vehicleId, p_approve: approve, p_reason: reason || null }); if (error) throw error; return data }
