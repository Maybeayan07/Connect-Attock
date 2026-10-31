import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import type { Session, User } from '@supabase/supabase-js'
import { isSupabaseConfigured, supabase, type Profile } from '../lib/supabase'

type AuthContextValue = { session: Session | null; user: User | null; profile: Profile | null; loading: boolean; configured: boolean; refreshProfile: () => Promise<void> }
const AuthContext = createContext<AuthContextValue | undefined>(undefined)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [loading, setLoading] = useState(true)

  const refreshProfile = async () => {
    if (!supabase || !session?.user) return
    const { data } = await supabase.from('profiles').select('*').eq('id', session.user.id).maybeSingle()
    setProfile((data as Profile | null) ?? null)
  }

  useEffect(() => {
    if (!supabase) { setLoading(false); return }
    supabase.auth.getSession().then(({ data }) => { setSession(data.session); setLoading(false) })
    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => { setSession(nextSession); setLoading(false) })
    return () => listener.subscription.unsubscribe()
  }, [])

  useEffect(() => { void refreshProfile() }, [session?.user?.id])
  const value = useMemo(() => ({ session, user: session?.user ?? null, profile, loading, configured: isSupabaseConfigured, refreshProfile }), [session, profile, loading])
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() { const context = useContext(AuthContext); if (!context) throw new Error('useAuth must be used within AuthProvider'); return context }
