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
    address: place.tags?.slice(0, 3).join(" · "),
    coordinate: place.coord,
    interest,
    source: "AnyTravel 目的地资料（非实时）",
    opening: place.openingHoursWeek,
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

/**
 * Knowledge-aware heat: a place that appears in the guide knowledge base with a
 * "必去" tier is a heavyweight sight; "推荐" is a solid filler; "顺路" is a
 * nice-to-have. Falls back to the OSM/category heuristics otherwise.
 */
export function knowledgeHeat(place: { name: string }, baseScore: number): number {
  const name = place.name;
  let bonus = 0;
  for (const city of knowledgeCities) {
    for (const famous of city.places) {
      if (name === famous.name || (famous.name.length >= 5 && name.includes(famous.name))) {
        bonus += tierBonus(famous.tier);
        if (famous.best) {
          // No selection change here; the caller may use best for slot hints.
        }
        return baseScore + bonus;
      }
    }
  }
  return baseScore;
}

function tierBonus(tier: string): number {
  switch (tier) {
    case "必去":
      return 120;
    case "推荐":
      return 45;
    case "顺路":
      return 8;
    default:
      return 0;
  }
}

export function famousBestTime(place: { name: string }): FamousPlace["best"] | null {
  for (const city of knowledgeCities) {
    for (const famous of city.places) {
      if (nameMatches(famous, place.name)) return famous.best ?? null;
    }
  }
  return null;
}

export function famousStayMinutes(place: { name: string }, fallback: number): number {
  for (const city of knowledgeCities) {
    for (const famous of city.places) {
      if (nameMatches(famous, place.name) && famous.stayMinutes) return famous.stayMinutes;
    }
  }
  return fallback;
}

function nameMatches(famous: FamousPlace, name: string): boolean {
  return name === famous.name || (famous.name.length >= 5 && name.includes(famous.name));
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
