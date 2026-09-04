export interface AssistantAction {
  type: string;
  value?: unknown;
}

export interface AssistantEnvelope {
  reply: string | null;
  actions: AssistantAction[];
}

export function parseAssistantEnvelope(text: string): AssistantEnvelope {
  for (const candidate of jsonCandidates(text)) {
    try {
      const payload = JSON.parse(candidate) as { reply?: unknown; actions?: unknown };
      const reply = typeof payload.reply === "string" && payload.reply.trim()
        ? payload.reply.trim()
        : null;
      const actions = Array.isArray(payload.actions)
        ? payload.actions.filter(isAssistantAction).slice(0, 16)
        : [];
      if (reply || actions.length > 0) return { reply, actions };
    } catch {
      // Try the next balanced JSON object in the response.
    }
  }
  return { reply: null, actions: [] };
}

export function partialAssistantReply(text: string): string | null {
  const complete = parseAssistantEnvelope(text).reply;
  if (complete) return complete;
  const match = text.match(/"reply"\s*:\s*"((?:\\.|[^"\\])*)/);
  if (!match?.[1]) return null;
  try {
    return JSON.parse(`"${match[1].replace(/"$/, "")}"`);
  } catch {
    return match[1].replace(/\\n/g, "\n").replace(/\\"/g, '"').trim() || null;
  }
}

export function normalizeActionType(type: string): string {
  const aliases: Record<string, string> = {
    set_destination: "setDestination",
    set_origin: "setOrigin",
    set_start_date: "setStartDate",
    set_day_count: "setDayCount",
    set_travelers: "setTravelers",
    set_budget: "setBudget",
    set_pace: "setPace",
    add_interest: "addInterest",
    remove_interest: "removeInterest",
    set_travel_mode: "setTransportMode",
    set_long_distance_mode: "setLongDistanceMode",
    generate_plan: "generatePlan"
  };
  return aliases[type] ?? type;
}

function isAssistantAction(value: unknown): value is AssistantAction {
  return Boolean(
    value &&
    typeof value === "object" &&
    typeof (value as { type?: unknown }).type === "string"
  );
}

function jsonCandidates(text: string): string[] {
  const trimmed = text.trim();
  const candidates = new Set<string>();
  if (trimmed) candidates.add(trimmed);
  const unfenced = trimmed.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
  if (unfenced) candidates.add(unfenced);

  let depth = 0;
  let start = -1;
  let quoted = false;
  let escaped = false;
  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (quoted) {
      if (escaped) escaped = false;
      else if (character === "\\") escaped = true;
      else if (character === '"') quoted = false;
      continue;
    }
    if (character === '"') {
      quoted = true;
      continue;
    }
    if (character === "{") {
      if (depth === 0) start = index;
      depth += 1;
    } else if (character === "}" && depth > 0) {
      depth -= 1;
      if (depth === 0 && start >= 0) {
        candidates.add(text.slice(start, index + 1));
        start = -1;
      }
    }
  }
  return [...candidates];
}
