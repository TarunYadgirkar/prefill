import "../background";

declare const chrome: {
  runtime: { onInstalled: { addListener(listener: (details: { reason: string }) => void): void } };
  tabs: { query(query: { url: string[] }): Promise<{ id?: number }[]> };
  scripting: { executeScript(injection: { target: { tabId: number; allFrames: boolean }; files: string[] }): Promise<unknown> };
};

const MATCHES = ["https://*/*", "http://localhost/*", "http://127.0.0.1/*"];

// Chrome only adds content scripts to pages loaded after the extension, so a tab opened
// before Prefill was installed, reloaded or updated would show nothing until it's reloaded.
// Prefill adds itself to those tabs; any old copy there steps aside on the next focus. Like
// the manifest it goes into every frame, and bails out in frames it doesn't run in.
chrome.runtime.onInstalled.addListener(({ reason }) => {
  if (reason !== "install" && reason !== "update") return;
  void chrome.tabs.query({ url: MATCHES }).then((tabs) => {
    for (const { id } of tabs) {
      if (id === undefined) continue;
      const target = { tabId: id, allFrames: true };
      chrome.scripting.executeScript({ target, files: ["content.js"] }).catch(() => undefined);
    }
  });
});
