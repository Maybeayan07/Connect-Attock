import { describe, expect, it } from 'vitest'
import { getErrorMessage } from './errors'

describe('getErrorMessage', () => {
  it('preserves native Error messages', () => expect(getErrorMessage(new Error('native failure'), 'fallback')).toBe('native failure'))
  it('preserves PostgrestError-shaped details and code', () => expect(getErrorMessage({ message: 'insert failed', details: 'Row violates policy', hint: 'Check RLS', code: '42501' }, 'fallback')).toContain('insert failed'))
  it('preserves StorageError-shaped messages', () => expect(getErrorMessage({ message: 'The resource already exists', statusCode: '409' }, 'fallback')).toBe('The resource already exists'))
  it('uses fallback only when no useful message exists', () => expect(getErrorMessage({ details: null }, 'Useful fallback')).toBe('Useful fallback'))
})
