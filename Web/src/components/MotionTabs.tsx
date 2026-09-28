import { useLayoutEffect, useRef, type ReactNode } from "react";

/** Interrupted selections retain their position and velocity; one spring owns transform. */
export default function MotionTabs({ items, value, onChange, label, className = "" }: {
  items: { id: string; content: ReactNode }[]; value: string;
  onChange: (id: string) => void; label: string; className?: string;
}) {
  const root = useRef<HTMLDivElement>(null);
  const thumb = useRef<HTMLSpanElement>(null);
  const motion = useRef({ x: 0, v: 0, target: 0, ready: false });
  useLayoutEffect(() => {
    let frame = 0, last = 0;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
    const paint = () => { if (thumb.current) thumb.current.style.transform = `translateX(${motion.current.x}px)`; };
    const step = (time: number) => {
      const m = motion.current;
      const dt = Math.min((time - (last || time - 16)) / 1000, 0.032);
      last = time;
      // Fixed substeps make stiffness independent of display refresh rate.
      const count = Math.max(1, Math.ceil(dt / 0.008));
      for (let i = 0; i < count; i++) {
        const h = dt / count;
        m.v += ((m.target - m.x) * 350 - m.v * 28) * h;
        m.x += m.v * h;
      }
      if (Math.abs(m.target - m.x) < 0.15 && Math.abs(m.v) < 0.5) { m.x = m.target; m.v = 0; paint(); return; }
      paint(); frame = requestAnimationFrame(step);
    };
    const update = () => {
      const button = root.current?.querySelector<HTMLButtonElement>(`button[aria-checked="true"]`);
      if (!button || !thumb.current) return;
      cancelAnimationFrame(frame);
      motion.current.target = button.offsetLeft;
      thumb.current.style.width = `${button.offsetWidth}px`;
      if (!motion.current.ready || reduced.matches) {
        motion.current.x = motion.current.target; motion.current.v = 0; motion.current.ready = true; paint();
      } else { last = 0; frame = requestAnimationFrame(step); }
      const rail = root.current;
      if (rail) {
        if (button.offsetLeft < rail.scrollLeft) rail.scrollLeft = button.offsetLeft;
        else if (button.offsetLeft + button.offsetWidth > rail.scrollLeft + rail.clientWidth) rail.scrollLeft = button.offsetLeft + button.offsetWidth - rail.clientWidth;
      }
    };
    update();
    const observer = new ResizeObserver(update);
    if (root.current) observer.observe(root.current);
    reduced.addEventListener("change", update);
    return () => { cancelAnimationFrame(frame); observer.disconnect(); reduced.removeEventListener("change", update); };
  }, [value, items.length]);
  return <div className={`motion-tabs ${className}`} ref={root} role="radiogroup" aria-label={label}>
    <span className="motion-tab-thumb" ref={thumb} aria-hidden="true" />
    {items.map((item, index) => <button type="button" key={item.id} role="radio" aria-checked={value === item.id}
      tabIndex={value === item.id ? 0 : -1} onClick={() => onChange(item.id)}
      onKeyDown={event => {
        let next = index;
        if (event.key === "ArrowRight" || event.key === "ArrowDown") next = (index + 1) % items.length;
        else if (event.key === "ArrowLeft" || event.key === "ArrowUp") next = (index - 1 + items.length) % items.length;
        else if (event.key === "Home") next = 0;
        else if (event.key === "End") next = items.length - 1;
        else return;
        event.preventDefault(); onChange(items[next].id);
        root.current?.querySelectorAll<HTMLButtonElement>("button")[next]?.focus();
      }}>{item.content}</button>)}
  </div>;
}
