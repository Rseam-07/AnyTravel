# AnyTravel Web design QA

Date: 2026-09-04

Reference: the current iOS planner screens and design tokens in `../AnyTravel/`, especially `Documentation/Screenshots/route-ready.png`, `complete-plan.png`, `itinerary-editor.png`, and `Design/AnyTravelTheme.swift`.

## Visual and interaction checks

- Mobile, 390 × 844: passed. The map remains the canvas, the planner uses a floating three-height sheet, controls remain reachable, and the sheet can expand without clipping the itinerary.
- Desktop, 1440 × 900: passed. The planner becomes a left floating panel, the map fills the viewport after tiles settle, and route controls remain clear of the panel.
- Wide desktop, 1512 × 830: passed. Once the viewport reaches the wide-screen ratio, the 430 px planner rail keeps 18 px margins at both top and bottom, while the 620 px title bar shifts right and is centered exactly in the remaining map canvas.
- Standard desktop, 1366 × 900: passed. Below the wide-screen ratio the original floating-card placement and viewport-centered 720 px title bar remain unchanged.
- Information architecture: passed. The ready state exposes the same four primary sections as iOS: 行程、住宿、交通、费用.
- Map-to-panel synchronization: passed. Switching from day 1 to day 2 changes the visible stops, route color, selected day, and map focus together.
- Visual language: passed. Route teal, warm day accents, ink color, translucent materials, rounded controls, restrained shadows, numbered markers, and white route halo follow the iOS system.
- Motion and accessibility: passed. Tap targets are at least 44 px, icons have accessible names, reduced-motion and reduced-transparency modes are covered, and no emoji is used as interface iconography.

## Real-flow checks

- 苏州 selection and three-day itinerary generation: passed.
- Current-day-only route and stop rendering: passed.
- Live ticket filtering: passed. Only 拙政园 showed a ticket quote; 观前街、东方之门、金鸡湖、苏州博物馆 did not inherit unrelated paid products.
- Public railway lookup: passed. 上海往返苏州 returned 8 outbound and 8 return options with seat and price data.
- Wide-screen railway flow: passed. 宁波往返杭州 returned 8 outbound and 8 return options while the full-height rail and right-centered title bar remained stable.
- Accommodation fallback: passed. With no hotel provider configured, the app shows honest area suggestions instead of invented hotel quotes.
- Budget roll-up: passed. Transport, ticket, local transit, food, and unavailable lodging are labeled by source and summed consistently for two travelers.
- Save and library: passed. A trip saves locally, appears in 旅册, and produces one transient confirmation.
- Inline adjustment: passed. Natural-language changes regenerate the itinerary and update the map rather than only changing copy.

## Automated checks

- Web unit tests: 7 passed.
- Backend tests: 48 passed.
- Knowledge validation: 162 destinations, including 141 in China, 1,234 places, 12 planning rules, and 867 unique sources.
- Production build: passed. Vite reports a non-blocking large-chunk warning because the map renderer is currently bundled with the main application.

No open P0, P1, or P2 visual defects remain in the checked flows.

final result: passed
