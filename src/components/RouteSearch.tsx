import { ArrowRight, CalendarDays, Search } from 'lucide-react'
import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Button, SelectInput } from './ui'

export function RouteSearch({ compact = false }: { compact?: boolean }) {
  const [from, setFrom] = useState('Rawalpindi')
  const [to, setTo] = useState('Attock')
  return <div className={compact ? 'rounded-2xl border border-navy-900/10 bg-white p-4 shadow-card' : 'rounded-2xl border border-white/20 bg-white p-4 shadow-2xl shadow-navy-950/20 sm:p-5'}><div className="mb-4 flex items-center justify-between"><div><p className="text-xs font-bold uppercase tracking-[0.17em] text-cyan-700">Route search</p><p className="mt-1 text-sm text-muted">Start with the city pair</p></div><CalendarDays className="text-cyan-600" size={21} /></div><div className="grid gap-3 sm:grid-cols-[1fr_auto_1fr] sm:items-end"><SelectInput label="From" value={from} onChange={(e) => setFrom(e.target.value)}><option>Rawalpindi</option><option>Attock</option></SelectInput><div className="hidden pb-3 text-muted sm:block"><ArrowRight size={18} /></div><SelectInput label="To" value={to} onChange={(e) => setTo(e.target.value)}><option>Attock</option><option>Rawalpindi</option></SelectInput></div><Link to={`/find-a-ride?from=${from}&to=${to}`} className="mt-4 block"><Button type="button" className="w-full"><Search size={16} /> Find available routes</Button></Link><p className="mt-3 text-center text-xs text-muted">Ride search is being connected in Phase 2. This form will not create a booking.</p></div>
}

export function PublicHero({ eyebrow, title, body, children, dark = false }: { eyebrow: string; title: string; body: string; children?: React.ReactNode; dark?: boolean }) { return <section className={dark ? 'bg-navy-900 text-white' : 'bg-sand'}><div className="mx-auto max-w-7xl px-5 py-16 sm:px-8 sm:py-20 lg:px-10 lg:py-24"><div className="max-w-3xl"><p className="mb-4 text-[11px] font-bold uppercase tracking-[0.2em] text-cyan-700">{eyebrow}</p><h1 className="font-display text-4xl font-bold leading-[1.03] tracking-[-0.05em] text-navy-900 sm:text-6xl">{title}</h1><p className="mt-6 max-w-2xl text-base leading-7 text-muted sm:text-lg">{body}</p>{children && <div className="mt-8">{children}</div>}</div></div></section> }
