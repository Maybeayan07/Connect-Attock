import { useEffect, useRef, useState } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { LocateFixed, MapPin } from 'lucide-react'
import { Button, Notice } from '../../components/ui'
import type { Point } from './types'

const defaultCenter: [number, number] = [33.67, 72.68]
export function MapPicker({ value, onChange, label, allowCurrentLocation = true }: { value: Point | null; onChange: (point: Point) => void; label: string; allowCurrentLocation?: boolean }) {
  const mapRef = useRef<HTMLDivElement | null>(null)
  const instanceRef = useRef<L.Map | null>(null)
  const markerRef = useRef<L.Marker | null>(null)
  const [locationMessage, setLocationMessage] = useState('')
  useEffect(() => {
    if (!mapRef.current || instanceRef.current) return
    const map = L.map(mapRef.current, { zoomControl: false }).setView(value ? [value.latitude, value.longitude] : defaultCenter, value ? 12 : 8)
    L.control.zoom({ position: 'bottomright' }).addTo(map)
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { attribution: '&copy; OpenStreetMap contributors', maxZoom: 18 }).addTo(map)
    map.on('click', (event: L.LeafletMouseEvent) => onChange({ latitude: Number(event.latlng.lat.toFixed(6)), longitude: Number(event.latlng.lng.toFixed(6)), label }))
    instanceRef.current = map
    return () => { map.remove(); instanceRef.current = null }
  }, [label, onChange, value])
  useEffect(() => { const map = instanceRef.current; if (!map || !value) return; markerRef.current?.remove(); markerRef.current = L.marker([value.latitude, value.longitude]).addTo(map).bindTooltip(label, { permanent: false }); map.setView([value.latitude, value.longitude], Math.max(map.getZoom(), 10)) }, [label, value])
  const useCurrent = () => { setLocationMessage(''); if (!navigator.geolocation) { setLocationMessage('This browser does not provide geolocation. You can still choose a point manually on the map.'); return } navigator.geolocation.getCurrentPosition((position) => onChange({ latitude: Number(position.coords.latitude.toFixed(6)), longitude: Number(position.coords.longitude.toFixed(6)), label }), (error) => setLocationMessage(error.code === error.PERMISSION_DENIED ? 'Location permission was denied. Choose a point manually; current-location actions remain unavailable.' : 'We could not read your current location. You can choose a point manually.'), { enableHighAccuracy: true, timeout: 8000 }) }
  return <div><div className="mb-2 flex items-center justify-between gap-3"><span className="text-sm font-bold text-navy-900">{label}</span>{allowCurrentLocation && <Button type="button" variant="ghost" className="px-2 py-1.5 text-xs" onClick={useCurrent}><LocateFixed size={14} /> Use current location</Button>}</div><div ref={mapRef} className="h-48 overflow-hidden rounded-xl border border-navy-900/15 bg-sand" />{value ? <p className="mt-2 flex items-center gap-1.5 text-xs text-muted"><MapPin size={13} className="text-cyan-600" /> {value.latitude.toFixed(4)}, {value.longitude.toFixed(4)}</p> : <p className="mt-2 text-xs text-muted">Click the map to choose a point. Desktop location hardware may be inaccurate.</p>}{locationMessage && <div className="mt-2"><Notice type="error">{locationMessage}</Notice></div>}</div>
}
