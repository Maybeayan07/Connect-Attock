import { env } from './http.ts'

export type PaymentStatus = 'created' | 'pending' | 'succeeded' | 'failed' | 'cancelled' | 'expired' | 'refunded' | 'partially_refunded' | 'under_review'
export type PaymentRecord = { id: string; amount: number | string; currency: string; provider: string; status: PaymentStatus; expires_at: string | null; payer_id: string; ride_booking_id: string | null }
export type CheckoutResult = { checkoutUrl: string; providerReference: string }
export type WebhookEvent = { providerEventId: string; paymentId: string; providerReference: string; eventType: string; status: 'succeeded' | 'failed' | 'cancelled' | 'pending'; amount: string; currency: string; metadata: Record<string, unknown> }

export interface PaymentProvider {
  name: string
  createCheckout(payment: PaymentRecord): Promise<CheckoutResult>
  verifyWebhook(rawBody: string, headers: Headers): Promise<boolean>
  parseWebhookEvent(rawBody: string): WebhookEvent
  getPaymentStatus(payment: PaymentRecord): Promise<PaymentStatus>
  refund(payment: PaymentRecord, amount: string, reason: string): Promise<{ providerReference: string }>
}

const encoder = new TextEncoder()
async function hmacHex(secret: string, message: string) { const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']); const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(message)); return [...new Uint8Array(signature)].map((value) => value.toString(16).padStart(2, '0')).join('') }
export async function signMockWebhook(rawBody: string, timestamp: string) { return hmacHex(env('MOCK_WEBHOOK_SECRET'), `${timestamp}.${rawBody}`) }
export function constantTimeEqual(left: string, right: string) { if (left.length !== right.length) return false; let result = 0; for (let index = 0; index < left.length; index += 1) result |= left.charCodeAt(index) ^ right.charCodeAt(index); return result === 0 }
export function isFreshTimestamp(timestamp: string, toleranceSeconds = 300) { const parsed = Number(timestamp); return Number.isFinite(parsed) && Math.abs(Math.floor(Date.now() / 1000) - parsed) <= toleranceSeconds }

export class MockSandboxProvider implements PaymentProvider {
  name = 'mock_sandbox'
  async createCheckout(payment: PaymentRecord): Promise<CheckoutResult> { const base = env('PUBLIC_APP_URL').replace(/\/$/, ''); return { checkoutUrl: `${base}/sandbox-checkout/${payment.id}`, providerReference: `mock_checkout_${payment.id}` } }
  async verifyWebhook(rawBody: string, headers: Headers) { const timestamp = headers.get('x-mock-timestamp') ?? ''; const supplied = headers.get('x-mock-signature') ?? ''; if (!isFreshTimestamp(timestamp)) return false; return constantTimeEqual(supplied, await signMockWebhook(rawBody, timestamp)) }
  parseWebhookEvent(rawBody: string): WebhookEvent { const event = JSON.parse(rawBody); return { providerEventId: String(event.id), paymentId: String(event.payment_id), providerReference: String(event.provider_reference), eventType: String(event.type), status: event.status, amount: String(event.amount), currency: String(event.currency), metadata: { sandbox: true, action: String(event.action ?? '') } } }
  async getPaymentStatus(payment: PaymentRecord): Promise<PaymentStatus> { return payment.status }
  async refund(payment: PaymentRecord, amount: string, reason: string) { return { providerReference: `mock_refund_${payment.id}_${Date.now()}` } }
}

export class SafepaySandboxProvider implements PaymentProvider {
  name = 'safepay_sandbox'
  private fail(): never { throw new Error('Safepay sandbox adapter is intentionally untested and not configured; provide documented sandbox credentials and verify the current public API before enabling it.') }
  createCheckout(_payment: PaymentRecord): Promise<CheckoutResult> { return this.fail() }
  verifyWebhook(_rawBody: string, _headers: Headers) { return Promise.resolve(false) }
  parseWebhookEvent(_rawBody: string): WebhookEvent { return this.fail() }
  getPaymentStatus(_payment: PaymentRecord): Promise<PaymentStatus> { return this.fail() }
  refund(_payment: PaymentRecord, _amount: string, _reason: string) { return this.fail() }
}

export function providerFromEnv(): PaymentProvider { const provider = (Deno.env.get('PAYMENT_PROVIDER') ?? 'mock').toLowerCase(); if (provider === 'mock' || provider === 'mock_sandbox') return new MockSandboxProvider(); if (provider === 'safepay' || provider === 'safepay_sandbox') return new SafepaySandboxProvider(); throw new Error(`Unsupported PAYMENT_PROVIDER: ${provider}`) }
