import { useRef, useState } from "react";
import { flightSearchURL, importFlightResearch, researchFromRows, type FlightResearch } from "../flight-import";
import type { TransportOption, TripDraft } from "../types";
import { addDays } from "../planner";

export default function FlightResearchImport({ draft, direction, onImport }: { draft: TripDraft; direction: "outbound" | "return"; onImport: (options: TransportOption[]) => void }) {
  const origin = direction === "outbound" ? draft.origin : draft.destination;
  const destination = direction === "outbound" ? draft.destination : draft.origin;
  const start = draft.startDate ?? "";
  const date = direction === "outbound" ? start : start ? addDays(start, draft.dayCount - 1) : "";
  const searchURL = flightSearchURL(origin, destination, date);
  const file = useRef<HTMLInputElement>(null);
  const [text, setText] = useState("");
  const [source, setSource] = useState(searchURL);
  const [error, setError] = useState("");
  const [preview, setPreview] = useState<TransportOption[]>([]);
  const parse = (data: FlightResearch) => {
    try { setPreview(importFlightResearch(data, { origin, destination, date, direction })); setError(""); }
    catch (error) { setError(error instanceof Error ? error.message : "无法识别查询记录"); setPreview([]); }
  };
  if (!origin || !destination || !date) return null;
  return <details className="flight-research">
    <summary>从网页补充航班</summary>
    <p className="sub-text">{origin} → {destination} · {date}。自动查询没有结果时，可将网页查到的班次带回行程。仅记录查询，不会购票。</p>
    <div className="research-actions"><a className="chip-btn" href={searchURL} target="_blank" rel="noreferrer">打开携程查询这一程 ↗</a><button className="chip-btn" onClick={() => file.current?.click()}>导入查询记录</button></div>
    <input ref={file} hidden type="file" accept=".json,application/json" onChange={async e => {
      const picked = e.target.files?.[0]; e.target.value = ""; if (!picked) return;
      try { if (picked.size > 100_000) throw new Error("查询记录过大，请使用不超过 100 KB 的文件。"); parse(JSON.parse(await picked.text())); } catch (error) { setPreview([]); setError(error instanceof Error ? error.message : "文件无法读取"); }
    }}/>
    <label className="research-field">查询网页链接<input value={source} type="url" onChange={e => { setSource(e.target.value); setPreview([]); }}/></label>
    <label className="research-field">粘贴核对后的班次<textarea rows={4} value={text} onChange={e => { setText(e.target.value); setPreview([]); }} placeholder="每行：航班号 | 起飞 | 到达 | 成人单程票价 | 出发机场 | 到达机场"/></label>
    <p className="sub-text">时间采用中国标准时间。跨日到达写为 01:30 +1；填网页票面价，不要填多人优惠广告价。点击识别时记录查询时间。</p>
    <button className="chip-btn" disabled={!text.trim()} onClick={() => parse(researchFromRows(text, { origin, destination, date, sourceURL: source, capturedAt: new Date().toISOString() }))}>识别并核对</button>
    {error && <p className="issue-note" role="alert">{error}</p>}
    {preview.length > 0 && <div className="research-preview"><strong>{preview.length} 班 · {origin} → {destination} · {date}</strong>{preview.map(item => <p key={item.id}>{item.title.split(" · ")[0]} · {item.departureTime?.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit", timeZone: "Asia/Shanghai" })} — {item.arrivalTime?.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit", timeZone: "Asia/Shanghai" })} · ¥{item.quotes[0].amountCNY}/人</p>)}<button className="chip-btn" onClick={() => { onImport(preview); setPreview([]); setText(""); }}>确认加入这一程</button></div>}
  </details>;
}
