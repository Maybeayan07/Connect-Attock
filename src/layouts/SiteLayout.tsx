import { useState } from 'react'
import { Link, NavLink, Outlet, useLocation } from 'react-router-dom'
import { Menu, X, ArrowUpRight, MapPin, UserRound } from 'lucide-react'
import { NAV_LINKS, cn } from '../lib/utils'
import { useAuth } from '../hooks/useAuth'

export function BrandMark({ light = false }: { light?: boolean }) {
  return <Link to="/" className="group inline-flex items-center gap-3" aria-label="Connect Attock home"><span className={cn('relative grid h-10 w-10 place-items-center rounded-xl border', light ? 'border-white/20 bg-white/10' : 'border-navy-900/10 bg-navy-900')}><span className="font-display text-sm font-bold text-cyan-400">CA</span><span className="absolute -right-1 -top-1 h-2.5 w-2.5 rounded-full bg-cyan-400 ring-4 ring-white" /></span><span className={cn('font-display text-lg font-bold tracking-tight', light ? 'text-white' : 'text-navy-900')}>Connect <span className={light ? 'text-cyan-400' : 'text-cyan-600'}>Attock</span></span></Link>
}

export function SiteLayout() {
  const [open, setOpen] = useState(false)
  const { user } = useAuth()
  const location = useLocation()
  return <div className="min-h-screen bg-white text-ink">
    <header className="sticky top-0 z-50 border-b border-navy-900/10 bg-white/90 backdrop-blur-xl">
      <div className="mx-auto flex h-[74px] max-w-7xl items-center justify-between px-5 sm:px-8 lg:px-10">
        <BrandMark />
        <nav className="hidden items-center gap-7 lg:flex" aria-label="Primary navigation">
          {NAV_LINKS.map((item) => <NavLink key={item.to} to={item.to} className={({ isActive }) => cn('text-sm font-semibold transition-colors hover:text-cyan-600', isActive ? 'text-cyan-600' : 'text-muted')}>{item.label}</NavLink>)}
          <NavLink to="/how-it-works" className={({ isActive }) => cn('text-sm font-semibold transition-colors hover:text-cyan-600', isActive ? 'text-cyan-600' : 'text-muted')}>How it works</NavLink>
        </nav>
        <div className="hidden items-center gap-3 lg:flex">
          {user ? <Link to="/dashboard" className="inline-flex items-center gap-2 rounded-full border border-navy-900/10 px-4 py-2 text-sm font-bold text-navy-900 hover:border-cyan-500 hover:text-cyan-600"><UserRound size={16} /> Dashboard</Link> : <><Link to="/login" className="px-3 py-2 text-sm font-bold text-navy-900 hover:text-cyan-600">Log in</Link><Link to="/signup" className="inline-flex items-center gap-2 rounded-full bg-navy-900 px-4 py-2.5 text-sm font-bold text-white shadow-lg shadow-navy-900/15 transition hover:-translate-y-0.5 hover:bg-navy-800">Join the route <ArrowUpRight size={16} /></Link></>}
        </div>
        <button type="button" onClick={() => setOpen((value) => !value)} className="grid h-11 w-11 place-items-center rounded-full border border-navy-900/10 lg:hidden" aria-expanded={open} aria-label="Toggle menu">{open ? <X size={21} /> : <Menu size={21} />}</button>
      </div>
      {open && <div className="border-t border-navy-900/10 bg-white px-5 py-5 lg:hidden"><nav className="flex flex-col gap-1" aria-label="Mobile navigation">{[...NAV_LINKS, { label: 'How it works', to: '/how-it-works' }].map((item) => <Link key={item.to} onClick={() => setOpen(false)} to={item.to} className={cn('rounded-xl px-4 py-3 font-semibold', location.pathname === item.to ? 'bg-cyan-50 text-cyan-700' : 'text-ink')}>{item.label}</Link>)}<div className="mt-3 flex gap-3 border-t border-navy-900/10 pt-4">{user ? <Link to="/dashboard" onClick={() => setOpen(false)} className="flex-1 rounded-full bg-navy-900 px-4 py-3 text-center text-sm font-bold text-white">Dashboard</Link> : <><Link to="/login" onClick={() => setOpen(false)} className="flex-1 rounded-full border border-navy-900/10 px-4 py-3 text-center text-sm font-bold">Log in</Link><Link to="/signup" onClick={() => setOpen(false)} className="flex-1 rounded-full bg-navy-900 px-4 py-3 text-center text-sm font-bold text-white">Join the route</Link></>}</div></nav></div>}
    </header>
    <main><Outlet /></main>
    <footer className="bg-navy-950 text-white"><div className="mx-auto max-w-7xl px-5 py-14 sm:px-8 lg:px-10"><div className="grid gap-10 lg:grid-cols-[1.2fr_1fr_1fr_1fr]"><div><BrandMark light /><p className="mt-5 max-w-xs text-sm leading-7 text-white/55">A clearer way to travel, shop and send between Rawalpindi and Attock.</p><div className="mt-5 flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.18em] text-cyan-400"><MapPin size={14} /> Rawalpindi ↔ Attock</div></div><FooterGroup title="Explore" links={NAV_LINKS} /><FooterGroup title="Company" links={[{ label: 'How it works', to: '/how-it-works' }, { label: 'About us', to: '/about' }, { label: 'Contact', to: '/contact' }, { label: 'FAQ', to: '/faq' }]} /><FooterGroup title="Policies" links={[{ label: 'Terms', to: '/terms' }, { label: 'Privacy', to: '/privacy' }, { label: 'Cancellation & refund', to: '/cancellation-refund' }, { label: 'Prohibited items', to: '/prohibited-items' }]} /></div><div className="mt-14 flex flex-col justify-between gap-3 border-t border-white/10 pt-5 text-xs text-white/45 sm:flex-row"><span>© {new Date().getFullYear()} Connect Attock. Phase 1 foundation.</span><span>Built for the route, not the rush.</span></div></div></footer>
  </div>
}
function FooterGroup({ title, links }: { title: string; links: { label: string; to: string }[] }) { return <div><p className="mb-4 text-xs font-bold uppercase tracking-[0.18em] text-white/45">{title}</p><div className="flex flex-col gap-3">{links.map((link) => <Link key={link.to} to={link.to} className="text-sm text-white/70 transition hover:text-cyan-400">{link.label}</Link>)}</div></div> }
