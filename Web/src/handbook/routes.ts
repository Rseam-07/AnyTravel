import type { BookDay, BookPlace } from "./model";

// Preserve returns (A → B → A). Filtering a region or a missing coordinate
// must break the line instead of inventing a shortcut over the hidden stop.
export function orderedDayPlaces(day: BookDay, places: BookPlace[]) {
  const ids = day.items.flatMap(item => item.placeIds).filter((id, i, all) => i === 0 || id !== all[i - 1]);
  return ids.map(id => places.find(place => place.id === id));
}

export function handbookLegs(day: BookDay, visible: BookPlace[]) {
  const ordered = orderedDayPlaces(day, visible);
  return ordered.slice(1).flatMap((to, i) => {
    const from = ordered[i];
    return from?.coordinate && to?.coordinate ? [{ from, to, order: i + 1 }] : [];
  });
}
