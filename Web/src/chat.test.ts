import { describe, expect, it } from "vitest";
import { normalizeActionType, parseAssistantEnvelope, partialAssistantReply } from "./chat";

describe("assistant response parsing", () => {
  it("extracts a fenced action envelope without exposing its JSON", () => {
    const parsed = parseAssistantEnvelope(`\n\`\`\`json\n{
      "reply": "已经改成四天慢游。",
      "actions": [{"type": "set_day_count", "value": 4}, {"type": "generate_plan"}]
    }\n\`\`\``);

    expect(parsed.reply).toBe("已经改成四天慢游。");
    expect(parsed.actions).toHaveLength(2);
    expect(normalizeActionType(parsed.actions[0].type)).toBe("setDayCount");
    expect(normalizeActionType(parsed.actions[1].type)).toBe("generatePlan");
  });

  it("finds a balanced JSON object after model preamble", () => {
    const parsed = parseAssistantEnvelope('好的，我来安排。 {"reply":"先去苏州。","actions":[{"type":"set_destination","value":"苏州"}]} 完成');
    expect(parsed).toEqual({
      reply: "先去苏州。",
      actions: [{ type: "set_destination", value: "苏州" }]
    });
  });

  it("shows only the natural-language reply while a stream is incomplete", () => {
    expect(partialAssistantReply('{"reply":"我先把每天的景点铺松一点')).toBe("我先把每天的景点铺松一点");
  });
});
