// MIT-derived ledger, stored by the AnyTravel parent only after an IndexedDB commit.
(() => {
  const pending = new Map();
  let started = false;
  window.addEventListener("message", async event => {
    if (event.source !== parent || event.origin !== location.origin) return;
    const msg = event.data;
    if (msg?.type === "anytravel-ledger-result" && pending.has(msg.id)) {
      const p = pending.get(msg.id); clearTimeout(p.timer); pending.delete(msg.id);
      msg.error ? p.reject(new Error(msg.error)) : p.resolve(); return;
    }
    if (msg?.type === "anytravel-ledger-theme") { document.documentElement.classList.toggle("dark", !!msg.dark); return; }
    if (msg?.type !== "anytravel-ledger-init" || started) return;
    started = true;
    document.documentElement.classList.toggle("dark", !!msg.dark);
    try {
      await window.TravelLedger.init({ root: "#ledger-root", tripId: msg.bookId, config: {}, adapter: {
        mode: "local", load: () => msg.snapshot,
        save(snapshot) { return new Promise((resolve, reject) => {
          const id = crypto.randomUUID();
          pending.set(id, { resolve, reject, timer: setTimeout(() => { pending.delete(id); reject(new Error("保存未完成，请重试。")); }, 15000) });
          parent.postMessage({ type: "anytravel-ledger-save", id, snapshot, bookId: msg.bookId }, location.origin);
        }); }
      } });
    } catch { document.querySelector("#ledger-root").textContent = "账本没有打开，请返回手册后重新进入。"; }
  });
  parent.postMessage({ type: "anytravel-ledger-ready" }, location.origin);
})();
