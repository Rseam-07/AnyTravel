import { useEffect, useMemo, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import { Compass, LocateFixed, Moon, Sun } from "lucide-react";
import "maplibre-gl/dist/maplibre-gl.css";
import { useApp } from "../store";
import type { Coord } from "../types";
import { meterText } from "../types";

const LIGHT_STYLE = "https://tiles.openfreemap.org/styles/liberty";
const DARK_STYLE = "https://tiles.openfreemap.org/styles/dark";
const ROUTE_SOURCE = "anytravel-current-route";
const ROUTE_HALO = "anytravel-current-route-halo";
const ROUTE_LINE = "anytravel-current-route-line";

export type MapSection = "plan" | "stay" | "transport";

const DAY_COLORS = ["#126E66", "#E87424", "#6157B8", "#B34B68", "#2777A8", "#7B6C35"];

interface MarkerSpec {
  kind: "destination" | "place" | "accommodation" | "station";
  coordinate: Coord;
  label: string;
  id: string;
  selected: boolean;
  number?: number;
  color?: string;
}

function appendUtilityIcon(container: HTMLElement, kind: "accommodation" | "station") {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("aria-hidden", "true");
  svg.setAttribute("fill", "none");
  svg.setAttribute("stroke", "currentColor");
  svg.setAttribute("stroke-width", "2");
  svg.setAttribute("stroke-linecap", "round");
  svg.setAttribute("stroke-linejoin", "round");
  const paths = kind === "accommodation"
    ? ["M2 4v16", "M2 8h18a2 2 0 0 1 2 2v10", "M2 17h20", "M6 8V6a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v2"]
    : ["M4 15.5V6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v9.5a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2Z", "M8 21l2-3.5", "M16 21l-2-3.5", "M8 9h8", "M8 13h.01", "M16 13h.01"];
  for (const d of paths) {
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("d", d);
    svg.appendChild(path);
  }
  container.appendChild(svg);
}

function pinElement(marker: MarkerSpec): HTMLElement {
  const root = document.createElement("button");
  root.type = "button";
  root.className = `map-pin ${marker.kind}${marker.selected ? " selected" : ""}`;
  root.setAttribute("aria-label", marker.label);

  const bubble = document.createElement("span");
  bubble.className = "map-pin-bubble";
  if (marker.color) bubble.style.setProperty("--pin-color", marker.color);
  if (marker.number != null) {
    const number = document.createElement("span");
    number.className = "map-pin-number";
    number.textContent = String(marker.number);
    bubble.appendChild(number);
  } else if (marker.kind === "accommodation" || marker.kind === "station") {
    appendUtilityIcon(bubble, marker.kind);
  }
  root.appendChild(bubble);

  if (marker.selected || marker.kind === "destination") {
    const label = document.createElement("span");
    label.className = "map-pin-label";
    label.textContent = marker.label.slice(0, 22);
    root.appendChild(label);
  }
  return root;
}

export default function MapView({
  dark,
  onDarkChange,
  activeSection
}: {
  dark: boolean;
  onDarkChange: (value: boolean) => void;
  activeSection: MapSection;
}) {
  const { state, setFocus } = useApp();
  const containerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const markersRef = useRef<maplibregl.Marker[]>([]);
  const styleRef = useRef<string | null>(null);
  const [northUp, setNorthUp] = useState(true);
  const [mapReady, setMapReady] = useState(false);

  const selectedDay = state.plan?.days[state.selectedDay];
  const selectedPlace = state.focus?.kind === "place" ? state.focus.id : null;

  const markers = useMemo<MarkerSpec[]>(() => {
    if (activeSection === "stay") {
      const hotels = state.accommodations.flatMap((item) => item.coordinate ? [{
        kind: "accommodation" as const,
        coordinate: item.coordinate,
        label: item.name,
        id: item.id,
        selected: item.id === state.selectedAccommodationID || (state.focus?.kind === "accommodation" && state.focus.id === item.id),
        color: "#2777A8"
      }] : []);
      if (hotels.length) return hotels;
      return (state.plan?.days ?? []).flatMap((day) => {
        const anchor = day.stops[0]?.place;
        if (!anchor) return [];
        const id = `area-${anchor.id}`;
        return [{
          kind: "accommodation" as const,
          coordinate: anchor.coordinate,
          label: `${anchor.name}一带`,
          id,
          selected: state.focus?.kind === "accommodation" && state.focus.id === id,
          color: "#2777A8"
        }];
      });
    }

    if (activeSection === "transport") {
      const selectedIDs = new Set([state.selectedOutboundID, state.selectedReturnID].filter(Boolean));
      const accessPoints = state.transports.flatMap((option) => option.arrivalAccessPoint ? [{
        kind: "station" as const,
        coordinate: option.arrivalAccessPoint.coordinate,
        label: option.arrivalAccessPoint.name,
        id: option.id,
        selected: selectedIDs.has(option.id),
        color: "#6157B8"
      }] : []);
      if (accessPoints.length) return accessPoints;
      return state.draft.destinationCoord ? [{
        kind: "station" as const,
        coordinate: state.draft.destinationCoord,
        label: `${state.draft.destination}抵达范围（示意）`,
        id: "destination-arrival-area",
        selected: true,
        color: "#6157B8"
      }] : [];
    }

    if (selectedDay?.stops.length) {
      const defaultSelected = selectedPlace == null;
      return selectedDay.stops.map((stop, index) => ({
        kind: "place",
        coordinate: stop.place.coordinate,
        label: stop.place.name,
        id: stop.place.id,
        selected: stop.place.id === selectedPlace || (defaultSelected && index === 0),
        number: index + 1,
        color: DAY_COLORS[state.selectedDay % DAY_COLORS.length]
      }));
    }

    return state.draft.destinationCoord ? [{
      kind: "destination",
      coordinate: state.draft.destinationCoord,
      label: state.draft.destination,
      id: "destination",
      selected: true,
      color: DAY_COLORS[0]
    }] : [];
  }, [
    activeSection,
    selectedDay,
    selectedPlace,
    state.accommodations,
    state.draft.destination,
    state.draft.destinationCoord,
    state.selectedAccommodationID,
    state.selectedDay,
    state.selectedOutboundID,
    state.selectedReturnID,
    state.transports,
    state.focus
  ]);

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;
    const style = dark ? DARK_STYLE : LIGHT_STYLE;
    styleRef.current = style;
    const map = new maplibregl.Map({
      container: containerRef.current,
      style,
      center: state.draft.destinationCoord
        ? [state.draft.destinationCoord.lng, state.draft.destinationCoord.lat]
        : [104.2, 35.8],
      zoom: state.draft.destinationCoord ? 11.4 : 3.35,
      attributionControl: { compact: true },
      pitchWithRotate: false
    });
    map.on("load", () => setMapReady(true));
    map.on("rotate", () => setNorthUp(Math.abs(map.getBearing()) < 0.5));
    map.on("error", () => undefined);
    mapRef.current = map;
    return () => {
      map.remove();
      mapRef.current = null;
    };
    // The map is intentionally created once; later data changes are applied below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    const nextStyle = dark ? DARK_STYLE : LIGHT_STYLE;
    if (!map || styleRef.current === nextStyle) return;
    styleRef.current = nextStyle;
    setMapReady(false);
    map.setStyle(nextStyle);
    map.once("style.load", () => setMapReady(true));
    localStorage.setItem("anytravel-web:mapstyle", dark ? "dark" : "light");
  }, [dark]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !mapReady) return;
    const route = activeSection === "plan" ? selectedDay?.route ?? [] : [];
    const color = DAY_COLORS[state.selectedDay % DAY_COLORS.length];
    const feature: GeoJSON.FeatureCollection = {
      type: "FeatureCollection",
      features: route.length ? [{
        type: "Feature",
        properties: { color },
        geometry: {
          type: "LineString",
          coordinates: [
            ...route.map((segment) => [segment.from.lng, segment.from.lat] as [number, number]),
            [route.at(-1)?.to.lng ?? 0, route.at(-1)?.to.lat ?? 0]
          ]
        }
      }] : []
    };

    const source = map.getSource(ROUTE_SOURCE) as maplibregl.GeoJSONSource | undefined;
    if (source) {
      source.setData(feature);
      return;
    }

    map.addSource(ROUTE_SOURCE, { type: "geojson", data: feature });
    map.addLayer({
      id: ROUTE_HALO,
      type: "line",
      source: ROUTE_SOURCE,
      layout: { "line-cap": "round", "line-join": "round" },
      paint: { "line-color": "rgba(255,255,255,0.94)", "line-width": 10, "line-opacity": 0.96 }
    });
    map.addLayer({
      id: ROUTE_LINE,
      type: "line",
      source: ROUTE_SOURCE,
      layout: { "line-cap": "round", "line-join": "round" },
      paint: { "line-color": ["get", "color"], "line-width": 5.5, "line-opacity": 0.98 }
    });
  }, [activeSection, mapReady, selectedDay, state.selectedDay]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !mapReady) return;
    for (const marker of markersRef.current) marker.remove();
    markersRef.current = [];
    const seen = new Set<string>();
    for (const marker of markers) {
      const key = `${marker.kind}:${Math.round(marker.coordinate.lat * 1e5)}:${Math.round(marker.coordinate.lng * 1e5)}`;
      if (seen.has(key)) continue;
      seen.add(key);
      const element = pinElement(marker);
      const item = new maplibregl.Marker({ element, anchor: "bottom" })
        .setLngLat([marker.coordinate.lng, marker.coordinate.lat])
        .addTo(map);
      element.addEventListener("click", () => {
        const kind = marker.kind === "destination" ? "destination" : marker.kind;
        setFocus({ kind, id: marker.id, coordinate: marker.coordinate });
      });
      markersRef.current.push(item);
    }
  }, [mapReady, markers, setFocus]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !mapReady) return;
    const coordinates = markers.map((marker) => marker.coordinate);
    if (coordinates.length === 0 && state.draft.destinationCoord) coordinates.push(state.draft.destinationCoord);
    if (coordinates.length === 0) return;
    if (coordinates.length === 1) {
      map.easeTo({ center: [coordinates[0].lng, coordinates[0].lat], zoom: 11.4, duration: 760 });
      return;
    }
    const bounds = coordinates.reduce(
      (value, point) => value.extend([point.lng, point.lat]),
      new maplibregl.LngLatBounds([coordinates[0].lng, coordinates[0].lat], [coordinates[0].lng, coordinates[0].lat])
    );
    const mobile = window.matchMedia("(max-width: 1023px)").matches;
    map.fitBounds(bounds, {
      padding: mobile
        ? { top: 180, right: 60, bottom: Math.min(window.innerHeight * 0.47, 390), left: 60 }
        : { top: 130, right: 100, bottom: 90, left: 490 },
      maxZoom: 13.2,
      duration: 820
    });
  }, [
    activeSection,
    mapReady,
    state.draft.destinationCoord,
    state.plan?.generatedAt,
    state.selectedDay,
    state.accommodations.length,
    state.transports.length
    // Marker selection is intentionally excluded so tapping a stop can zoom to it.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  ]);

  useEffect(() => {
    const map = mapRef.current;
    const focus = state.focus;
    if (!map || !focus?.coordinate) return;
    map.easeTo({
      center: [focus.coordinate.lng, focus.coordinate.lat],
      zoom: Math.max(map.getZoom(), 12.4),
      duration: 720
    });
  }, [state.focus]);

  const locate = () => {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(
      (position) => {
        const coordinate = { lat: position.coords.latitude, lng: position.coords.longitude };
        mapRef.current?.easeTo({ center: [coordinate.lng, coordinate.lat], zoom: 13, duration: 800 });
        setFocus({ kind: "place", coordinate });
      },
      () => undefined,
      { enableHighAccuracy: true, timeout: 8000 }
    );
  };

  const rotateNorth = () => {
    mapRef.current?.easeTo({ bearing: 0, pitch: 0, duration: 620 });
    setNorthUp(true);
  };

  const selectedRouteMeters = (selectedDay?.route ?? []).reduce((sum, segment) => {
    const dLat = (segment.to.lat - segment.from.lat) * 111000;
    const dLng = (segment.to.lng - segment.from.lng) * 111000 * Math.cos((segment.from.lat * Math.PI) / 180);
    return sum + Math.hypot(dLat, dLng);
  }, 0);

  return (
    <>
      <div ref={containerRef} className="map-root" aria-label="行程地图" />
      <div className="map-controls">
        <button className="map-control" title="定位到当前位置" aria-label="定位到当前位置" onClick={locate}>
          <LocateFixed size={19} aria-hidden="true" />
        </button>
        <button
          className={`map-control${dark ? " active" : ""}`}
          title="切换地图明暗"
          aria-label={dark ? "切换到浅色地图" : "切换到深色地图"}
          onClick={() => onDarkChange(!dark)}
        >
          {dark ? <Sun size={19} aria-hidden="true" /> : <Moon size={19} aria-hidden="true" />}
        </button>
        <button className={`map-control${northUp ? "" : " active"}`} title="恢复北向" aria-label="恢复地图北向" onClick={rotateNorth}>
          <Compass size={19} aria-hidden="true" />
        </button>
      </div>
      {activeSection === "plan" && selectedRouteMeters > 0 && (
        <div className="route-distance-pill">
          <i style={{ background: DAY_COLORS[state.selectedDay % DAY_COLORS.length] }} />
          第 {state.selectedDay + 1} 天 · {meterText(selectedRouteMeters)}
        </div>
      )}
    </>
  );
}
