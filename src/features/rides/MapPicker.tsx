import { useEffect, useRef, useState } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { LocateFixed, MapPin, Search } from 'lucide-react'
import { Button, Notice, TextInput } from '../../components/ui'
import { searchRouteLocations } from './api'
import { geocodeExplicitly, geocoderPolicyNote } from './geocoding'
import type { Point, RouteLocation } from './types'

const defaultCenter: [number, number] = [33.67, 72.68]
export function MapPicker({ value, onChange, label, allowCurrentLocation = true }: { value: Point | null; onChange: (point: Point) => void; label: string; allowCurrentLocation?: boolean }) {
  const mapRef = useRef<HTMLDivElement | null>(null)
  const instanceRef = useRef<L.Map | null>(null)
  const markerRef = useRef<L.Marker | null>(null)
  const onChangeRef = useRef(onChange)
  const labelRef = useRef(label)
  const [query, setQuery] = useState('')
  const [suggestions, setSuggestions] = useState<RouteLocation[]>([])
  const [locationMessage, setLocationMessage] = useState('')
  const [searching, setSearching] = useState(false)
  useEffect(() => { onChangeRef.current = onChange; labelRef.current = label }, [label, onChange])
  useEffect(() => {
    if (!mapRef.current || instanceRef.current) return
    const map = L.map(mapRef.current, { zoomControl: false }).setView(value ? [value.latitude, value.longitude] : defaultCenter, value ? 12 : 8)
    L.control.zoom({ position: 'bottomright' }).addTo(map)
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { attribution: '&copy; OpenStreetMap contributors', maxZoom: 18 }).addTo(map)
    map.on('click', (event: L.LeafletMouseEvent) => onChangeRef.current({ latitude: Number(event.latlng.lat.toFixed(6)), longitude: Number(event.latlng.lng.toFixed(6)), label: labelRef.current }))
    instanceRef.current = map
    return () => { map.remove(); instanceRef.current = null }
  }, [])
  useEffect(() => { const map = instanceRef.current; if (!map || !value) return; markerRef.current?.remove(); markerRef.current = L.marker([value.latitude, value.longitude]).addTo(map).bindTooltip(value.label ?? label, { permanent: false }); map.setView([value.latitude, value.longitude], Math.max(map.getZoom(), 10)) }, [label, value])
  useEffect(() => {
    const trimmed = query.trim()
    if (trimmed.length < 2) { setSuggestions([]); return }
    const timer = window.setTimeout(() => { setSearching(true); void searchRouteLocations(trimmed).then(setSuggestions).catch(() => setSuggestions([])).finally(() => setSearching(false)) }, 220)
    return () => window.clearTimeout(timer)
  }, [query])
  const choose = (place: RouteLocation) => { setQuery(place.name); setSuggestions([]); onChange({ latitude: Number(place.latitude), longitude: Number(place.longitude), label: place.name }) }
  const widerSearch = async () => { setLocationMessage(''); try { const point = await geocodeExplicitly(query); if (point) { onChange(point); setSuggestions([]) } else setLocationMessage('No wider-area result was found.') } catch (error) { setLocationMessage(error instanceof Error ? error.message : 'The optional geocoder failed.') } }
  const useCurrent = () => { setLocationMessage(''); if (!navigator.geolocation) { setLocationMessage('This browser does not provide geolocation. Choose a point manually.'); return } navigator.geolocation.getCurrentPosition((position) => onChange({ latitude: Number(position.coords.latitude.toFixed(6)), longitude: Number(position.coords.longitude.toFixed(6)), label }), (error) => setLocationMessage(error.code === error.PERMISSION_DENIED ? 'Location permission was denied. Choose a point manually.' : 'We could not read your current location. You can choose a point manually.'), { enableHighAccuracy: true, timeout: 8000 }) }
  return <div><div className="mb-2 flex items-center justify-between gap-3"><span className="text-sm font-bold text-navy-900">{label}</span>{allowCurrentLocation && <Button type="button" variant="ghost" className="px-2 py-1.5 text-xs" onClick={useCurrent}><LocateFixed size={14} /> Use current location</Button>}</div><div className="relative"><TextInput label="Search nearby place" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Saddar, Attock City, Hasan Abdal…" /><Search className="pointer-events-none absolute right-3 top-9 text-cyan-600" size={16} />{(searching || suggestions.length > 0 || query.trim().length > 2) && <div className="absolute z-20 mt-1 w-full overflow-hidden rounded-xl border border-navy-900/10 bg-white shadow-soft">{searching && <p className="px-4 py-3 text-xs text-muted">Searching seeded places…</p>}{suggestions.map((place) => <button key={place.id} type="button" className="block w-full px-4 py-3 text-left text-sm hover:bg-cyan-50" onClick={() => choose(place)}>{place.name}<span className="ml-2 text-xs text-muted">{place.latitude.toFixed(4)}, {place.longitude.toFixed(4)}</span></button>)}{!searching && suggestions.length === 0 && query.trim().length > 2 && <><p className="px-4 py-3 text-xs text-muted">No seeded place matched.</p><button type="button" className="w-full border-t px-4 py-3 text-left text-xs font-semibold text-cyan-700" onClick={() => void widerSearch()}>Search wider area (development fallback)</button></>}</div>}</div><div ref={mapRef} className="mt-3 h-48 overflow-hidden rounded-xl border border-navy-900/15 bg-sand" />{value ? <p className="mt-2 flex items-center gap-1.5 text-xs text-muted"><MapPin size={13} className="text-cyan-600" /> {value.label ?? label} · {value.latitude.toFixed(4)}, {value.longitude.toFixed(4)}</p> : <p className="mt-2 text-xs text-muted">Choose a seeded place, click the map, or use current location.</p>}{locationMessage && <div className="mt-2"><Notice type="error">{locationMessage}</Notice></div>}<p className="mt-2 text-[11px] leading-4 text-muted">{geocoderPolicyNote}</p></div>
}
