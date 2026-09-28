import { describe, expect, it } from "vitest";
import { channelStatusFromHealth } from "./api";

describe("channelStatusFromHealth", () => {
  it("shows local assistant and public map fallbacks as usable capabilities", () => {
    const channels = channelStatusFromHealth({
      service: "anytravel-companion",
      status: "ok",
      assistant: "local",
      amap: "public"
    });

    expect(channels.find(channel => channel.name === "assistant")).toMatchObject({
      status: "configured",
      detail: "智能向导（本地理解）"
    });
    expect(channels.find(channel => channel.name === "amap")).toMatchObject({
      status: "configured",
      detail: "地点与路线（含 OpenStreetMap 备用）（公开源）"
    });
  });
});
