import { describe, expect, it } from "vitest";
import { isLegacyLocalService, normalizeServiceURL, resolveServiceURL } from "./service-config";

describe("default service routing", () => {
  it("uses the deployed website origin without asking users to configure localhost", () => {
    expect(resolveServiceURL("", "", "https://travel.example")).toBe("https://travel.example/");
    expect(resolveServiceURL("", "https://api.example/travel", "https://web.example")).toBe("https://api.example/travel/");
  });
  it("keeps overrides explicit and rejects insecure or credential-bearing public URLs", () => {
    for (const value of ["http://example.org", "https://user:secret@example.org", "https://example.org?key=secret", "javascript:alert(1)"]) {
      expect(normalizeServiceURL(value)).toBeNull();
    }
    expect(normalizeServiceURL("http://localhost:8787")).toBe("http://localhost:8787/");
    expect(resolveServiceURL("https://own.example", "https://default.example", "https://web.example")).toBe("https://own.example/");
  });
  it("migrates only the old development default, not users' explicit endpoints", () => {
    expect(isLegacyLocalService("http://127.0.0.1:8787/")).toBe(true);
    expect(isLegacyLocalService("https://my.example/")).toBe(false);
  });
});
