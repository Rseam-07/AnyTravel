import { describe, expect, it } from "vitest";
import { saveSettingsToStorage, type WebSettings } from "./api";

class MemoryStorage {
  private values = new Map<string, string>();
  failNextSet = false;

  getItem(key: string) { return this.values.get(key) ?? null; }
  setItem(key: string, value: string) {
    if (this.failNextSet) {
      this.failNextSet = false;
      throw new DOMException("Storage disabled", "QuotaExceededError");
    }
    this.values.set(key, value);
  }
  removeItem(key: string) { this.values.delete(key); }
}

const settings: WebSettings = {
  backendURL: "https://travel.example/",
  deepseekKey: "tab-only-key",
  deepseekModel: "deepseek-chat"
};

describe("settings storage transaction", () => {
  it("separates persistent preferences from the tab-scoped assistant key", () => {
    const local = new MemoryStorage();
    const session = new MemoryStorage();

    saveSettingsToStorage(settings, local, session);

    expect(local.getItem("anytravel-web:settings")).toBe(JSON.stringify({
      backendURL: settings.backendURL,
      deepseekModel: settings.deepseekModel
    }));
    expect(local.getItem("anytravel-web:settings")).not.toContain(settings.deepseekKey);
    expect(session.getItem("anytravel-web:assistant-session-key")).toBe(settings.deepseekKey);
  });

  it("restores both previous values when the second storage write fails", () => {
    const local = new MemoryStorage();
    const session = new MemoryStorage();
    local.setItem("anytravel-web:settings", "previous-local");
    session.setItem("anytravel-web:assistant-session-key", "previous-session");
    session.failNextSet = true;

    expect(() => saveSettingsToStorage(settings, local, session)).toThrow();
    expect(local.getItem("anytravel-web:settings")).toBe("previous-local");
    expect(session.getItem("anytravel-web:assistant-session-key")).toBe("previous-session");
  });
});
