// @vitest-environment node
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const RESOURCES = new URL("../../Extension/Resources/", import.meta.url);
const PNG_SIGNATURE = "89504e470d0a1a0a";

interface Manifest {
  icons: Record<string, string>;
  action: { default_icon: Record<string, string>; default_popup: string };
}

const manifest = JSON.parse(readFileSync(new URL("manifest.json", RESOURCES), "utf8")) as Manifest;

function pngSize(path: string): { width: number; height: number } {
  const bytes = readFileSync(new URL(path, RESOURCES));
  expect(bytes.subarray(0, 8).toString("hex")).toBe(PNG_SIGNATURE);
  return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
}

describe.each([
  ["icons", manifest.icons],
  ["action.default_icon", manifest.action.default_icon],
])("manifest %s", (_name, icons) => {
  it.each(Object.entries(icons))("%s px points at a square PNG of that size", (size, path) => {
    expect(existsSync(new URL(path, RESOURCES))).toBe(true);
    expect(pngSize(path)).toEqual({ width: Number(size), height: Number(size) });
  });
});

describe("Chrome manifest", () => {
  // Chrome names an unpacked extension after its key: the first 128 bits of the key's
  // SHA-256, one letter a to p per hex digit. The Mac app allows only that ID.
  it("has the key whose ID the Mac app's native host allows", () => {
    const chrome = JSON.parse(readFileSync(new URL("../chromium/manifest.json", import.meta.url), "utf8")) as { key: string };
    const digest = createHash("sha256").update(Buffer.from(chrome.key, "base64")).digest("hex").slice(0, 32);
    const id = digest.replace(/[0-9a-f]/gu, (digit) => String.fromCharCode(97 + parseInt(digit, 16)));
    const installer = readFileSync(new URL("../../MacApp/Relay/HostInstaller.swift", import.meta.url), "utf8");
    expect(installer).toContain(`static let extensionID = "${id}"`);
  });
});

describe("manifest action", () => {
  it("opens Safari's Prefill sheet from the page menu", () => {
    expect(manifest.action.default_popup).toBe("popup.html");
  });
});
