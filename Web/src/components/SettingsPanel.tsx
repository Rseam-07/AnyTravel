import { useEffect, useRef, useState } from "react";
import { RefreshCw, ShieldCheck, Sparkles, X } from "lucide-react";
import { useApp } from "../store";
import { DEFAULT_BACKEND_URL } from "../api";
import { normalizeServiceURL } from "../service-config";

export default function SettingsPanel({ onClose }: { onClose: () => void }) {
  const { state, saveSettings, refreshChannels } = useApp();
  const [backendURL, setBackendURL] = useState(state.settings.backendURL);
  const [deepseekKey, setDeepseekKey] = useState(state.settings.deepseekKey);
  const [model, setModel] = useState(state.settings.deepseekModel);
  const [message, setMessage] = useState("");
  const [checking, setChecking] = useState(false);
  const card = useRef<HTMLDivElement>(null);
  const closeRef = useRef(onClose);
  closeRef.current = onClose;

  useEffect(() => {
    const previousFocus = document.activeElement as HTMLElement | null;
    card.current?.querySelector<HTMLButtonElement>("button")?.focus();
    const handleKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") { event.stopPropagation(); closeRef.current(); }
      if (event.key !== "Tab") return;
      const controls = [...(card.current?.querySelectorAll<HTMLElement>("button:not(:disabled), input:not(:disabled), summary, a[href]") ?? [])]
        .filter(element => element.getClientRects().length > 0);
      const first = controls[0], last = controls[controls.length - 1];
      if (!first) return;
      if (event.shiftKey && (document.activeElement === first || !card.current?.contains(document.activeElement))) {
        event.preventDefault(); last.focus();
      } else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    };
    window.addEventListener("keydown", handleKey);
    return () => { window.removeEventListener("keydown", handleKey); previousFocus?.focus(); };
  }, []);

  const enabled = state.channels.filter(channel => channel.status !== "disabled");
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div ref={card} className="modal-card" role="dialog" aria-modal="true" aria-labelledby="settings-title" onClick={event => event.stopPropagation()}>
        <div className="modal-head">
          <h2 id="settings-title">旅途偏好与服务</h2>
          <button className="chat-close" onClick={onClose} aria-label="关闭设置"><X size={20} aria-hidden="true" /></button>
        </div>
        <div className="service-summary">
          <Sparkles size={23} aria-hidden="true" />
          <div><strong>默认服务，无需配置</strong><p>规划、住宿和交通查询沿用应用预设。你只需要决定去哪里，无需填写接口或密钥。</p></div>
        </div>
        <div className="service-summary">
          <ShieldCheck size={23} aria-hidden="true" />
          <div><strong>选择不等于预订</strong><p>价格注明来源和查询时间。预订与付款由原平台完成，出发前请复核库存、税费和退改条件。</p></div>
        </div>
        <div className="modal-head service-heading">
          <h2>在线服务状态</h2>
          <button className="chip" disabled={checking} onClick={async () => {
            setChecking(true);
            try { await refreshChannels(); } finally { setChecking(false); }
          }}><RefreshCw size={16} aria-hidden="true" />{checking ? "检查中…" : "重新检查"}</button>
        </div>
        <div role="status" className="sub-text">
          {state.backendReachable ? "已连接 AnyTravel。接入状态不代表当前有房或有票，具体以每次查询为准。"
            : "在线服务暂未连接，内置地点与本机规划仍可用。可以稍后重试，不必修改设置。"}
        </div>
        <div className="channel-list">
          {enabled.map(channel => <div key={channel.name} className="channel-row">
            <span className="channel-dot on" aria-hidden="true" /><strong>{channel.detail ?? channel.name}</strong><span>已接入</span>
          </div>)}
        </div>
        <details className="advanced-settings">
          <summary>高级设置（可选）</summary>
          <p className="sub-text">仅在你希望使用自己的服务时更改。留空地址将恢复应用预设。</p>
          <div className="setting-field">
            <label htmlFor="backend-url">自建服务地址</label>
            <input id="backend-url" value={backendURL} placeholder="留空使用默认服务" onChange={event => setBackendURL(event.target.value)} />
          </div>
          <div className="setting-field">
            <label htmlFor="deepseek-key">自定义 DeepSeek Key</label>
            <input id="deepseek-key" type="password" autoComplete="off" value={deepseekKey} onChange={event => setDeepseekKey(event.target.value)} />
            <p className="sub-text">仅作为默认向导不可用时的备用；只保存到当前标签页关闭。使用时问题与当前行程将发往 DeepSeek。</p>
          </div>
          <div className="setting-field">
            <label htmlFor="deepseek-model">自定义模型名称</label>
            <input id="deepseek-model" value={model} onChange={event => setModel(event.target.value)} />
          </div>
          <button className="generate-btn" onClick={() => {
            const url = backendURL.trim() ? normalizeServiceURL(backendURL) : DEFAULT_BACKEND_URL;
            if (!url) { setMessage("请使用完整的 HTTPS 地址；本机调试可使用 localhost。原设置没有改变。"); return; }
            try {
              saveSettings({ backendURL: url, deepseekKey, deepseekModel: model.trim() || "deepseek-chat" });
              setMessage("设置已保存。服务状态会自动重新检查。");
            } catch { setMessage("浏览器暂时无法保存设置，请检查存储空间或浏览器的隐私设置。原设置没有改变。"); }
          }}>保存高级设置</button>
          {message && <p role="status" className="sub-text">{message}</p>}
        </details>
      </div>
    </div>
  );
}
