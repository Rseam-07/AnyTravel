import { useEffect, useRef } from "react";
import type { Handbook, LedgerSnapshot } from "./model";

export default function LedgerFrame({ book, dark, onSave }: { book: Handbook; dark: boolean; onSave: (snapshot: LedgerSnapshot) => Promise<void> }) {
  const frame = useRef<HTMLIFrameElement>(null), latest = useRef({ book, dark, onSave }); latest.current = { book, dark, onSave };
  useEffect(() => {
    function receive(e: MessageEvent) {
      if (e.origin !== location.origin || e.source !== frame.current?.contentWindow) return;
      const msg = e.data, { book, dark, onSave } = latest.current;
      if (msg?.type === "anytravel-ledger-ready") frame.current?.contentWindow?.postMessage({ type: "anytravel-ledger-init", bookId: book.id, snapshot: book.ledger, dark }, location.origin);
      if (msg?.type === "anytravel-ledger-save" && msg.bookId === book.id) {
        const source = frame.current?.contentWindow;
        void onSave(msg.snapshot).then(() => source?.postMessage({ type: "anytravel-ledger-result", id: msg.id }, location.origin)).catch(e => source?.postMessage({ type: "anytravel-ledger-result", id: msg.id, error: e instanceof Error ? e.message : "保存失败" }, location.origin));
      }
    }
    window.addEventListener("message", receive); return () => window.removeEventListener("message", receive);
  }, []);
  useEffect(() => { frame.current?.contentWindow?.postMessage({ type: "anytravel-ledger-theme", dark }, location.origin); }, [dark]);
  return <iframe ref={frame} title="同行账本：记账、同行人和结算" className="hb-ledger-frame" src={`${import.meta.env.BASE_URL}vendor/travel-plan-page/ledger.html`} />;
}
