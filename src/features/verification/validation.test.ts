import { describe, expect, it } from 'vitest'
import { hasRequiredVerificationDocuments, validateVerificationFile } from './validation'
describe('provider verification validation', () => {
  it('accepts supported files within the 10 MB limit', () => expect(validateVerificationFile({ type: 'application/pdf', size: 1024 })).toBeNull())
  it('rejects unsupported types and oversized files', () => { expect(validateVerificationFile({ type: 'text/plain', size: 10 })).toContain('JPG'); expect(validateVerificationFile({ type: 'image/png', size: 10 * 1024 * 1024 + 1 })).toContain('10 MB') })
  it('requires all four provider document types', () => { expect(hasRequiredVerificationDocuments(['identity', 'driving_licence', 'vehicle_registration'])).toBe(false); expect(hasRequiredVerificationDocuments(['identity', 'driving_licence', 'vehicle_registration', 'vehicle_image'])).toBe(true) })
})
