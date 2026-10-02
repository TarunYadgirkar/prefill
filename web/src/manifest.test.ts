// @vitest-environment node
import { existsSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const RESOURCES = new URL("../../Extension/Resources/", import.meta.url);
const PNG_SIGNATURE = "89504e470d0a1a0a";

interface Manifest {
  icons: Record<string, string>;
  action: { default_icon: Record<string, string> };
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
