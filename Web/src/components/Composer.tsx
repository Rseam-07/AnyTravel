import { useCallback, useEffect, useRef, useState } from "react";
import { Baby, Landmark, MoonStar, Search, Sparkles, Trees, UtensilsCrossed, Images } from "lucide-react";
import { nominatimSearch, type NominatimPlace } from "../api";
import { useApp } from "../store";
import { INTERESTS, PACE_META, effectiveParty, type Interest, type MobilityNeed, type Pace, type TravelerProfile } from "../types";
import { knowledgeCitiesRef } from "../knowledge";
import MotionTabs from "./MotionTabs";
import { catalogPlaces } from "../catalog";
import { knowledgePlaces } from "../knowledge";
import { draftChangeImpacts } from "../plan-locks";

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
  const searchVersion = useRef(0);
  const [searchError, setSearchError] = useState("");

  useEffect(() => {
    setQuery(draft.destination);
  }, [draft.destination]);

  const { settings } = state;
  const search = useCallback(async (text: string) => {
    if (text.trim().length < 2) {
      setSuggestions([]);
      return;
    }
    const version = ++searchVersion.current;
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
      if (version !== searchVersion.current) return;
      setSuggestions([...local, ...remote.filter((item) => !names.has(item.name))].slice(0, 8));
    } catch {
      if (version === searchVersion.current) setSuggestions(local);
    }
  }, [settings.backendURL]);

  const onInput = (text: string) => {
    searchVersion.current++;
    setSearchError("");
    setQuery(text);
    setOpen(true);
    if (timerRef.current) window.clearTimeout(timerRef.current);
    timerRef.current = window.setTimeout(() => void search(text), 550);
  };

  const pick = async (place: NominatimPlace) => {
    searchVersion.current++;
    pickedAtRef.current = Date.now();
    setSuggestions([]);
    setOpen(false);
    inputRef.current?.blur();
    await resolveDestination(place.display_name.split(",")[0] || place.name);
    setQuery(place.name);
  };

  const canGenerate = query.trim().length > 0 && state.phase !== "planning";
  const submit = async () => {
    if (query.trim() !== draft.destination) {
      const found = await resolveDestination(query.trim());
      if (!found) { setSearchError("没有定位到这座城市，请尝试完整城市名称。"); return; }
    }
    setOpen(false);
    await generatePlan();
  };

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
              if (canGenerate) void submit();
            }
          }}
          aria-label="目的地搜索"
        />
        <div className="composer-actions">
          <button className="chip-btn" title="打开智能向导" onClick={() => toggleChat(true)}>
            <Sparkles size={16} aria-hidden="true" /> 直接说吧
          </button>
          <button className="generate-btn" disabled={!canGenerate} onClick={() => void submit()}>
            {state.phase === "planning" ? "规划中…" : "生成路线"}
          </button>
        </div>
      </div>
      {searchError && <p className="issue-note" role="alert">{searchError}</p>}
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
  const { state, updateDraft, generatePlan, applyDraftChanges } = useApp();
  const editingExistingPlan = Boolean(state.plan);
  const [draft, setDraft] = useState(state.draft);
  useEffect(() => setDraft(state.draft), [state.draft, state.plan?.generatedAt]);
  const changeDraft = (patch: Partial<typeof draft>) => {
    setDraft((current) => ({ ...current, ...patch }));
    if (!editingExistingPlan) updateDraft(patch);
  };
  const party = effectiveParty(draft);
  const changeParty = (patch: Partial<TravelerProfile>) => {
    const next = { ...party, ...patch };
    changeDraft({ party: next, travelers: next.adults + next.childrenAges.length });
  };
  const impacts = editingExistingPlan ? draftChangeImpacts(state.draft, draft) : [];
  const localCandidates = catalogPlaces(draft.destination);
  const candidates = localCandidates.length >= 2 ? localCandidates : knowledgePlaces(draft.destination, draft.interests);
  const setRequired = (id: string) => changeDraft({
    mustVisitIDs: draft.mustVisitIDs?.includes(id) ? draft.mustVisitIDs.filter(p => p !== id) : [...(draft.mustVisitIDs ?? []), id],
    excludedPlaceIDs: draft.excludedPlaceIDs?.filter(p => p !== id)
  });
  return (
    <div className="planning-brief">
      <div className="brief-heading"><span>01</span><h2>先留出旅行的时间</h2></div>
      <div className="brief-fields">
        <div className="field"><label htmlFor="trip-start-date">出发日期</label><input id="trip-start-date" type="date" value={draft.startDate ?? ""} onChange={e => changeDraft({ startDate: e.target.value })} /></div>
        <div className="field"><label>旅行天数</label><div className="stepper"><button aria-label="减少一天" disabled={draft.dayCount <= 1} onClick={() => changeDraft({ dayCount: draft.dayCount - 1 })}>−</button><strong>{draft.dayCount} 天</strong><button aria-label="增加一天" disabled={draft.dayCount >= 14} onClick={() => changeDraft({ dayCount: draft.dayCount + 1 })}>+</button></div></div>
        <div className="field"><label htmlFor="first-day-start">首日几点能开始逛</label><input id="first-day-start" type="time" value={draft.firstDayStart ?? ""} onChange={e => changeDraft({ firstDayStart: e.target.value || undefined })} /><small>算上抵达、安顿的时间</small></div>
        <div className="field"><label htmlFor="last-day-end">末日几点结束游览</label><input id="last-day-end" type="time" value={draft.lastDayEnd ?? ""} onChange={e => changeDraft({ lastDayEnd: e.target.value || undefined })} /><small>留好前往车站或机场的时间</small></div>
      </div>
      <div className="brief-heading"><span>02</span><h2>按你的节奏走</h2></div>
      <MotionTabs label="游览节奏" value={draft.pace} onChange={id => changeDraft({ pace: id as Pace })} items={[
        { id: "relaxed", content: <><b>松弛</b><small>少走，慢慢看</small></> },
        { id: "balanced", content: <><b>适中</b><small>游览与留白兼顾</small></> },
        { id: "full", content: <><b>充实</b><small>愿意多走一点</small></> }
      ]} />
      <div className="field travel-mode-field"><label htmlFor="trip-transport-mode">市内怎么移动</label><select id="trip-transport-mode" value={draft.transportMode} onChange={e => changeDraft({ transportMode: e.target.value as TripDraftTransportMode })}><option value="transit">地铁 / 公交</option><option value="walking">主要步行</option><option value="driving">打车 / 自驾</option></select></div>
      <div className="interest-grid">{INTERESTS.map(interest => { const Icon = INTEREST_ICONS[interest.id]; const selected = draft.interests.includes(interest.id); return <button key={interest.id} className={`chip-btn ${selected ? "active" : ""}`} aria-pressed={selected} onClick={() => changeDraft({ interests: selected ? draft.interests.filter(i => i !== interest.id) : [...draft.interests, interest.id] })}><Icon size={15} aria-hidden="true" />{interest.title}</button>; })}</div>
      {candidates.length > 0 && <details className="brief-disclosure priority-picker">
        <summary><span>有没有一定想去的地方？</span><b>{draft.mustVisitIDs?.length ? `${draft.mustVisitIDs.length} 处必去` : "按需选择"}</b></summary>
        <p>“必去”优先安排，实在放不下会说明原因。其余地点按偏好和距离挑选。</p>
        {candidates.map(place => <div className="priority-choice" key={place.id}><span>{place.name}</span><button className="chip-btn" aria-label={`必去${place.name}`} aria-pressed={Boolean(draft.mustVisitIDs?.includes(place.id))} onClick={() => setRequired(place.id)}>必去</button><button className="chip-btn" aria-label={`不去${place.name}`} aria-pressed={Boolean(draft.excludedPlaceIDs?.includes(place.id))} onClick={() => changeDraft({ excludedPlaceIDs: draft.excludedPlaceIDs?.includes(place.id) ? draft.excludedPlaceIDs.filter(id => id !== place.id) : [...(draft.excludedPlaceIDs ?? []), place.id], mustVisitIDs: draft.mustVisitIDs?.filter(id => id !== place.id) })}>不去</button></div>)}
      </details>}
      <details className="brief-disclosure"><summary><span>同行、预算与往返</span><b>{party.adults + party.childrenAges.length} 人</b></summary>
        <div className="brief-fields">
          <div className="field"><label htmlFor="trip-origin">出发地</label><input id="trip-origin" value={draft.origin} placeholder="用于查询往返班次" onChange={e => changeDraft({ origin: e.target.value })} /></div>
          <div className="field"><label htmlFor="trip-budget">人均预算（元）</label><input id="trip-budget" type="number" min={100} step={100} value={draft.budgetPerPerson ?? ""} onChange={e => changeDraft({ budgetPerPerson: Number(e.target.value) || undefined })} /></div>
        </div>
        <div className="stepper"><span>成人 {party.adults} 人</span><button aria-label="减少一位成人" disabled={party.adults <= 1} onClick={() => changeParty({ adults: party.adults - 1 })}>−</button><button aria-label="增加一位成人" disabled={party.adults >= 8} onClick={() => changeParty({ adults: party.adults + 1 })}>+</button></div>
        {party.childrenAges.map((age, index) => <div className="stepper" key={index}><label htmlFor={`child-age-${index}`}>儿童 {index + 1} 年龄</label><input id={`child-age-${index}`} type="number" min={0} max={17} value={age} onChange={e => changeParty({ childrenAges: party.childrenAges.map((v, i) => i === index ? Math.max(0, Math.min(17, Number(e.target.value))) : v) })} /><button aria-label={`删除第${index + 1}名儿童`} onClick={() => changeParty({ childrenAges: party.childrenAges.filter((_, i) => i !== index) })}>×</button></div>)}
        <button className="chip-btn" disabled={party.childrenAges.length >= 6} onClick={() => changeParty({ childrenAges: [...party.childrenAges, 8] })}>添加儿童</button>
        <div className="stepper"><span>长辈 {party.seniorTravelers} 人</span><button aria-label="减少一位长辈" disabled={party.seniorTravelers <= 0} onClick={() => changeParty({ seniorTravelers: party.seniorTravelers - 1 })}>−</button><button aria-label="增加一位长辈" disabled={party.seniorTravelers >= party.adults} onClick={() => changeParty({ seniorTravelers: party.seniorTravelers + 1 })}>+</button></div>
        <div className="stepper"><span>房间 {party.rooms} 间</span><button aria-label="减少一间房" disabled={party.rooms <= 1} onClick={() => changeParty({ rooms: party.rooms - 1 })}>−</button><button aria-label="增加一间房" disabled={party.rooms >= 4} onClick={() => changeParty({ rooms: party.rooms + 1 })}>+</button></div>
        <div className="field"><label htmlFor="mobility-need">行动需要</label><select id="mobility-need" value={party.mobilityNeed} onChange={e => changeParty({ mobilityNeed: e.target.value as MobilityNeed })}><option value="none">无特别需要</option><option value="stroller">携带婴儿车</option><option value="wheelchair">需要无障碍通行</option></select><small>会多留休息时间；实际无障碍通行条件仍需核实。</small></div>
      </details>
      {editingExistingPlan && impacts.length > 0 && <div className="change-preview" role="status"><strong>这次将调整</strong>{impacts.map(impact => <div key={impact.key}><span>{impact.title}</span><small>{impact.detail}</small></div>)}<p>可撤销本次调整。</p></div>}
      <div className="brief-submit"><button className="generate-btn" disabled={state.phase === "planning" || !draft.destination || (editingExistingPlan && !impacts.length)} onClick={() => void (editingExistingPlan ? applyDraftChanges(draft) : generatePlan())}>{state.phase === "planning" ? "正在安排时间与路线…" : editingExistingPlan ? impacts.length ? "应用调整" : "条件没有变化" : "生成我的路线"}</button><p>先有一份走得通的安排，再慢慢调整。</p></div>
    </div>
  );
}

type TripDraftTransportMode = "walking" | "transit" | "driving";
