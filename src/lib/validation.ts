import { z } from 'zod'

export const signupSchema = z.object({
  fullName: z.string().min(2, 'Enter your full name.'),
  email: z.string().email('Enter a valid email address.'),
  phone: z.string().min(7, 'Enter a valid phone number.'),
  password: z.string().min(8, 'Use at least 8 characters.'),
  confirmPassword: z.string(),
  terms: z.literal(true, { errorMap: () => ({ message: 'You need to accept the terms.' }) }),
}).refine((data) => data.password === data.confirmPassword, { path: ['confirmPassword'], message: 'Passwords do not match.' })

export const loginSchema = z.object({ email: z.string().email('Enter a valid email address.'), password: z.string().min(1, 'Enter your password.') })
export const resetRequestSchema = z.object({ email: z.string().email('Enter a valid email address.') })
export const updatePasswordSchema = z.object({ password: z.string().min(8, 'Use at least 8 characters.'), confirmPassword: z.string() }).refine((data) => data.password === data.confirmPassword, { path: ['confirmPassword'], message: 'Passwords do not match.' })
export const profileSchema = z.object({ fullName: z.string().min(2, 'Enter your full name.'), phone: z.string().min(7, 'Enter a valid phone number.'), avatarUrl: z.string().url('Use a valid URL.').or(z.literal('')), notificationEmail: z.boolean() })

export type SignupForm = z.infer<typeof signupSchema>
export type LoginForm = z.infer<typeof loginSchema>
export type ProfileForm = z.infer<typeof profileSchema>
