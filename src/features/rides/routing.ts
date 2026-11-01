export type RoutePreview = { distanceKm: number; durationMinutes: number; geometry: [number, number][] }

/** Public OSRM demo server is for development/testing only. Replace behind this wrapper before production traffic. */
export async function getRoutePreview(from: { latitude: number; longitude: number }, to: { latitude: number; longitude: number }): Promise<RoutePreview | null> {
  const url = `https://router.project-osrm.org/route/v1/driving/${from.longitude},${from.latitude};${to.longitude},${to.latitude}?overview=full&geometries=geojson`
  try {
    const response = await fetch(url)
    if (!response.ok) return null
    const data = await response.json() as { routes?: { distance: number; duration: number; geometry?: { coordinates: [number, number][] } }[] }
    const route = data.routes?.[0]
    if (!route) return null
    return { distanceKm: Math.round(route.distance / 100) / 10, durationMinutes: Math.max(1, Math.round(route.duration / 60)), geometry: (route.geometry?.coordinates ?? []).map(([lng, lat]) => [lat, lng]) }
  } catch { return null }
}
