import { useEffect, useMemo, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { useApp } from "../store";
import type { Coord } from "../types";
import { meterText } from "../types";

const LIGHT_STYLE = "https://tiles.openfreemap.org/styles/liberty";
const DARK_STYLE = "https://tiles.openfreemap.org/styles/dark";

function pinElement(kind: string, label: string, selected: boolean): HTMLElement {
  const el = document.createElement("div");
  el.style.display = "flex";
  el.style.flexDirection = "column";
  el.style.alignItems = "center";
  el.style.pointerEvents = "auto";
  el.innerHTML = `
    <div class="pin-dot ${kind}${selected ? " selected" : ""}"></div>
    <div class="pin-label">${label.replace(/</g, "&lt;").slice(0, 22)}</div>
  `;
  return el;
}

export default function MapView({ dark, onDarkChange }: { dark: boolean; onDarkChange: (v: boolean) => void }) {
  const { state, setFocus } = useApp();
  const containerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const markersRef = useRef<maplibregl.Marker[]>([]);
  const [northUp, setNorthUp] = useState(false);
  const [mapReady, setMapReady] = useState(false);

  const markers = useMemo(() => {
    const out: { kind: string; coordinate: Coord; label: string; id: string }[] = [];
    const draft = state.draft;
    if (draft.destinationCoord) {
      out.push({ kind: "start", coordinate: draft.destinationCoord, label: draft.destination, id: "destination" });
    }
    for (const day of state.plan?.days ?? []) {
      for (const stop of day.stops) {
        const kind = stop.place.interest === "food" ? "food" : stop.place.interest === "night" ? "night" : "place";
        out.push({
          kind,
          coordinate: stop.place.coordinate,
          label: stop.place.name,
          id: `place-${stop.place.id}`
        });
      }
    }
    const selectedStopId = state.focus?.kind === "place" ? state.focus.id : undefined;
    for (const item of state.accommodations) {
      if (item.coordinate) {
        out.push({ kind: "accommodation", coordinate: item.coordinate, label: item.name, id: `stay-${item.id}` });
      }
    }
    for (const option of state.transports) {
      const point = option.arrivalAccessPoint;
      if (point) {
        out.push({ kind: "station", coordinate: point.coordinate, label: point.name, id: `station-${option.id}` });
      }
    }
    return out.map((m) => ({ ...m, selected: m.id === selectedStopId || (m.id === `stay-${state.selectedAccommodationID}`) }));
  }, [state.draft, state.plan, state.accommodations, state.transports, state.focus, state.selectedAccommodationID]);

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;
    const map = new maplibregl.Map({
      container: containerRef.current,
      style: dark ? DARK_STYLE : LIGHT_STYLE,
      center: state.draft.destinationCoord ? [state.draft.destinationCoord.lng, state.draft.destinationCoord.lat] : [120.5853, 31.2989],
      zoom: state.draft.destinationCoord ? 11.6 : 11,
      attributionControl: { compact: true }
    });
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "bottom-right");
    map.on("load", () => setMapReady(true));
    map.on("error", () => undefined); // tolerate tile/style hiccups
    mapRef.current = map;
    return () => {
      map.remove();
      mapRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Style switch.
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    setMapReady(false);
    map.setStyle(dark ? DARK_STYLE : LIGHT_STYLE);
    map.once("style.load", () => setMapReady(true));
    localStorage.setItem("anytravel-web:mapstyle", dark ? "dark" : "light");
  }, [dark]);

  // Route layers: one source fed with current plan day routes.
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !mapReady) return;
    const sourceId = "anytravel-day-routes";
    const feature: GeoJSON.FeatureCollection = {
      type: "FeatureCollection",
      features: (state.plan?.days ?? []).map((day, index) => ({
        type: "Feature",
        properties: { day: index, overCapacity: day.overCapacity ? 1 : 0 },
        geometry: {
          type: "LineString",
          coordinates: [...day.route.map((r) => [r.from.lng, r.from.lat] as [number, number]), [
            day.route[day.route.length - 1]?.to.lng ?? 0,
            day.route[day.route.length - 1]?.to.lat ?? 0
          ] as [number, number]]
        }
      }))
    };
    if (!map.getSource(sourceId)) {
      map.addSource(sourceId, { type: "geojson", data: feature });
      map.addLayer({
        id: sourceId,
        type: "line",
        source: sourceId,
        layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-color": ["case", ["==", ["get", "overCapacity"], 1], "#d97706", "#0f766e"],
          "line-width": ["case", ["==", ["get", "day"], state.selectedDay], 5, 2.4],
          "line-opacity": ["case", ["==", ["get", "day"], state.selectedDay], 0.95, 0.42]
        }
      });
    } else {
      (map.getSource(sourceId) as maplibregl.GeoJSONSource).setData(feature);
    }
    return () => {
      if (map.getLayer(sourceId)) map.removeLayer(sourceId);
      if (map.getSource(sourceId)) map.removeSource(sourceId);
    };
  }, [state.plan, state.selectedDay]);

  // Markers.
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !mapReady) return;
    for (const marker of markersRef.current) marker.remove();
    markersRef.current = [];
    const seen = new Set<string>();
    for (const marker of markers) {
      const key = `${marker.kind}:${Math.round(marker.coordinate.lat * 1e4)}:${Math.round(marker.coordinate.lng * 1e4)}`;
      if (seen.has(key)) continue;
      seen.add(key);
      const element = pinElement(marker.kind, marker.label, marker.selected);
      const item = new maplibregl.Marker({ element, anchor: "bottom" })
        .setLngLat([marker.coordinate.lng, marker.coordinate.lat])
        .addTo(map);
      element.addEventListener("click", () => {
        setFocus({ kind: marker.kind === "accommodation" ? "accommodation" : "place", id: marker.id, coordinate: marker.coordinate });
      });
      markersRef.current.push(item);
    }
  }, [markers, setFocus, mapReady]);

  // Camera follows focus.
  useEffect(() => {
    const map = mapRef.current;
    const focus = state.focus;
    if (!map || !focus?.coordinate) return;
    map.easeTo({
      center: [focus.coordinate.lng, focus.coordinate.lat],
      zoom: Math.max(map.getZoom() ?? 11, 12),
      duration: 900
    });
  }, [state.focus]);

  // Locate.
  const locate = () => {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(
      (position) => {
        const map = mapRef.current;
        if (!map) return;
        map.easeTo({ center: [position.coords.longitude, position.coords.latitude], zoom: 13, duration: 900 });
        setFocus({ kind: "place", coordinate: { lat: position.coords.latitude, lng: position.coords.longitude } });
      },
      () => undefined,
      { enableHighAccuracy: true, timeout: 8000 }
    );
  };

  const rotate = () => {
    const map = mapRef.current;
    if (!map) return;
    if (!northUp) {
      map.easeTo({ bearing: 0, pitch: 0, duration: 700 });
      setNorthUp(true);
    } else {
      setNorthUp(false);
    }
  };

  return (
    <>
      <div ref={containerRef} className="map-root" />
      <div className="map-title">
        <div className="brand-mark">远</div>
        <div className="brand-text">AnyTravel · 旅行是一场诗意的迁徙</div>
      </div>
      <div className="map-controls">
        <button className="map-control" title="定位到当前位置" onClick={locate}>📍</button>
        <button
          className={`map-control ${dark ? "active" : ""}`}
          title="切换地图样式"
          onClick={() => onDarkChange(!dark)}
        >
          {dark ? "☀️" : "🌙"}
        </button>
        <button className={`map-control ${northUp ? "active" : ""}`} title="方向" onClick={rotate}>🧭</button>
      </div>
      <div className="map-legend">
        <span><i className="legend-dot" style={{ background: "#0f766e" }} />出发地/路线</span>
        <span><i className="legend-dot" style={{ background: "#d97706" }} />景点</span>
        <span><i className="legend-dot" style={{ background: "#2563eb" }} />住宿</span>
        <span><i className="legend-dot" style={{ background: "#7c3aed" }} />枢纽</span>
      </div>
      {state.plan && <div className="map-legend" style={{ left: "auto", right: 76, bottom: 18 }}>
        <span style={{ color: "var(--secondary-ink)" }}>{meterText(routeTotalMeters(state.plan))} 路线 · 直连示意</span>
      </div>}
    </>
  );
}

function routeTotalMeters(plan: NonNullable<ReturnType<typeof useApp>["state"]["plan"]>): number {
  let meters = 0;
  for (const day of plan.days) {
    for (const segment of day.route) {
      const dLat = (segment.to.lat - segment.from.lat) * 111000;
      const dLng = (segment.to.lng - segment.from.lng) * 111000 * Math.cos((segment.from.lat * Math.PI) / 180);
      meters += Math.hypot(dLat, dLng);
    }
  }
  return meters;
}
