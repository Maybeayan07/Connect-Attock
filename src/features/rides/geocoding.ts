import type { Point, RouteLocation } from './types'

export type Geocoder = { search(query: string): Promise<RouteLocation[]> }

/** Seeded route locations power autocomplete. The optional fallback is explicit-only,
 * never used for as-you-type suggestions, and should point to an approved provider. */
export async function geocodeExplicitly(query: string): Promise<Point | null> {
  const endpoint = import.meta.env.VITE_GEOCODER_URL as string | undefined
  if (!endpoint || !query.trim()) return null
  const url = new URL(endpoint)
  url.searchParams.set('q', query.trim())
  const response = await fetch(url)
  if (!response.ok) throw new Error('The optional geocoder is unavailable.')
  const results = await response.json() as Array<{ lat?: string; lon?: string; display_name?: string }>
  const first = results[0]
  if (!first?.lat || !first.lon) return null
  return { latitude: Number(first.lat), longitude: Number(first.lon), label: first.display_name ?? query.trim() }
}

export const geocoderPolicyNote = 'Autocomplete uses the seeded Connect Attock route catalog. Optional geocoding is explicit-only through VITE_GEOCODER_URL; do not point it at a public Nominatim server for as-you-type requests. Any public demo geocoder is for development/testing only and must follow its provider policy.'
