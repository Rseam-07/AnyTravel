import { Component, useEffect, useRef, useState, type ReactNode } from "react";
import { AppProvider, useApp } from "./store";
import MapView from "./components/MapView";
import Composer, { ConditionsCard } from "./components/Composer";
import ChatPanel from "./components/ChatPanel";
import SettingsPanel from "./components/SettingsPanel";
import TrackRail from "./components/TrackRail";
import { AccommodationPanel, BudgetPanel, PlanPanel, TransportPanel } from "./components/Panels";
import type { Interest } from "./types";

type Tab = "compose" | "plan" | "stay" | "transport" | "budget";

const TAB_META: { id: Tab; title: string }[] = [
  { id: "compose", title: "条件" },
  { id: "plan", title: "方案" },
  { id: "stay", title: "住宿" },
  { id: "transport", title: "交通" },
  { id: "budget", title: "费用" }
];

export default function App() {
  return (
    <ErrorBoundary>
      <AppProvider>
        <Shell />
      </AppProvider>
    </ErrorBoundary>
  );
}

class ErrorBoundary extends Component<{ children: ReactNode }, { message: string | null }> {
  state: { message: string | null } = { message: null };
  static getDerivedStateFromError(error: unknown) {
    return { message: error instanceof Error ? error.message : String(error) };
  }
  render() {
    if (this.state.message) {
      return (
        <div style={{ padding: 40, fontFamily: "var(--font)" }}>
          <h2>页面遇到了一点问题</h2>
          <pre style={{ whiteSpace: "pre-wrap", background: "#f3efe7", padding: 16, borderRadius: 12 }}>{this.state.message}</pre>
          <button className="primary-cta" onClick={() => location.reload()}>
            刷新重试
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}

function Shell() {
  const app = useApp();
  const state = app.state;
  const [tab, setTab] = useState<Tab>("plan");
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [collapsed, setCollapsed] = useState(false);

  if (state.phase === "welcome") {
    return <Welcome />;
  }

  return (
    <div className="app" onClick={() => undefined}>
      <MapView />
      <div className="top-bar desktop-only">
        <Composer />
      </div>
      {state.phase === "planning" && <div className="phase-pill">正在翻阅这座城的热门去处…</div>}

      <aside className={`side-panel desktop-only${collapsed ? " collapsed" : ""}`}>
        <button
          className="collapse-handle"
          onClick={() => setCollapsed((v) => !v)}
          aria-label={collapsed ? "展开面板" : "收起面板"}
        >
          {collapsed ? "›" : "‹"}
        </button>
        {!collapsed && (
          <>
            <PanelTabs tab={tab} setTab={setTab} />
            <div className="side-content">
              <PanelBody tab={tab} />
            </div>
          </>
        )}
      </aside>

      <div className="desktop-only">
        <TrackRail />
      </div>

      <MobileLayer tab={tab} setTab={setTab} />

      <button className="chat-fab" onClick={() => app.toggleChat(true)} aria-label="打开智能向导">
        ✨
      </button>
      {state.chatOpen && <ChatPanel />}

      <button
        className="map-control"
        style={{ position: "absolute", top: 18, right: 76, zIndex: 8 }}
        onClick={() => setSettingsOpen(true)}
        aria-label="设置"
      >
        ⚙️
      </button>
      {settingsOpen && <SettingsPanel onClose={() => setSettingsOpen(false)} />}

      <div className="print-plan">
        <PrintView />
      </div>
    </div>
  );
}

function PanelTabs({ tab, setTab }: { tab: Tab; setTab: (tab: Tab) => void }) {
  return (
    <div className="side-tabs">
      {TAB_META.map((meta) => (
        <button key={meta.id} className={`side-tab${tab === meta.id ? " active" : ""}`} onClick={() => setTab(meta.id)}>
          {meta.title}
        </button>
      ))}
    </div>
  );
}

function PanelBody({ tab }: { tab: Tab }) {
  switch (tab) {
    case "compose":
      return <ConditionsCard />;
    case "plan":
      return <PlanPanel />;
    case "stay":
      return <AccommodationPanel />;
    case "transport":
      return <TransportPanel />;
    case "budget":
      return <BudgetPanel />;
  }
}

// ---------- mobile: three-detent sheet ----------

const DETENTS = { compact: 190, medium: window.innerHeight * 0.52, large: window.innerHeight * 0.88 };

function MobileLayer({ tab, setTab }: { tab: Tab; setTab: (tab: Tab) => void }) {
  const app = useApp();
  const [detent, setDetent] = useState<keyof typeof DETENTS>("medium");
  const [dragY, setDragY] = useState<number | null>(null);
  const startRef = useRef<{ y: number; height: number } | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);

  const height = dragY != null ? dragY : DETENTS[detent];

  useEffect(() => {
    DETENTS.medium = window.innerHeight * 0.52;
    DETENTS.large = window.innerHeight * 0.88;
    setDetent((d) => {
      if (d === "medium") return "medium";
      return d;
    });
  }, []);

  const onPointerDown = (e: React.PointerEvent) => {
    startRef.current = { y: e.clientY, height: heightRef() };
    (e.target as HTMLElement).setPointerCapture?.(e.pointerId);
  };
  const heightRef = () => (dragY != null ? dragY : DETENTS[detent]);

  const onPointerMove = (e: React.PointerEvent) => {
    if (!startRef.current) return;
    const next = startRef.current.height + (startRef.current.y - e.clientY);
    setDragY(Math.max(90, Math.min(window.innerHeight - 40, next)));
  };

  const onPointerUp = () => {
    startRef.current = null;
    const current = dragY ?? DETENTS[detent];
    const candidates: [keyof typeof DETENTS, number][] = [
      ["compact", DETENTS.compact],
      ["medium", DETENTS.medium],
      ["large", DETENTS.large]
    ];
    const nearest = candidates.sort((a, b) => Math.abs(a[1] - current) - Math.abs(b[1] - current))[0][0];
    setDetent(nearest);
    setDragY(null);
  };

  const stepUp = () => {
    const order: (keyof typeof DETENTS)[] = ["compact", "medium", "large"];
    const index = order.indexOf(detent);
    setDetent(order[Math.min(index + 1, order.length - 1)]);
  };
  const stepDown = () => {
    const order: (keyof typeof DETENTS)[] = ["compact", "medium", "large"];
    const index = order.indexOf(detent);
    setDetent(order[Math.max(index - 1, 0)]);
  };

  return (
    <div
      ref={containerRef}
      className="mobile-sheet mobile-only"
      style={{ height }}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerUp}
    >
      <button className="sheet-expand" onClick={detent === "large" ? stepDown : stepUp} aria-label="切换面板高度">
        {detent === "large" ? "▾" : "▴"}
      </button>
      <div className="sheet-handle">
        <div className="bar" />
      </div>
      <div className="mobile-only" style={{ padding: "0 10px 8px" }}>
        <Composer />
      </div>
      <div className="sheet-tabs">
        {TAB_META.map((meta) => (
          <button key={meta.id} className={`side-tab${tab === meta.id ? " active" : ""}`} onClick={() => setTab(meta.id)}>
            {meta.title}
          </button>
        ))}
      </div>
      <div className="sheet-content">
        <PanelBody tab={tab} />
      </div>
    </div>
  );
}

function Welcome() {
  const app = useApp();
  const { updateDraft, dismissWelcome, resolveDestination, generatePlan } = app;

  const startExample = async (destination: string, dayCount: number, travelers: number, pace: "relaxed" | "balanced" | "full", interest?: Interest) => {
    updateDraft({ dayCount, travelers, pace, interests: interest ? [interest, "culture", "food", "nature"] : ["gardens", "culture", "food", "nature"] });
    await resolveDestination(destination);
    dismissWelcome();
    void generatePlan();
  };

  return (
    <div className="welcome">
      <div className="welcome-card">
        <div className="welcome-logo">远</div>
        <h1>旅行是一场诗意的迁徙</h1>
        <p>
          先选车次，还是先挑住处？都可以。把想去的地方、预算和节奏交给 AnyTravel，
          它会在背景地图上把日子铺成一条能走的路线——每个人都能看懂为什么这样排。
        </p>
        <div className="example-chips">
          <button className="example-chip" onClick={() => void startExample("苏州", 3, 2, "relaxed")}>🌿 苏州 3 天 2 人</button>
          <button className="example-chip" onClick={() => void startExample("杭州", 4, 2, "relaxed", "gardens")}>🏞️ 杭州 4 天，园林古镇</button>
          <button className="example-chip" onClick={() => void startExample("青岛", 3, 4, "balanced")}>🌊 青岛 3 天 4 人</button>
        </div>
        <button className="primary-cta" onClick={dismissWelcome}>开始规划</button>
        <p style={{ marginTop: 22, fontSize: 12 }}>
          Web 版与 iOS 共用同一套行程模型与价格渠道：铁路 12306、去哪儿门票、RollingGo/携程/同程/艺龙/万邦 由伴随服务承载（见“设置”）。
        </p>
      </div>
    </div>
  );
}

function PrintView() {
  const { state } = useApp();
  const plan = state.plan;
  if (!plan) return null;
  return (
    <div>
      <h1>{state.draft.destination} · {state.draft.dayCount} 天行程</h1>
      {plan.days.map((day, i) => (
        <section key={i}>
          <h2>{day.title}</h2>
          {day.stops.map((stop, index) => (
            <p key={index}>
              <strong>{stop.arrivalText}–{stop.departureText}</strong> {stop.place.name}
              {stop.place.address ? `（${stop.place.address.slice(0, 80)}）` : ""}
            </p>
          ))}
        </section>
      ))}
    </div>
  );
}
