import { defineConfig } from "vitest/config";

export default defineConfig({
  // The classifier tests read testbed/form.html from the repository root.
  server: { fs: { allow: [".."] } },
  test: {
    environment: "happy-dom",
    include: ["src/**/*.test.ts"],
  },
});
