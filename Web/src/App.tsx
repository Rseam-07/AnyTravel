import { Component, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import {
  BedDouble,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  ChevronUp,
  Luggage,
  Map as MapIcon,
  RotateCcw,
  Settings,
  SlidersHorizontal,
  TrainFront,
  WalletCards
} from "lucide-react";
import { AppProvider, useApp } from "./store";
import MapView, { type MapSection } from "./components/MapView";
import Composer, { ConditionsCard } from "./components/Composer";
import ChatPanel from "./components/ChatPanel";
import SettingsPanel from "./components/SettingsPanel";
import { AccommodationPanel, BudgetPanel, PlanPanel, TransportPanel } from "./components/Panels";

type ReadyTab = "plan" | "stay" | "transport" | "budget";

const READY_TABS = [
  { id: "plan", title: "行程", icon: MapIcon },
  { id: "stay", title: "住宿", icon: BedDouble },
  { id: "transport", title: "交通", icon: TrainFront },
  { id: "budget", title: "费用", icon: WalletCards }
] satisfies { id: ReadyTab; title: string; icon: typeof MapIcon }[];

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
        <div className="fatal-state">
          <h2>这一段路暂时没有接上</h2>
          <p>{this.state.message}</p>
          <button className="primary-cta" onClick={() => location.reload()}>刷新重试</button>
        </div>
      );
    }
    return this.props.children;
  }
}

function Shell() {
  const app = useApp();
  const { state } = app;
  const [tab, setTab] = useState<ReadyTab>("plan");
  const [editingConditions, setEditingConditions] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [libraryOpen, setLibraryOpen] = useState(false);
  const [collapsed, setCollapsed] = useState(false);
  const [mapDark, setMapDark] = useState(() => localStorage.getItem("anytravel-web:mapstyle") === "dark");
  const hasPlan = Boolean(state.plan);
  const mapSection: MapSection = !hasPlan ? "plan" : tab === "stay" ? "stay" : tab === "transport" ? "transport" : "plan";

  useEffect(() => {
    if (state.phase === "ready") {
      setTab("plan");
      setEditingConditions(false);
    }
  }, [state.plan?.generatedAt, state.phase]);

  return (
    <div className={`app${mapDark ? " dark" : ""}`}>
      <MapView dark={mapDark} onDarkChange={setMapDark} activeSection={mapSection} />
      <TopChrome
        onReset={app.resetAll}
        onOpenSettings={() => setSettingsOpen(true)}
        onOpenLibrary={() => setLibraryOpen(true)}
      />

      {state.phase === "planning" && <div className="route-status">正在筛地点、排顺序、铺路线…</div>}
      {state.phase === "ready" && state.plan && (
        <div className="route-status">
          {tab === "stay"
            ? "落脚片区已经和每日主线对齐"
            : tab === "transport"
              ? "往返选择已经和目的地保持同步"
              : tab === "budget"
                ? "费用会随着你的选择一起更新"
                : `第 ${state.selectedDay + 1} 天的脚步已经落在地图上`}
        </div>
      )}

      <aside className={`side-panel desktop-only${collapsed ? " collapsed" : ""}`}>
        <button
          className="collapse-handle"
          onClick={() => setCollapsed((value) => !value)}
          aria-label={collapsed ? "展开规划面板" : "收起规划面板"}
        >
          {collapsed ? <ChevronRight size={18} aria-hidden="true" /> : <ChevronLeft size={18} aria-hidden="true" />}
        </button>
        {!collapsed && (
          <PanelScaffold
            tab={tab}
            setTab={setTab}
            hasPlan={hasPlan}
            editingConditions={editingConditions}
            setEditingConditions={setEditingConditions}
          />
        )}
      </aside>

      <MobileLayer
        tab={tab}
        setTab={setTab}
        hasPlan={hasPlan}
        editingConditions={editingConditions}
        setEditingConditions={setEditingConditions}
      />

      {state.chatOpen && <ChatPanel />}
      {settingsOpen && <SettingsPanel onClose={() => setSettingsOpen(false)} />}
      {libraryOpen && <LibraryPanel onClose={() => setLibraryOpen(false)} />}

      <div className="print-plan"><PrintView /></div>
    </div>
  );
}

