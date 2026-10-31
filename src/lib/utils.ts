import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) { return twMerge(clsx(inputs)) }

export const NAV_LINKS = [
  { label: 'Find a ride', to: '/find-a-ride' },
  { label: 'Offer a ride', to: '/offer-a-ride' },
  { label: 'Shop on the way', to: '/shopping' },
  { label: 'Send a parcel', to: '/cargo-delivery' },
]

export const SERVICE_CARDS = [
  { number: '01', title: 'Find a ride', eyebrow: 'Ride sharing', description: 'Share the road between Rawalpindi and Attock with people you can trust.', to: '/find-a-ride', accent: 'cyan' },
  { number: '02', title: 'Shop on the way', eyebrow: 'On-the-way shopping', description: 'Get your essentials picked up by someone already making the journey.', to: '/shopping', accent: 'navy' },
  { number: '03', title: 'Send a parcel', eyebrow: 'Cargo & parcel', description: 'Move what matters with clearer handoffs, tracking and proof of delivery.', to: '/cargo-delivery', accent: 'sand' },
]

export const ROUTE_NAMES = ['Rawalpindi', 'Attock'] as const
