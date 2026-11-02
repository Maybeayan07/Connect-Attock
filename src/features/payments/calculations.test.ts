import { describe, expect, it } from 'vitest'
import { buildBreakdown, calculateCommission, toMinorUnits } from './calculations'
import { constantTimeEqual, isFreshTimestamp, safeWebhookStatus } from './security'

describe('sandbox payment money calculations', () => {
  it('uses integer minor units for PKR rounding', () => expect(toMinorUnits('400.05')).toBe(40005))
  it('computes a 10 percent commission and provider net', () => expect(calculateCommission('400.00', '0.10', '0')).toEqual({ gross: '400.00', commission: '40.00', net: '360.00' }))
  it('rounds percentage commission at the minor-unit boundary', () => expect(calculateCommission('99.99', '0.10', '0.01')).toEqual({ gross: '99.99', commission: '10.01', net: '89.98' }))
  it('keeps the passenger price breakdown explicit', () => expect(buildBreakdown('400.00', 0)).toEqual({ fare: 400, platformFee: 0, total: 400, currency: 'PKR' }))
})

describe('webhook security helpers', () => {
  it('compares signatures without early length-based success', () => { expect(constantTimeEqual('abc', 'abc')).toBe(true); expect(constantTimeEqual('abc', 'abd')).toBe(false); expect(constantTimeEqual('abc', 'ab')).toBe(false) })
  it('rejects stale timestamps', () => expect(isFreshTimestamp('100', 1000, 300)).toBe(false))
  it('accepts only known provider states', () => { expect(safeWebhookStatus('succeeded')).toBe('succeeded'); expect(safeWebhookStatus('success')).toBeNull() })
})
