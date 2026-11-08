type SupabaseLikeError = {
  message?: unknown
  details?: unknown
  hint?: unknown
  code?: unknown
}

export function getErrorMessage(error: unknown, fallback = 'Something went wrong.'): string {
  if (error instanceof Error && error.message.trim()) return error.message
  if (typeof error === 'string' && error.trim()) return error
  if (error && typeof error === 'object') {
    const value = error as SupabaseLikeError
    const message = typeof value.message === 'string' ? value.message.trim() : ''
    const details = typeof value.details === 'string' ? value.details.trim() : ''
    const hint = typeof value.hint === 'string' ? value.hint.trim() : ''
    const code = typeof value.code === 'string' ? value.code.trim() : ''
    const parts = [message, details && details !== message ? details : '', hint && hint !== message ? `Hint: ${hint}` : ''].filter(Boolean)
    if (parts.length) return code && !parts.join(' ').includes(code) ? `${parts.join(' ')} (${code})` : parts.join(' ')
  }
  return fallback
}
