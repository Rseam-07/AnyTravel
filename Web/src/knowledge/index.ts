// Recovered destination knowledge from the unfinished DeepSeek hand-off.
// The checked-in snapshot is deliberately treated as planning context rather
// than live truth: ticket notes and opening rules must still be rechecked.

import citiesDocument from "./cities.json";
import rulesDocument from "./rules.json";
import type { Interest, TravelPlace } from "../types";
import { CATEGORY_TO_INTEREST, type FamousPlace, type GuideCity, type GuideKnowledge, type GuideRule } from "./types";

const cityPayload = citiesDocument as unknown as GuideKnowledge & {
  cityCount?: number;
  cities?: GuideCity[];
};
const rulePayload = rulesDocument as unknown as GuideKnowledge & {
  ruleCount?: number;
  rules?: GuideRule[];
};
const knowledgeCities = cityPayload.cities ?? [];
const knowledgeRules = rulePayload.rules ?? [];

export const KNOWLEDGE_STATS = {
  cities: cityPayload.cityCount ?? knowledgeCities.length,
  sources: cityPayload.sourceCount ?? 0,
  rules: rulePayload.ruleCount ?? knowledgeRules.length
};

export async function loadKnowledge(): Promise<{ cities: GuideCity[]; rules: GuideRule[] }> {
  return { cities: knowledgeCities, rules: knowledgeRules };
}

export function knowledgeCitiesRef(): GuideCity[] {
  return knowledgeCities;
}

export function knowledgeRulesRef(): GuideRule[] {
  return knowledgeRules;
}

/** Find the knowledge entry for a destination city (name normalization). */
export function lookupCity(destination: string): GuideCity | null {
  const normalized = normalizeDestination(destination);
  if (!normalized) return null;
  return (
    knowledgeCities.find(
      (city) => normalizeDestination(city.city) === normalized
    ) ?? null
  );
}

export function lookupCityCoordinate(destination: string): { lat: number; lng: number } | null {
  const coordinate = lookupCity(destination)?.coord;
  return coordinate && validCoordinate(coordinate) ? coordinate : null;
}

export function knowledgePlaces(destination: string, preferred: Interest[] = []): TravelPlace[] {
  const city = lookupCity(destination);
  if (!city) return [];

  const ranked = city.places
    .filter((place): place is FamousPlace & { coord: { lat: number; lng: number } } =>
      Boolean(place.coord && validCoordinate(place.coord))
    )
    .map((place, index) => {
      const interest = normalizeInterest(place.category);
      const preferenceRank = preferred.includes(interest) ? 0 : 1;
      const tierRank = place.tier === "必去" ? 0 : place.tier === "推荐" ? 1 : 2;
      return { place, interest, order: preferenceRank * 100 + tierRank * 10 + index / 100 };
    })
    .sort((a, b) => a.order - b.order);

  return ranked.map(({ place, interest }) => ({
    id: `knowledge-${normalizeDestination(city.city)}-${place.name}`,
    name: place.name,
    // Tags describe research provenance/preferences, not a street address.
    coordinate: place.coord,
    interest,
    source: "AnyTravel 目的地资料（非实时）",
    opening: place.openingHoursWeek,
    suggestedVisitMinutes: place.stayMinutes,
    bestTime: place.best,
    planningPriority: place.tier === "必去" ? "primary" : "supplemental",
    ticket: place.ticket
      ? {
          provider: "攻略资料快照",
          amountCNY: null,
          note: `${place.ticket}；价格、预约与开放信息请在出发前复核。`
        }
      : null
  }));
}

/** Match facts geographically: same-name attractions in different cities are unrelated. */
function matchedPlace(place: { name: string; coordinate?: { lat: number; lng: number } }): FamousPlace | undefined {
  return knowledgeCities.flatMap(city => city.places).find(famous => {
    const matches = place.name === famous.name || (famous.name.length >= 2 && Boolean(place.coordinate && famous.coord) && place.name.includes(famous.name));
    if (!matches) return false;
    if (!place.coordinate || !famous.coord) return place.name === famous.name;
    return Math.abs(place.coordinate.lat - famous.coord.lat) < 0.08 && Math.abs(place.coordinate.lng - famous.coord.lng) < 0.08;
  });
}

export function knowledgeHeat(place: { name: string; coordinate?: { lat: number; lng: number } }, baseScore: number): number {
  const tier = matchedPlace(place)?.tier;
  return baseScore + (tier === "必去" ? 10 : tier === "推荐" ? 5 : 0);
}

export function famousBestTime(place: TravelPlace): FamousPlace["best"] | null {
  return place.bestTime ?? matchedPlace(place)?.best ?? null;
}

export function famousStayMinutes(place: TravelPlace, fallback: number): number {
  return place.suggestedVisitMinutes ?? matchedPlace(place)?.stayMinutes ?? fallback;
}

export function enrichPlace(place: TravelPlace): TravelPlace {
  const facts = matchedPlace(place);
  return facts ? {
    ...place,
    opening: place.opening ?? facts.openingHoursWeek,
    suggestedVisitMinutes: place.suggestedVisitMinutes ?? facts.stayMinutes,
    bestTime: place.bestTime ?? facts.best
  } : place;
}

function normalizeDestination(value: string): string {
  return value
    .trim()
    .replace(/\s+/g, "")
    .replace(/(市|省|自治区|特别行政区)$/, "");
}

function normalizeInterest(category: string): Interest {
  const mapped = CATEGORY_TO_INTEREST[category];
  return mapped === "culture" || mapped === "food" || mapped === "nature" || mapped === "family" || mapped === "night"
    ? mapped
    : "gardens";
}

function validCoordinate(coordinate: { lat: number; lng: number }): boolean {
  return Number.isFinite(coordinate.lat) && Number.isFinite(coordinate.lng) && Math.abs(coordinate.lat) <= 85 && Math.abs(coordinate.lng) <= 180;
}
