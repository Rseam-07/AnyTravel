import { useEffect, useMemo, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import { ExternalLink, Maximize2, Minimize2, MapPin, X } from "lucide-react";
import "maplibre-gl/dist/maplibre-gl.css";
import type { BookPlace, Handbook } from "./model";
import { DAY_COLORS, sketchLeg } from "../route-geometry";
import { handbookLegs, orderedDayPlaces } from "./routes";

export default function HandbookMap({ book, dark, onLocate }: { book: Handbook; dark: boolean; onLocate: (place: BookPlace) => void }) {
  const container = useRef<HTMLDivElement>(null), map = useRef<maplibregl.Map>(), markers = useRef<maplibregl.Marker[]>([]);
  const [ready, setReady] = useState(false), [region, setRegion] = useState("all"), [dayID, setDayID] = useState("all"), [selected, setSelected] = useState<BookPlace>(), [full, setFull] = useState(false), [error, setError] = useState("");
  const [selectedLeg, setSelectedLeg] = useState<{ title: string; note: string }>();
  const regions = [...new Set(book.places.map(p => p.region))];
  const days = useMemo(() => book.days.filter(d => dayID === "all" || d.id === dayID), [book.days, dayID]);
  const visible = useMemo(() => { const ordered = dayID === "all" ? book.places : [...new Map(days.flatMap(d => orderedDayPlaces(d, book.places)).filter((p): p is BookPlace => Boolean(p)).map(p => [p.id, p])).values()]; return ordered.filter(p => (region === "all" || p.region === region) && (dayID === "all" || days.some(d => d.items.some(i => i.placeIds.includes(p.id))))); }, [book.places, days, dayID, region]);
  const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches;
  useEffect(() => {
    if (!container.current) return;
    setReady(false);
    let m: maplibregl.Map;
    try { m = new maplibregl.Map({ container: container.current, style: `https://tiles.openfreemap.org/styles/${dark ? "dark" : "liberty"}`, center: [105, 34], zoom: 3, attributionControl: { compact: true } }); }
    catch { setError("此设备未能启动地图。下方地点与导航链接仍可使用。"); return; }
    map.current = m; m.addControl(new maplibregl.NavigationControl(), "bottom-right");
    m.on("load", () => setReady(true));
    m.on("error", () => setError("部分底图没有加载，请检查网络；仍可从地点卡片打开导航。"));
    m.on("idle", () => { if (m.areTilesLoaded()) setError(""); });
    m.on("click", "handbook-route-line", event => { const properties = event.features?.[0]?.properties; if (properties) { setSelected(undefined); setSelectedLeg({ title: properties.title, note: properties.note }); } });
    const resize = new ResizeObserver(() => m.resize()); resize.observe(container.current);
    return () => { resize.disconnect(); markers.current.forEach(p => p.remove()); markers.current = []; m.remove(); map.current = undefined; setReady(false); };
  }, [dark]);
  useEffect(() => {
    const m = map.current; if (!m || !ready || !m.isStyleLoaded()) return;
    markers.current.forEach(p => p.remove()); markers.current = [];
    const features: GeoJSON.Feature<GeoJSON.LineString>[] = [];
    days.forEach(d => {
      const dayIndex = book.days.indexOf(d);
      for (const { from, to, order } of handbookLegs(d, visible)) {
        const transfer = d.items.find(item => item.placeIds.includes(from.id) && item.placeIds.includes(to.id));
        features.push({ type: "Feature", properties: { color: DAY_COLORS[dayIndex % DAY_COLORS.length], title: `${order}. ${from.name} → ${to.name}`, note: [d.title, transfer?.title, transfer?.time, transfer?.note, "虚线为顺序示意，实际班次与道路请另行核对"].filter(Boolean).join(" · ") }, geometry: { type: "LineString", coordinates: sketchLeg(from.coordinate!, to.coordinate!) } });
      }
    });
    visible.filter(p => p.coordinate).forEach((p, i) => {
      const el = document.createElement("button"); el.className = "hb-pin"; el.textContent = String(i + 1); el.setAttribute("aria-label", `${i + 1}. ${p.name}`); el.onclick = () => { setSelectedLeg(undefined); setSelected(p); m.easeTo({ center: [p.coordinate!.lng, p.coordinate!.lat], duration: reduced() ? 0 : 300 }); };
      markers.current.push(new maplibregl.Marker({ element: el }).setLngLat([p.coordinate!.lng, p.coordinate!.lat]).addTo(m));
    });
    const data: GeoJSON.FeatureCollection<GeoJSON.LineString> = { type: "FeatureCollection", features };
    const source = m.getSource("handbook-route") as maplibregl.GeoJSONSource | undefined;
    if (source) source.setData(data); else {
      m.addSource("handbook-route", { type: "geojson", data });
      m.addLayer({ id: "handbook-route-halo", type: "line", source: "handbook-route", layout: { "line-cap": "round", "line-join": "round" }, paint: { "line-color": "#fff", "line-width": 7, "line-opacity": 0.8 } });
      m.addLayer({ id: "handbook-route-line", type: "line", source: "handbook-route", layout: { "line-cap": "round", "line-join": "round" }, paint: { "line-color": ["get", "color"], "line-width": 3.5, "line-dasharray": [2, 2] } });
      m.addLayer({ id: "handbook-route-arrows", type: "symbol", source: "handbook-route", layout: { "symbol-placement": "line", "symbol-spacing": 100, "text-field": ">", "text-size": 15, "text-keep-upright": false }, paint: { "text-color": ["get", "color"], "text-halo-color": "#fff", "text-halo-width": 2 } });
    }
    const coords = visible.flatMap(p => p.coordinate ? [[p.coordinate.lng, p.coordinate.lat] as [number, number]] : []);
    if (coords.length) { const bounds = new maplibregl.LngLatBounds(coords[0], coords[0]); coords.forEach(c => bounds.extend(c)); m.fitBounds(bounds, { padding: 70, maxZoom: 14, duration: reduced() ? 0 : 450 }); }
  }, [visible, days, ready, book.days]);
  useEffect(() => { if (!full) return; const escape = (e: KeyboardEvent) => { if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); setFull(false); } }; window.addEventListener("keydown", escape, true); return () => window.removeEventListener("keydown", escape, true); }, [full]);
  return <section className={`hb-map-section${full ? " hb-map-full" : ""}`} aria-label="手册路线地图">
    <div className="hb-row hb-map-controls"><label>地区<select value={region} onChange={e => { setRegion(e.target.value); setSelected(undefined); }}><option value="all">全部地区</option>{regions.map(r => <option key={r}>{r}</option>)}</select></label><label>路线<select value={dayID} onChange={e => { setDayID(e.target.value); setSelected(undefined); }}><option value="all">全程总览</option>{book.days.map((d, i) => <option value={d.id} key={d.id}>第 {i + 1} 天 · {d.title}</option>)}</select></label><button className="hb-icon" onClick={() => setFull(!full)} aria-label={full ? "退出全屏地图" : "全屏地图"}>{full ? <Minimize2 size={20}/> : <Maximize2 size={20}/>}</button></div>
    <div className="hb-map-canvas"><div ref={container} className="hb-map-root" />{error && <p className="hb-map-notice" role="status">{error}</p>}{selected && <article className="hb-map-popup"><button className="hb-icon" onClick={() => setSelected(undefined)} aria-label="关闭地点"><X size={18}/></button><strong>{selected.name}</strong><p>{selected.address || selected.region}</p><a href={selected.url || `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(selected.coordinate ? `${selected.coordinate.lat},${selected.coordinate.lng}` : selected.name)}`} target="_blank" rel="noopener noreferrer">外部导航 <ExternalLink size={14}/></a><button onClick={() => onLocate(selected)}>回到主地图 <MapPin size={14}/></button></article>}</div>
    {selectedLeg && <article className="hb-card"><div className="hb-section-heading"><h3>{selectedLeg.title}</h3><button className="hb-icon" onClick={() => setSelectedLeg(undefined)} aria-label="关闭交通详情"><X size={18}/></button></div><p>{selectedLeg.note}</p></article>}
    <div className="hb-actions hb-map-legend">{days.map(d => <span key={d.id} className="hb-tag"><i style={{ width: 18, borderTop: `3px dashed ${DAY_COLORS[book.days.indexOf(d) % DAY_COLORS.length]}` }}/>{book.days.indexOf(d) + 1} · {d.date || d.title}</span>)}</div>
    <p className="hb-muted hb-map-legend">虚线仅表示游览顺序，不是步行或驾车导航；点击连线可查看这段安排。地点缺少经纬度时仅显示在下方列表。</p>
    {!full && <div className="hb-grid">{visible.map((p, i) => <button className="hb-place" key={p.id} onClick={() => { setSelected(p); if (p.coordinate) map.current?.easeTo({ center: [p.coordinate.lng, p.coordinate.lat], zoom: 14, duration: reduced() ? 0 : 350 }); }}><span className="hb-index">{i + 1}</span><span><strong>{p.name}</strong><small>{p.address || p.region}{!p.coordinate && " · 位置待补充"}</small></span></button>)}</div>}
    {!book.places.length && <p className="hb-empty">先在主地图规划行程，或导入含有地点信息的旅行资料。</p>}
  </section>;
}
