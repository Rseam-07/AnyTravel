import { useCallback, useEffect, useRef, useState } from "react";
import { nominatimSearch, type NominatimPlace } from "../api";
import { useApp } from "../store";
import { INTERESTS, PACE_META, type Interest, type Pace } from "../types";

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
    try {
      setSuggestions(await nominatimSearch(settings.backendURL, text, 6));
    } catch {
      setSuggestions([]);
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
    updateDraft({ destination: place.name });
    await resolveDestination(place.display_name.split(",")[0] || place.name);
    setQuery(place.name);
  };

  const canGenerate = draft.destination.length > 0 && state.phase !== "planning";

  return (
    <div className="composer" onClick={(e) => e.stopPropagation()}>
      <div className="composer-row">
        <span className="search-icon">🔍</span>
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
            ✨ 直接说吧
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
          <label>出发地（用于往返班次）</label>
          <input
            type="text"
            placeholder="比如：上海"
            value={draft.origin}
            onChange={(e) => updateDraft({ origin: e.target.value })}
          />
        </div>
        <div className="field">
          <label>出发日期</label>
          <input
            type="date"
            value={draft.startDate ?? ""}
            onChange={(e) => updateDraft({ startDate: e.target.value })}
          />
        </div>
        <div className="field">
          <label>天数</label>
          <div className="stepper">
            <button onClick={() => updateDraft({ dayCount: Math.max(draft.dayCount - 1, 1) })} disabled={draft.dayCount <= 1}>
              −
            </button>
            <span>{draft.dayCount} 天</span>
            <button onClick={() => updateDraft({ dayCount: Math.min(draft.dayCount + 1, 14) })} disabled={draft.dayCount >= 14}>
              +
            </button>
          </div>
        </div>
        <div className="field">
          <label>同行人数</label>
          <div className="stepper">
            <button onClick={() => updateDraft({ travelers: Math.max(draft.travelers - 1, 1) })} disabled={draft.travelers <= 1}>
              −
            </button>
            <span>{draft.travelers} 人</span>
            <button onClick={() => updateDraft({ travelers: Math.min(draft.travelers + 1, 10) })} disabled={draft.travelers >= 10}>
              +
            </button>
          </div>
        </div>
        <div className="field">
          <label>人均预算（元）</label>
          <input
            type="number"
            value={draft.budgetPerPerson ?? ""}
            min={100}
            step={100}
            onChange={(e) => updateDraft({ budgetPerPerson: Number(e.target.value) || undefined })}
          />
        </div>
        <div className="field">
          <label>节奏</label>
          <select value={draft.pace} onChange={(e) => updateDraft({ pace: e.target.value as Pace })}>
            {(Object.keys(PACE_META) as Pace[]).map((pace) => (
              <option key={pace} value={pace}>
                {PACE_META[pace].title} · {PACE_META[pace].note}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label>市内移动（估算）</label>
          <select value={draft.transportMode} onChange={(e) => updateDraft({ transportMode: e.target.value as TripDraftTransportMode })}>
            <option value="transit">地铁公交</option>
            <option value="walking">步行</option>
            <option value="driving">打车/自驾</option>
          </select>
        </div>
        <div className="field" style={{ gridColumn: "1 / -1" }}>
          <label>想去哪类地方</label>
          <div className="interest-grid">
            {INTERESTS.map((interest) => (
              <button
                key={interest.id}
                className={`chip-btn ${draft.interests.includes(interest.id) ? "active" : ""}`}
                onClick={() => {
                  const next = draft.interests.includes(interest.id)
                    ? draft.interests.filter((i) => i !== interest.id)
                    : [...draft.interests, interest.id];
                  updateDraft({ interests: next.length === 0 ? (["gardens"] as Interest[]) : next });
                }}
              >
                {interest.symbol} {interest.title}
              </button>
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
