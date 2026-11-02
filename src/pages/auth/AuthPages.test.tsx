/** @vitest-environment jsdom */
import '@testing-library/jest-dom/vitest'
import { createRef } from 'react'
import { MemoryRouter } from 'react-router-dom'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { TextInput } from '../../components/ui'

const { signUp } = vi.hoisted(() => ({ signUp: vi.fn() }))

vi.mock('../../lib/supabase', () => ({
  isSupabaseConfigured: true,
  supabase: { auth: { signUp } },
}))

import { Signup } from './AuthPages'

describe('form ref forwarding', () => {
  beforeEach(() => signUp.mockReset())

  it('forwards TextInput refs to the real input element', () => {
    const ref = createRef<HTMLInputElement>()
    render(<TextInput ref={ref} label="Email" />)
    expect(ref.current).toBeInstanceOf(HTMLInputElement)
  })

  it('submits the typed signup email and password through react-hook-form', async () => {
    const user = userEvent.setup()
    signUp.mockResolvedValue({ data: { session: null }, error: null })
    render(<MemoryRouter><Signup /></MemoryRouter>)

    await user.type(screen.getByLabelText('Full name'), 'Ada Attock')
    await user.type(screen.getByLabelText('Phone number'), '03001234567')
    await user.type(screen.getByLabelText('Email address'), 'ada@example.com')
    await user.type(screen.getByLabelText('Password'), 'correct-horse-battery')
    await user.type(screen.getByLabelText('Confirm password'), 'correct-horse-battery')
    await user.click(screen.getByRole('checkbox'))
    await user.click(screen.getByRole('button', { name: /create account/i }))

    expect(signUp).toHaveBeenCalledWith(expect.objectContaining({
      email: 'ada@example.com',
      password: 'correct-horse-battery',
      options: expect.objectContaining({ data: { full_name: 'Ada Attock', phone: '03001234567' } }),
    }))
  })
})
