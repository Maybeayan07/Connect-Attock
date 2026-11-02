declare const Deno: {
  env: { get(name: string): string | undefined }
  serve(handler: (request: Request) => Response | Promise<Response>): void
}

declare module 'https://esm.sh/@supabase/supabase-js@2' {
  export type User = { id: string; email?: string }
  export type SupabaseClient = any
  export function createClient(...args: any[]): any
}