function TopChrome({
  onReset,
  onOpenSettings,
  onOpenLibrary
}: {
  onReset: () => void;
  onOpenSettings: () => void;
  onOpenLibrary: () => void;
}) {
  const { state } = useApp();
  const title = state.draft.destination || "AnyTravel";
  const subtitle = state.phase === "planning"
    ? "正在把想法落到地图上"
    : state.phase === "ready"
      ? `${state.draft.dayCount} 天 · 每次选择都落在地图上`
      : state.phase === "failure"
        ? "这一段路需要重新接上"
        : state.draft.destination
          ? "再告诉我一点旅途偏好"
          : "地图正等你说出下一处远方";
  const progress = state.phase === "ready" || state.phase === "failure"
    ? 3
    : state.phase === "planning"
      ? 2
      : state.draft.destination
        ? 1
        : 0;

  return (
    <header className="ios-chrome">
      <div className="chrome-row">
        <button className="glass-circle" onClick={onReset} aria-label="重新规划" title="重新规划">
          <RotateCcw size={20} aria-hidden="true" />
        </button>
        <div className="journey-title" aria-live="polite">
          <strong>{title}</strong>
          <span>{subtitle}</span>
        </div>
        <button className="glass-circle" onClick={onOpenSettings} aria-label="旅途偏好与价格渠道" title="设置">
          <Settings size={20} aria-hidden="true" />
        </button>
        <button className="glass-circle" onClick={onOpenLibrary} aria-label="已保存行程" title="旅册">
          <Luggage size={20} aria-hidden="true" />
        </button>
      </div>
      <div className="progress-dots" aria-label={`规划进度，第 ${progress + 1} 步，共 4 步`}>
        {[0, 1, 2, 3].map((index) => <i key={index} className={index === progress ? "active" : ""} />)}
      </div>
    </header>
  );
}

function PanelScaffold({
  tab,
  setTab,
  hasPlan,
  editingConditions,
  setEditingConditions
}: {
  tab: ReadyTab;
  setTab: (tab: ReadyTab) => void;
  hasPlan: boolean;
  editingConditions: boolean;
  setEditingConditions: (value: boolean) => void;
}) {
  return (
    <>
      <div className="panel-grabber" aria-hidden="true"><i /></div>
      {hasPlan && !editingConditions && <PanelTabs tab={tab} setTab={setTab} />}
      <div className="side-content">
        {!hasPlan ? (
          <DestinationStart />
        ) : editingConditions ? (
          <div className="conditions-view">
            <div className="panel-section-head">
              <div>
                <span>调整行程</span>
                <small>日期、人数、预算与抵达方式</small>
              </div>
              <button className="chip-btn" onClick={() => setEditingConditions(false)}>返回行程</button>
            </div>
            <ConditionsCard />
          </div>
        ) : (
          <>
            <div className="ready-tools">
              <span>{tab === "plan" ? "当天路线" : tab === "stay" ? "落脚选择" : tab === "transport" ? "往返抵达" : "旅途花费"}</span>
              <button className="chip-btn" onClick={() => setEditingConditions(true)}>
                <SlidersHorizontal size={15} aria-hidden="true" /> 调整
              </button>
            </div>
            <PanelBody tab={tab} goConditions={() => setEditingConditions(true)} />
          </>
        )}
      </div>
    </>
  );
}

function DestinationStart() {
  const { state, resolveDestination } = useApp();
  const [choosing, setChoosing] = useState<string | null>(null);
  const examples = ["苏州", "杭州", "成都"];

  return (
    <div className="destination-start">
      <p className="eyebrow">从地图出发，不填长表格</p>
      <h1>想把哪里变成一段行程？</h1>
      <Composer />
      <div className="destination-examples" aria-label="推荐目的地">
        {examples.map((city) => (
          <button
            key={city}
            className="example-chip"
            disabled={choosing !== null}
            onClick={async () => {
              setChoosing(city);
              await resolveDestination(city);
              setChoosing(null);
            }}
          >
            {choosing === city ? "定位中…" : city}
          </button>
        ))}
      </div>
      {state.draft.destination && (
        <div className="destination-confirmed">
          <strong>地图已抵达 {state.draft.destination}</strong>
          <span>继续补充偏好，或直接让旅程展开。</span>
          <ConditionsCard />
        </div>
      )}
      {state.failureDetail && <div className="issue-note">{state.failureDetail}</div>}
    </div>
  );
}

function PanelBody({ tab, goConditions }: { tab: ReadyTab; goConditions?: () => void }) {
  switch (tab) {
    case "plan": return <PlanPanel />;
    case "stay": return <AccommodationPanel />;
    case "transport": return <TransportPanel onGoConditions={goConditions} />;
    case "budget": return <BudgetPanel />;
  }
}

function PanelTabs({ tab, setTab }: { tab: ReadyTab; setTab: (tab: ReadyTab) => void }) {
  return (
    <div className="side-tabs" role="tablist" aria-label="行程内容">
      {READY_TABS.map((meta) => {
        const Icon = meta.icon;
        const selected = tab === meta.id;
        return (
          <button
            key={meta.id}
            className={`side-tab${selected ? " active" : ""}`}
            onClick={() => setTab(meta.id)}
            role="tab"
            aria-selected={selected}
          >
            <Icon size={17} aria-hidden="true" />
            {meta.title}
          </button>
        );
      })}
    </div>
  );
}

type Detent = "compact" | "medium" | "large";

