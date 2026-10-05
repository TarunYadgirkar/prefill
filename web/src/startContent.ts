import { isPrefillFrame, startPage, type PageEnvironment } from "./page";
import { answerPageNeeds } from "./pageNeeds";

// Chrome leaves a reloaded or updated extension's old scripts running in open tabs, cut off
// from the extension, and starts a new copy beside them.
function isConnected(): boolean {
  try {
    return (browser.runtime as { id?: string }).id !== undefined;
  } catch {
    return false;
  }
}

export function startContent(kind: NonNullable<PageEnvironment["browser"]>): void {
  const frame = {
    protocol: location.protocol,
    hostname: location.hostname,
    isSecureContext: window.isSecureContext,
    isTopFrame: window === window.top,
  };
  // The script loads into every frame, so a frame Prefill doesn't run in gets nothing added.
  if (!isPrefillFrame(frame)) return;
  // Registered before the page's own listeners, so a cut-off copy steps aside before it
  // shows anything from what it fetched earlier.
  const retire = (): void => {
    if (isConnected()) return;
    stop();
    document.removeEventListener("focusin", retire, true);
  };
  document.addEventListener("focusin", retire, true);
  const stop = startPage({
    doc: document,
    win: window,
    ...frame,
    send: (request) => browser.runtime.sendMessage(request),
    browser: kind,
  });

  // Safari's sheet asks the top frame only.
  if (frame.isTopFrame) {
    browser.runtime.onMessage.addListener((message, sender) =>
      answerPageNeeds(message, sender, browser.runtime.id, {
        doc: document,
        protocol: location.protocol,
        hostname: location.hostname,
      }),
    );
  }
}
