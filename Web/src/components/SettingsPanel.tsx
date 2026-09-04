import { useEffect, useState } from "react";
import { X } from "lucide-react";
import { useApp } from "../store";
import { DEFAULT_BACKEND_URL } from "../api";

export default function SettingsPanel({ onClose }: { onClose: () => void }) {
  const { state, saveSettings, refreshChannels } = useApp();
  const [backendURL, setBackendURL] = useState(state.settings.backendURL);
  const [deepseekKey, setDeepseekKey] = useState(state.settings.deepseekKey);
  const [model, setModel] = useState(state.settings.deepseekModel);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    window.addEventListener("keydown", closeOnEscape);
    return () => window.removeEventListener("keydown", closeOnEscape);
  }, [onClose]);

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal-card" role="dialog" aria-modal="true" aria-labelledby="settings-title" onClick={(e) => e.stopPropagation()}>
        <div className="modal-head">
          <h2 id="settings-title">设置与价格渠道</h2>
          <button className="chat-close" onClick={onClose} aria-label="关闭设置"><X size={18} aria-hidden="true" /></button>
        </div>
        <div className="sub-text">报价与智能服务密钥应放在 Backend/.env，由伴随服务保管，不会打进网页代码。</div>

        <div className="setting-field">
          <label htmlFor="backend-url">伴随服务节点地址（报价/门票/智能向导代理）</label>
          <input
            id="backend-url"
            value={backendURL}
            placeholder={DEFAULT_BACKEND_URL}
            onChange={(e) => setBackendURL(e.target.value)}
          />
        </div>
        <div className="setting-field">
          <label htmlFor="deepseek-key">浏览器直连 DeepSeek 备用 Key（不推荐）</label>
          <input
            id="deepseek-key"
            type="password"
            value={deepseekKey}
            placeholder="sk-…"
            onChange={(e) => setDeepseekKey(e.target.value)}
          />
          <div className="sub-text">只在伴随服务不可用时使用；仅保留到当前标签页关闭，浏览器直连仍无法像服务端那样保护密钥。</div>
        </div>
        <div className="setting-field">
          <label htmlFor="deepseek-model">备用对话模型</label>
          <input id="deepseek-model" value={model} onChange={(e) => setModel(e.target.value)} />
        </div>
        <button
          className="generate-btn"
          onClick={() => {
            saveSettings({ backendURL, deepseekKey, deepseekModel: model });
            setSaved(true);
            void refreshChannels();
            window.setTimeout(() => setSaved(false), 1600);
          }}
        >
          {saved ? "已保存 ✓" : "保存设置"}
        </button>

        <h2 style={{ marginTop: 20 }}>价格渠道健康</h2>
        <div className="channel-list">
          {state.channels.length === 0 && (
            <div className="empty-note">
              未连接伴随服务：{backendURL || DEFAULT_BACKEND_URL}
              <div style={{ marginTop: 6 }}>
                节点在仓库 <code>Backend/</code> 目录，`npm install && npx playwright install chromium && npm start` 即可启动。
              </div>
            </div>
          )}
          {state.channels.map((channel) => (
            <div key={channel.name} className="channel-row">
              <span
                className={`channel-dot ${channel.status === "configured" ? "on" : channel.status === "unverified" ? "warn" : "off"}`}
              />
              <span style={{ fontWeight: 700 }}>{channel.detail ?? channel.name}</span>
              <span style={{ marginLeft: "auto", fontSize: 11, opacity: 0.7 }}>
                {channel.status === "configured" ? "可用" : "未接通/未配置"}
              </span>
            </div>
          ))}
        </div>

      </div>
    </div>
  );
}
