# Travel-Plan-Page integration

Source: https://github.com/do-tongxue/Travel-Plan-Page
Revision: ed869d21b19b7afb4a33fef97715c1091f087563
License: MIT (see LICENSE in this directory)
Copyright (c) 2026 Travel Template contributors

Reused: ledger.js, ledger.css, runtime-storage.js. AnyTravel adds a persistence
adapter, host bridge and brand stylesheet. The trip-data test fixture is adapted
from the upstream canonical fixture. No upstream map backgrounds, boundary
datasets, photographs, or personal travel data are shipped.

The main map uses OpenFreeMap / OpenStreetMap attribution. Road geometry uses
the FOSSGIS OSRM foot/car service; its provider and geometry status are shown on
the map. Dashed curves represent itinerary order, not navigation instructions.
