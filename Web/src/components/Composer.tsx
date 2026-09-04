import { useCallback, useEffect, useRef, useState } from "react";
import { Baby, Landmark, MoonStar, Search, Sparkles, Trees, UtensilsCrossed, Images } from "lucide-react";
import { nominatimSearch, type NominatimPlace } from "../api";
import { useApp } from "../store";
import { INTERESTS, PACE_META, type Interest, type Pace } from "../types";
import { knowledgeCitiesRef } from "../knowledge";

const INTEREST_ICONS = {
  gardens: Landmark,
  culture: Images,
  food: UtensilsCrossed,
  nature: Trees,
  family: Baby,
  night: MoonStar
} as const;

export default function Composer() {
  const { state, updateDraft, resolveDestination, generatePlan, toggleChat } = useApp();
  const draft = state.draft;
  const [query, setQuery] = useState(draft.destination);
  const [suggestions, setSuggestions] = useState<NominatimPlace[]>([]);
  const [open, setOpen] = useState(false);
  const timerRef = useRef<number | null>(null);
  const inputRef = useRef<HTMLInputElement | null>(null);
  const pickedAtRef = useRef(0);

  useEffect(() => {
    setQuery(draft.destination);
  }, [draft.destination]);

  const { settings } = state;
  const search = useCallback(async (text: string) => {
    if (text.trim().length < 2) {
      setSuggestions([]);
      return;
    }
    const normalized = text.trim().replace(/(市|省)$/, "");
    const local = knowledgeCitiesRef()
      .filter((city) => city.city.includes(normalized) || normalized.includes(city.city))
      .slice(0, 6)
      .flatMap<NominatimPlace>((city) => city.coord ? [{
        name: city.city,
        display_name: `${city.city}, ${city.province || city.country}, 离线可规划`,
        latitude: city.coord.lat,
        longitude: city.coord.lng,
        type: "administrative",
        addresstype: "city"
      }] : []);
    setSuggestions(local);
    try {
      const remote = await nominatimSearch(settings.backendURL, text, 6);
      const names = new Set(local.map((item) => item.name));
      setSuggestions([...local, ...remote.filter((item) => !names.has(item.name))].slice(0, 8));
    } catch {
      setSuggestions(local);
    }
  }, [settings.backendURL]);

  const onInput = (text: string) => {
    setQuery(text);
    setOpen(true);
    if (timerRef.current) window.clearTimeout(timerRef.current);
    timerRef.current = window.setTimeout(() => void search(text), 550);
  };

  const pick = async (place: NominatimPlace) => {
    pickedAtRef.current = Date.now();
    setSuggestions([]);
    setOpen(false);
    inputRef.current?.blur();
    await resolveDestination(place.display_name.split(",")[0] || place.name);
    setQuery(place.name);
  };

  const canGenerate = draft.destination.length > 0 && state.phase !== "planning";

  return (
    <div className="composer" onClick={(e) => e.stopPropagation()}>
      <div className="composer-row">
        <span className="search-icon" aria-hidden="true"><Search size={20} strokeWidth={2.2} /></span>
        <input
          ref={inputRef}
          placeholder="想去哪座城市？比如：苏州、杭州、青岛…"
          value={query}
          onChange={(e) => onInput(e.target.value)}
          onFocus={() => {
            if (!open && Date.now() - pickedAtRef.current > 1500) {
              setOpen(true);
              void search(query);
            }
          }}
          onKeyDown={(e) => {
            if (e.key === "Escape") {
              setOpen(false);
              setSuggestions([]);
              return;
            }
            if (e.key === "Enter") {
              e.preventDefault();
              if (query.trim() && query.trim() !== draft.destination) {
                void resolveDestination(query.trim());
                setOpen(false);
              } else if (canGenerate) {
                void generatePlan();
              }
            }
          }}
          aria-label="目的地搜索"
        />
        <div className="composer-actions">
          <button className="chip-btn" title="打开智能向导" onClick={() => toggleChat(true)}>
            <Sparkles size={16} aria-hidden="true" /> 直接说吧
          </button>
          <button className="generate-btn" disabled={!canGenerate} onClick={() => void generatePlan()}>
            {state.phase === "planning" ? "规划中…" : "让旅程展开"}
          </button>
        </div>
      </div>
      {open && suggestions.length > 0 && (
        <div className="suggestions">
          {suggestions.map((s) => (
            <button
              key={`${s.name}-${s.latitude}-${s.longitude}`}
              className="suggestion"
              onClick={() => void pick(s)}
            >
              <div className="s-name">{s.name || s.display_name.split(",")[0]}</div>
              <div className="s-detail">{s.display_name.slice(0, 90)}</div>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

/** Conditions form shared by the desktop side panel and the mobile sheet. */
export function ConditionsCard() {
  const { state, updateDraft, generatePlan } = useApp();
  const draft = state.draft;
  return (
    <div>
      <div className="section-title">这次怎么走</div>
      <div className="composer-expanded" style={{ borderTop: "none", padding: "4px 0 10px" }}>
        <div className="field">
          <label htmlFor="trip-origin">出发地（用于往返班次）</label>
          <input
            id="trip-origin"
            type="text"
            placeholder="比如：上海"
            value={draft.origin}
            onChange={(e) => updateDraft({ origin: e.target.value })}
          />
        </div>
        <div className="field">
          <label htmlFor="trip-start-date">出发日期</label>
          <input
            id="trip-start-date"
            type="date"
            value={draft.startDate ?? ""}
            onChange={(e) => updateDraft({ startDate: e.target.value })}
          />
        </div>
        <div className="field">
          <label>天数</label>
          <div className="stepper">
            <button aria-label="减少一天" onClick={() => updateDraft({ dayCount: Math.max(draft.dayCount - 1, 1) })} disabled={draft.dayCount <= 1}>
              −
            </button>
            <span>{draft.dayCount} 天</span>
            <button aria-label="增加一天" onClick={() => updateDraft({ dayCount: Math.min(draft.dayCount + 1, 14) })} disabled={draft.dayCount >= 14}>
              +
            </button>
          </div>
        </div>
        <div className="field">
          <label>同行人数</label>
          <div className="stepper">
            <button aria-label="减少一人" onClick={() => updateDraft({ travelers: Math.max(draft.travelers - 1, 1) })} disabled={draft.travelers <= 1}>
              −
            </button>
            <span>{draft.travelers} 人</span>
            <button aria-label="增加一人" onClick={() => updateDraft({ travelers: Math.min(draft.travelers + 1, 10) })} disabled={draft.travelers >= 10}>
              +
            </button>
          </div>
        </div>
        <div className="field">
          <label htmlFor="trip-budget">人均预算（元）</label>
          <input
            id="trip-budget"
            type="number"
            value={draft.budgetPerPerson ?? ""}
            min={100}
            step={100}
            onChange={(e) => updateDraft({ budgetPerPerson: Number(e.target.value) || undefined })}
          />
        </div>
        <div className="field">
          <label htmlFor="trip-pace">节奏</label>
          <select id="trip-pace" value={draft.pace} onChange={(e) => updateDraft({ pace: e.target.value as Pace })}>
            {(Object.keys(PACE_META) as Pace[]).map((pace) => (
              <option key={pace} value={pace}>
                {PACE_META[pace].title} · {PACE_META[pace].note}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label htmlFor="trip-transport-mode">市内移动（估算）</label>
          <select id="trip-transport-mode" value={draft.transportMode} onChange={(e) => updateDraft({ transportMode: e.target.value as TripDraftTransportMode })}>
            <option value="transit">地铁公交</option>
            <option value="walking">步行</option>
            <option value="driving">打车/自驾</option>
          </select>
        </div>
        <div className="field" style={{ gridColumn: "1 / -1" }}>
          <label>想去哪类地方</label>
          <div className="interest-grid">
            {INTERESTS.map((interest) => (
              (() => {
                const Icon = INTEREST_ICONS[interest.id];
                const selected = draft.interests.includes(interest.id);
                return (
                  <button
                    key={interest.id}
                    className={`chip-btn ${selected ? "active" : ""}`}
                    aria-pressed={selected}
                    onClick={() => {
                      const next = selected
                        ? draft.interests.filter((i) => i !== interest.id)
                        : [...draft.interests, interest.id];
                      updateDraft({ interests: next.length === 0 ? (["gardens"] as Interest[]) : next });
                    }}
                  >
                    <Icon size={15} aria-hidden="true" /> {interest.title}
                  </button>
                );
              })()
            ))}
          </div>
        </div>
      </div>
      <button
        className="generate-btn"
        style={{ width: "100%", marginTop: 4 }}
        disabled={state.phase === "planning" || !draft.destination}
        onClick={() => void generatePlan()}
      >
        {state.phase === "planning" ? "规划中…" : "让旅程展开"}
      </button>
      <div className="sub-text" style={{ marginTop: 8, lineHeight: 1.6 }}>
        条件可以随时改：日期、人数、预算、节奏、兴趣与城市内移动方式；重新生成会替换方案，也可以先“存进旅册”。
      </div>
    </div>
  );
}

type TripDraftTransportMode = "walking" | "transit" | "driving";