function MobileLayer({
  tab,
  setTab,
  hasPlan,
  editingConditions,
  setEditingConditions
}: {
  tab: ReadyTab;
  setTab: (tab: ReadyTab) => void;
  hasPlan: boolean;
  editingConditions: boolean;
  setEditingConditions: (value: boolean) => void;
}) {
  const [detent, setDetent] = useState<Detent>("medium");
  const [viewportHeight, setViewportHeight] = useState(() => window.innerHeight);
  const [liveHeight, setLiveHeight] = useState<number | null>(null);
  const sheetRef = useRef<HTMLDivElement | null>(null);
  const dragRef = useRef<{ pointerY: number; height: number; samples: { height: number; time: number }[] } | null>(null);
  const heights = useMemo(() => ({
    compact: hasPlan ? 174 : 250,
    medium: Math.min(Math.max(viewportHeight * 0.61, 390), 570, Math.max(viewportHeight - 20, 320)),
    large: Math.max(viewportHeight - 20, 320)
  }), [hasPlan, viewportHeight]);
  const height = liveHeight ?? heights[detent];

  useEffect(() => {
    const update = () => setViewportHeight(window.innerHeight);
    window.addEventListener("resize", update);
    return () => window.removeEventListener("resize", update);
  }, []);

  const moveDetent = (up: boolean) => {
    const order: Detent[] = ["compact", "medium", "large"];
    const index = order.indexOf(detent);
    setDetent(order[Math.min(Math.max(index + (up ? 1 : -1), 0), order.length - 1)]);
  };

  const onPointerDown = (event: React.PointerEvent<HTMLButtonElement>) => {
    const currentHeight = sheetRef.current?.getBoundingClientRect().height ?? height;
    dragRef.current = { pointerY: event.clientY, height: currentHeight, samples: [{ height: currentHeight, time: performance.now() }] };
    setLiveHeight(currentHeight);
    event.currentTarget.setPointerCapture(event.pointerId);
  };

  const onPointerMove = (event: React.PointerEvent<HTMLButtonElement>) => {
    const drag = dragRef.current;
    if (!drag) return;
    const now = performance.now();
    const next = Math.min(Math.max(drag.height + drag.pointerY - event.clientY, heights.compact), heights.large);
    setLiveHeight(next);
    drag.samples.push({ height: next, time: now });
    drag.samples = drag.samples.filter((sample) => now - sample.time < 140);
  };

  const onPointerUp = () => {
    const drag = dragRef.current;
    if (!drag) return;
    const first = drag.samples[0];
    const last = drag.samples.at(-1) ?? first;
    const seconds = Math.max((last.time - first.time) / 1000, 0.016);
    const velocity = (last.height - first.height) / seconds;
    const projected = last.height + velocity * 0.18;
    const next = (Object.entries(heights) as [Detent, number][])
      .sort((a, b) => Math.abs(a[1] - projected) - Math.abs(b[1] - projected))[0][0];
    dragRef.current = null;
    setDetent(next);
    setLiveHeight(null);
  };

  return (
    <div ref={sheetRef} className={`mobile-sheet mobile-only${liveHeight !== null ? " dragging" : ""}`} style={{ height }}>
      <button
        className="sheet-handle"
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        onDoubleClick={() => moveDetent(detent !== "large")}
        aria-label="调整地图面板高度"
        aria-valuetext={detent === "compact" ? "仅显示主要内容" : detent === "medium" ? "显示主要内容" : "几乎全屏显示"}
      >
        <i />
      </button>
      <button className="sheet-expand" onClick={() => moveDetent(detent !== "large")} aria-label="切换面板高度">
        {detent === "large" ? <ChevronDown size={18} aria-hidden="true" /> : <ChevronUp size={18} aria-hidden="true" />}
      </button>
      <PanelScaffold
        tab={tab}
        setTab={setTab}
        hasPlan={hasPlan}
        editingConditions={editingConditions}
        setEditingConditions={setEditingConditions}
      />
    </div>
  );
}

function LibraryPanel({ onClose }: { onClose: () => void }) {
  const { state, loadTrip, deleteTrip } = useApp();
  useEffect(() => {
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    window.addEventListener("keydown", closeOnEscape);
    return () => window.removeEventListener("keydown", closeOnEscape);
  }, [onClose]);

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <section className="modal-card" role="dialog" aria-modal="true" aria-labelledby="library-title" onClick={(event) => event.stopPropagation()}>
        <div className="modal-head">
          <div>
            <h2 id="library-title">旅册</h2>
            <p className="sub-text">在这台浏览器保存的行程</p>
          </div>
          <button className="chip-btn" onClick={onClose}>完成</button>
        </div>
        {state.savedTrips.length === 0 && <div className="empty-note">还没有保存的行程。</div>}
        {state.savedTrips.map((trip) => (
          <div key={trip.id} className="trip-row">
            <span className="t-title">{trip.title}</span>
            <button className="mini-btn" onClick={() => { loadTrip(trip.id); onClose(); }}>打开</button>
            <button className="mini-btn danger" onClick={() => deleteTrip(trip.id)}>删除</button>
          </div>
        ))}
      </section>
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
      {plan.days.map((day, index) => (
        <section key={index}>
          <h2>{day.title}</h2>
          {day.stops.map((stop, stopIndex) => (
            <p key={stopIndex}>
              <strong>{stop.arrivalText}–{stop.departureText}</strong> {stop.place.name}
              {stop.place.address ? `（${stop.place.address.slice(0, 80)}）` : ""}
            </p>
          ))}
        </section>
      ))}
    </div>
  );
}
