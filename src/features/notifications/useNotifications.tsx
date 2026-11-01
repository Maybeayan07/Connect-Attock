import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'

export type AppNotification = { id: string; type: string; title: string; body: string; action_url: string | null; read_at: string | null; created_at: string }
export function useNotifications() {
  const [notifications, setNotifications] = useState<AppNotification[]>([])
  const [loading, setLoading] = useState(true)
  useEffect(() => {
    if (!supabase) { setLoading(false); return }
    let channel: ReturnType<typeof supabase.channel> | null = null
    let active = true
    const load = async () => { const { data } = await supabase!.from('notifications').select('*').order('created_at', { ascending: false }).limit(40); if (active) { setNotifications((data as AppNotification[]) ?? []); setLoading(false) } }
    void load()
    channel = supabase.channel('connect-attock-notifications').on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'notifications' }, (payload) => setNotifications((current) => [payload.new as AppNotification, ...current].slice(0, 40))).subscribe()
    return () => { active = false; if (channel) void supabase!.removeChannel(channel) }
  }, [])
  const markRead = async (id: string) => { if (!supabase) return; await supabase.rpc('mark_notification_read', { p_notification_id: id }); setNotifications((current) => current.map((item) => item.id === id ? { ...item, read_at: item.read_at ?? new Date().toISOString() } : item)) }
  return { notifications, unreadCount: notifications.filter((item) => !item.read_at).length, loading, markRead }
}
