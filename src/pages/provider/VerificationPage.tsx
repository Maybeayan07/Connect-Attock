import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { CheckCircle2, FileLock2, UploadCloud } from 'lucide-react'
import { Button, Eyebrow, LoadingButton, Notice, SectionHeading, StatusBadge } from '../../components/ui'
import { useAuth } from '../../hooks/useAuth'
import { getErrorMessage } from '../../lib/errors'
import { getMyVerification, submitProviderVerification, uploadVerificationDocument, verificationDocumentTypes, type VerificationDocumentType } from '../../features/verification/api'
import { hasRequiredVerificationDocuments } from '../../features/verification/validation'

const labels: Record<VerificationDocumentType, string> = { identity: 'Identity document', driving_licence: 'Driving licence', vehicle_registration: 'Vehicle registration', vehicle_image: 'Vehicle image' }
type UploadState = { status: 'idle' | 'uploading' | 'uploaded' | 'failed'; fileName?: string; error?: string }
const initialUploadState = (): Record<VerificationDocumentType, UploadState> => ({ identity: { status: 'idle' }, driving_licence: { status: 'idle' }, vehicle_registration: { status: 'idle' }, vehicle_image: { status: 'idle' } })
const fileName = (path: string) => path.split('/').pop() ?? path

export function VerificationPage() {
  const { user } = useAuth()
  const [status, setStatus] = useState('not_submitted')
  const [reason, setReason] = useState<string | null>(null)
  const [documents, setDocuments] = useState<any[]>([])
  const [files, setFiles] = useState<Partial<Record<VerificationDocumentType, File>>>({})
  const [uploadStates, setUploadStates] = useState(initialUploadState)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [working, setWorking] = useState(false)

  const load = async () => {
    try {
      const result = await getMyVerification()
      setStatus(result.profile?.verification_status ?? 'not_submitted')
      setReason(result.profile?.rejection_reason ?? null)
      setDocuments(result.documents)
      setUploadStates((current) => {
        const next = { ...current }
        for (const type of verificationDocumentTypes) {
          const document = result.documents.find((item) => item.document_type === type)
          if (document && next[type].status !== 'uploading') next[type] = { status: 'uploaded', fileName: fileName(document.storage_path) }
        }
        return next
      })
    } catch (e) { setError(getErrorMessage(e, 'Verification could not be loaded.')) }
  }

  useEffect(() => { if (user) void load() }, [user])

  const upload = async (type: VerificationDocumentType) => {
    if (!user || !files[type]) return
    const selected = files[type]!
    setWorking(true); setError(''); setSuccess('')
    setUploadStates((current) => ({ ...current, [type]: { status: 'uploading', fileName: selected.name } }))
    try {
      await uploadVerificationDocument(user.id, type, selected)
      setFiles((current) => ({ ...current, [type]: undefined }))
      setUploadStates((current) => ({ ...current, [type]: { status: 'uploaded', fileName: selected.name } }))
      setSuccess(`${labels[type]} uploaded privately.`)
      await load()
    } catch (e) {
      setUploadStates((current) => ({ ...current, [type]: { status: 'failed', fileName: selected.name, error: getErrorMessage(e, 'Upload failed.') } }))
      setError(getErrorMessage(e, 'Upload failed.'))
    } finally { setWorking(false) }
  }

  const hasAllDocuments = useMemo(() => hasRequiredVerificationDocuments(documents.map((document) => document.document_type)), [documents])
  const submit = async () => {
    if (!hasAllDocuments) { setError('Upload all four required documents before submitting.'); return }
    setWorking(true); setError(''); setSuccess('')
    try { await submitProviderVerification(); setSuccess('Verification submitted. An administrator will review your documents.'); await load() }
    catch (e) { setError(getErrorMessage(e, 'Verification submission failed.')) }
    finally { setWorking(false) }
  }

  if (!user) return <Notice>Log in to submit provider verification.</Notice>
  return <section className="bg-sand px-5 py-12 sm:px-8 lg:px-10 lg:py-16"><div className="mx-auto max-w-4xl"><Link to="/dashboard" className="text-sm font-bold text-cyan-700">← Back to dashboard</Link><div className="mt-8"><SectionHeading eyebrow="Provider verification" title="Show the people behind the route." body="Upload the minimum documents needed to offer rides. Files stay in a private bucket and are shown to reviewers through short-lived signed links." /></div>{(error || success) && <div className="mt-7"><Notice type={error ? 'error' : 'success'}>{error || success}</Notice></div>}<div className="mt-8 flex items-center gap-3 rounded-2xl border border-navy-900/10 bg-white p-6 shadow-card"><StatusBadge tone={status === 'approved' ? 'green' : status === 'rejected' ? 'navy' : 'amber'}>{status.replace('_', ' ')}</StatusBadge><span className="text-sm text-muted">{reason ?? 'Complete all four document uploads before submitting.'}</span></div><div className="mt-6 grid gap-4 md:grid-cols-2">{verificationDocumentTypes.map((type) => { const state = uploadStates[type]; return <article key={type} className="rounded-2xl border border-navy-900/10 bg-white p-6 shadow-card"><div className="flex items-start gap-3"><FileLock2 className="mt-1 text-cyan-600" size={20} /><div><h2 className="font-display text-xl font-bold text-navy-900">{labels[type]}</h2><p className="mt-1 text-xs leading-5 text-muted">Private storage · JPG, PNG, WEBP or PDF · max 10 MB</p></div></div><p className="mt-5 text-sm font-semibold text-navy-900">{state.status === 'uploading' ? 'Uploading…' : state.status === 'uploaded' ? `Uploaded · ${state.fileName}` : state.status === 'failed' ? 'Upload failed' : documents.some((doc) => doc.document_type === type) ? 'Uploaded' : 'Required'}</p>{state.status === 'failed' && <p className="mt-2 text-sm text-red-700">{state.error}</p>}<input className="mt-3 block w-full text-sm" type="file" accept="image/jpeg,image/png,image/webp,application/pdf" onChange={(event) => setFiles((current) => ({ ...current, [type]: event.target.files?.[0] }))} /><Button className="mt-4" type="button" variant="secondary" disabled={!files[type] || working} onClick={() => void upload(type)}><UploadCloud size={16} /> {state.status === 'uploaded' ? 'Replace file' : 'Upload privately'}</Button></article> })}</div>{status === 'rejected' || status === 'not_submitted' ? <div className="mt-8"><LoadingButton loading={working} disabled={!hasAllDocuments} onClick={() => void submit()}><CheckCircle2 size={16} /> Submit for review</LoadingButton>{!hasAllDocuments && <p className="mt-3 text-sm text-muted">Upload all four documents to enable submission.</p>}</div> : <p className="mt-8 text-sm text-muted">Your submission is locked while it is pending or approved. If rejected, review the reason and upload replacement documents before resubmitting.</p>}</div></section>
}
