import { useState } from "react";
import { useApp } from "../store";
import { DEFAULT_BACKEND_URL } from "../api";

export default function SettingsPanel({ onClose }: { onClose: () => void }) {
  const { state, saveSettings, refreshChannels, loadTrip, deleteTrip } = useApp();
  const [backendURL, setBackendURL] = useState(state.settings.backendURL);
  const [deepseekKey, setDeepseekKey] = useState(state.settings.deepseekKey);
  const [model, setModel] = useState(state.settings.deepseekModel);
  const [saved, setSaved] = useState(false);

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal-card" onClick={(e) => e.stopPropagation()}>
        <h2>设置与价格渠道</h2>
        <div className="sub-text">密钥只保存在本机浏览器或构建配置中，不会上传或写进 Git。</div>

        <div className="setting-field">
          <label>伴随服务节点地址（报价/门票/智能向导代理）</label>
          <input
            value={backendURL}
            placeholder={DEFAULT_BACKEND_URL}
            onChange={(e) => setBackendURL(e.target.value)}
          />
        </div>
        <div className="setting-field">
          <label>DeepSeek API Key（对话用，可留空用构建配置）</label>
          <input
            type="password"
            value={deepseekKey}
            placeholder="sk-…"
            onChange={(e) => setDeepseekKey(e.target.value)}
          />
        </div>
        <div className="setting-field">
          <label>对话模型</label>
          <input value={model} onChange={(e) => setModel(e.target.value)} />
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

        <h2 style={{ marginTop: 20 }}>旅册</h2>
        {state.savedTrips.length === 0 && <div className="empty-note">还没有保存的行程。</div>}
        {state.savedTrips.map((trip) => (
          <div key={trip.id} className="trip-row">
            <span className="t-title">{trip.title}</span>
            <button className="mini-btn" onClick={() => loadTrip(trip.id)}>
              打开
            </button>
            <button className="mini-btn" onClick={() => deleteTrip(trip.id)}>
              删除
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}
