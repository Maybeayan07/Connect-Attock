import { Bell } from 'lucide-react'
import { Link } from 'react-router-dom'
import { useAuth } from '../../hooks/useAuth'
import { useNotifications } from './useNotifications'
export function NotificationBell() { const { user } = useAuth(); const { unreadCount } = useNotifications(); if (!user) return null; return <Link to="/notifications" className="relative grid h-10 w-10 place-items-center rounded-full border border-navy-900/10 text-navy-900 transition hover:border-cyan-500 hover:text-cyan-700" aria-label={unreadCount ? `${unreadCount} unread notifications` : 'Notifications'}><Bell size={17} />{unreadCount > 0 && <span className="absolute -right-1 -top-1 grid min-h-4 min-w-4 place-items-center rounded-full bg-cyan-500 px-1 text-[9px] font-bold text-navy-950">{unreadCount > 9 ? '9+' : unreadCount}</span>}</Link> }
